# frozen_string_literal: true

module ExtractEval
  module CLI
    # The options shared by the commands that call a model. Settings resolve
    # flag first, then the config entry, then config.yml's defaults.
    class ModelCommand < Command
      # How close to the best field accuracy a model must come to compete on
      # price: 0.02 is two percentage points.
      VALUE_MARGIN = 0.02

      # What each leaderboard column means, printed under the leaderboard.
      GLOSSARY = {
        "effort"    => "Reasoning effort sent to the model as OpenRouter's reasoning.effort. \"default\" sends none, " \
                       "and the model decides. Jev takes no effort.",
        "temp"      => "Sampling temperature sent to the model. \"default\" sends none; Jev takes none.",
        "accuracy"  => "Mean per-field score over the cases. Enum, boolean and integer fields must match the truth " \
                       "exactly; multi-select fields score their overlap with it (Jaccard). A field the text never " \
                       "answers is right only when left empty (null, \"\" or []); 0 or false counts as wrong.",
        "exact"     => "Share of cases with every field right: the form prefills with nothing to correct.",
        "restraint" => "Of the fields the text never answers, the share the model left empty instead of guessing. " \
                       "\"-\" when every field has an answer, as in the clear dataset.",
        "valid"     => "Share of replies that were a JSON object holding every schema field. A reply that is not " \
                       "JSON scores 0 on every metric.",
        "errors"    => "Cases whose call failed outright (an API or network error), so they have no scores at all.",
        "time"      => "Wall-clock time for the experiment. Experiments run side by side and share the network, " \
                       "so compare times within one run only.",
        "tok_in"    => "Input tokens sent, summed over the cases, as the provider counted them.",
        "tok_out"   => "Output tokens received, summed over the cases; reasoning tokens are included where the " \
                       "provider bills them as output.",
        "score"     => "The mean of accuracy, exact and restraint; of accuracy and exact alone where restraint is " \
                       "\"-\". The last table ranks every experiment by it.",
        "cost"      => "US dollars. For OpenRouter models, what OpenRouter billed for each call. For Jev, input tokens " \
                       "at TypeSafe's $0.042 per million; its output is free."
      }.freeze

      def self.inherited(subclass)
        super
        subclass.extend(Dry::CLI::UI::Flags)
        subclass.flags(:output)
        subclass.option :config, default: Config::DEFAULT_PATH, desc: "The comparison matrix"
        subclass.option :effort,
          aliases: ["-e"],
          desc:    "Reasoning effort: default, #{OpenRouterAdapter::EFFORTS.join(", ")} (overrides config.yml)"
        subclass.option :temperature, aliases: ["-t"], desc: "Sampling temperature, or 'default' to send none (overrides config.yml)"
        subclass.option :max_tokens, desc: "Output token cap, reasoning included (overrides config.yml)"
        subclass.option :case,
          type:    :array,
          aliases: ["-c"],
          default: [],
          desc:    "Only these cases, by prefix: -c 01,09 or -c 03_home"
        subclass.option :parallelism, aliases: ["-p"], desc: "Cases in flight at once, per model (overrides config.yml)"
        subclass.option :project,
          desc: "Braintrust project name; default is the BRAINTRUST_PROJECT_ID project, " \
                "else config.yml's project"
        subclass.option :open,
          type:    :boolean,
          default: true,
          desc:    "Open the best experiment in the browser when done (no effect with --local)"
        subclass.option :local,
          type:    :boolean,
          default: false,
          desc:    "Score locally without logging to Braintrust (still calls OpenRouter)"
      end

      private

      # @return [Hash{String => Object}] the setting flags that were given
      def overrides(options)
        { "effort" => options[:effort], "temperature" => options[:temperature], "max_tokens" => options[:max_tokens] }
      end

      def experiment(contender, config, options, dataset:)
        Experiment.new(
          adapter:     adapter(contender),
          fixtures:    fixtures(options[:case], dataset: dataset),
          project:     options[:local] ? nil : (options[:project] || config.project || Experiment::DEFAULT_PROJECT),
          project_id:  options[:local] || options[:project] ? nil : ENV["BRAINTRUST_PROJECT_ID"].to_s[/\S+/],
          parallelism: Integer(options[:parallelism] || config.defaults["parallelism"])
        )
      end

      # The contenders a command runs: the models named on the command line,
      # or every model config.yml lists.
      #
      # @param models [Array<String>] as given to -m, possibly comma-separated
      # @return [Array<Config::Contender>]
      # @raise [Error] when neither names any model
      def contenders(config, models, options)
        models = models.flat_map { it.split(",") }
        found = models.empty? ? config.contenders(overrides(options)) : config.contenders_for(models, overrides(options))
        raise Error, "no models: list some under vendors in #{config.path}, or pass -m" if found.empty?

        found
      end

      # Runs the experiments side by side, a progress bar each. What would
      # print as a warning meanwhile, failed cases included, goes to
      # {#warnings} instead.
      #
      # @param runs [Array<Experiment>]
      # @param concurrency [Integer] experiments at once; 0 runs them all together
      # @return [Array<Experiment::Summary>]
      def execute(runs, concurrency: 0)
        summaries = Array.new(runs.size)
        warnings.capture { bars(runs, summaries, concurrency) }
        summaries.compact.each { |s| s.errors.each { warnings.record("[#{s.model} effort=#{s.effort || "default"} #{s.dataset}] #{it}") } }
        summaries.compact
      end

      # @return [Warnings] what this command has held back from the screen
      def warnings = @warnings ||= Warnings.new

      def bars(runs, summaries, concurrency)
        ProgressBars.for(ui).run("Running #{runs.size} experiment#{"s" unless runs.size == 1}",
          concurrent: concurrency.zero? || concurrency) do |multi|
          runs.each_with_index do |run, index|
            multi.progress(run.name, total: run.fixtures.size) do |bar|
              summaries[index] = run.run(on_case: -> { bar.advance })
            end
          end
        end
      end

      # @param names [Array<String>] as given to -d, possibly comma-separated
      # @return [Array<String>]
      # @raise [Error] on an unknown dataset, before anything is spent
      def datasets(names)
        names.flat_map { it.split(",") }.uniq.tap { |list| list.each { Fixture.all(dataset: it) } }
      end

      # Prints what the block writes, then the leaderboard, its glossary and
      # the scores; then says where the warnings went, if any, and opens the
      # best-scoring experiment.
      #
      # With -o, the block's output goes to the file alone, and the rest to
      # both, each drawn for its own stream. The file is in color and ends
      # with the time it was closed, as dry-cli-ui's own reports do.
      #
      # @param summaries [Array<Experiment::Summary>]
      # @param output [String, nil] what -o was given: nil, "-", "" for the default file, or a path
      # @param open [Boolean]
      # @return [void]
      def report(summaries, output:, open:, &details)
        path = invocation.report_path(output)
        if path
          File.open(path, "w") do |file|
            report = Dry::CLI::UI::Report.new(file)
            writing_to(report) do
              details&.call
              leaderboard(summaries)
            end
            report.puts "Closed at #{Time.now.strftime("%Y-%m-%d %H:%M:%S %z")}"
          end
        else
          details&.call
        end
        leaderboard(summaries)
        status_box(:info, "Report written to #{relative(path)}", stream: err) if path
        save_warnings
        url = summaries.max_by { score(it) || -1 }&.permalink
        status_box(:warning, "could not open #{url}", stream: err) if open && url && !Runtime.browse(url)
      end

      # Saves {#warnings}, if there are any, to
      # log/<command>.warnings.<YYYY-MM-DD>.<HHMMSS>.log at the repository
      # root, stamped with the time the process started, and says how many.
      #
      # @return [void]
      def save_warnings
        return if warnings.none?

        stamp = Dry::CLI::UI.started_at.strftime("%Y-%m-%d.%H%M%S")
        path = File.join(Dry::CLI::UI::Invocation.root(Dir.pwd), "log", "#{invocation.action}.warnings.#{stamp}.log")
        FileUtils.mkdir_p(File.dirname(path))
        warnings.save(path)
        count = warnings.count
        status_box(:warning, "#{count} #{count == 1 ? "Warning was" : "Warnings were"} recorded in #{relative(path)}", stream: err)
      end

      # @return [Dry::CLI::UI::Invocation] how the command was run, which names its files
      def invocation = ui.send(:invocation)

      def relative(path) = Pathname(path).relative_path_from(Dir.pwd).to_s

      # Points the tables and boxes at another stream while the block runs.
      # They keep the screen's width.
      #
      # @param io [IO, nil] nil to leave them on the screen
      def writing_to(io)
        return yield if io.nil?

        screen = out
        @screen = screen
        @out = io
        @pastel = nil
        yield
      ensure
        if io
          @out = screen
          @screen = nil
          @pastel = nil
        end
      end

      # @param contenders [Array<Config::Contender>]
      # @return [Array<String>] the API keys those contenders' adapters need
      def keys_for(contenders)
        contenders.map { JevAdapter.serves?(it.model) ? "TYPESAFE_API_KEY" : "OPENROUTER_API_KEY" }.uniq
      end

      def adapter(contender)
        return JevAdapter.new(model: contender.model) if JevAdapter.serves?(contender.model)

        OpenRouterAdapter.new(
          model:       contender.model,
          effort:      contender.effort == "default" ? nil : contender.effort,
          temperature: contender.temperature.to_s == "default" ? nil : Float(contender.temperature),
          max_tokens:  contender.max_tokens
        )
      end

      def percent(value) = value.nil? ? "-" : format("%.1f%%", value * 100)

      def dollars(value) = format("$%.4f", value.to_f)

      # The best value: the cheapest entry within {VALUE_MARGIN} of the best
      # field accuracy. Entries with errors, or no accuracy, do not compete. A
      # plain accuracy-per-dollar ratio would crown whatever is nearly free,
      # however wrong it is.
      #
      # @param entries [Array<Array(Float, Float, Integer)>] accuracy, cost, errors
      # @return [Integer, nil] the winner's index
      def best_value(entries)
        eligible = entries.each_index.select { entries[it][0] && entries[it][2].zero? }
        return nil if eligible.empty?

        floor = eligible.map { entries[it][0] }.max - VALUE_MARGIN
        eligible.select { entries[it][0] >= floor - 1e-9 }.min_by { entries[it][1] }
      end

      def value_line(label, accuracy, cost)
        out.puts "best value#{label}: #{format("%.1f%%", accuracy * 100)} at #{dollars(cost)}, " \
                 "the cheapest within #{(VALUE_MARGIN * 100).round} points of the best accuracy"
      end

      def contender_label(summary) = "#{summary.model} effort=#{summary.effort || "default"}"

      # Tokens, cost and mean field accuracy per contender, over every
      # dataset it ran.
      def totals(summaries)
        groups = summaries.group_by { [it.model, it.effort, it.temperature] }.values.map do |group|
          accuracies = group.filter_map { it.means["field_accuracy"] }
          { first: group.first, errors: group.sum { it.errors.size },
            accuracy: accuracies.size == group.size ? accuracies.sum / accuracies.size : nil,
            tokens: %i[input_tokens output_tokens cost_usd].to_h { |key| [key, group.sum { it.tokens[key] }] } }
        end
        groups.sort_by! { -(it[:accuracy] || -1) }
        rows = groups.map do |g|
          s = g[:first]
          [s.model, s.effort || "default", s.temperature.nil? ? "default" : s.temperature, percent(g[:accuracy]),
           g[:errors], g[:tokens][:input_tokens], g[:tokens][:output_tokens], dollars(g[:tokens][:cost_usd])]
        end
        best = best_value(groups.map { [it[:accuracy], it[:tokens][:cost_usd], it[:errors]] })
        table(rows, header: %w[model effort temp accuracy errors tok_in tok_out cost], highlight: [best].compact, fill: 0)
        return unless best

        g = groups[best]
        value_line(" overall (#{contender_label(g[:first])})", g[:accuracy], g[:tokens][:cost_usd])
      end

      # The mean of field accuracy, exact match and restraint, over those the
      # experiment has: restraint is nil where every field has an answer.
      #
      # @param summary [Experiment::Summary]
      # @return [Float, nil] 0..1; nil when it has none of them
      def score(summary)
        values = summary.means.values_at("field_accuracy", "exact_match", "restraint").compact
        values.sum / values.size unless values.empty?
      end

      # Every experiment by {#score}, best first, with its cost and its
      # Braintrust page. URLs are never wrapped, so they stay clickable.
      def scores(summaries)
        rows = summaries.sort_by { -(score(it) || -1) }.map do |s|
          [s.model, s.effort || "default", s.dataset, percent(score(s)), dollars(s.tokens[:cost_usd]), s.permalink || "-"]
        end
        table(rows, header: %w[model effort dataset score cost braintrust_url], fill: 0)
      end

      # The best value in each dataset's block of the leaderboard.
      #
      # @param ranked [Array<Experiment::Summary>]
      # @return [Array<Integer>] indices into ranked
      def best_per_dataset(ranked)
        ranked.each_index.group_by { ranked[it].dataset }.values.filter_map do |indices|
          winner = best_value(indices.map { [ranked[it].means["field_accuracy"], ranked[it].tokens[:cost_usd], ranked[it].errors.size] })
          winner && indices[winner]
        end
      end

      # One row per experiment, best field accuracy first, with the best
      # value per dataset; the glossary; the totals, over several datasets;
      # and every experiment by score.
      def leaderboard(summaries)
        ranked = summaries.sort_by { [it.dataset, -(it.means["field_accuracy"] || -1)] }
        rows = ranked.map do |s|
          [s.dataset, s.model, s.effort || "default", s.temperature.nil? ? "default" : s.temperature,
           percent(s.means["field_accuracy"]), percent(s.means["exact_match"]), percent(s.means["restraint"]),
           percent(s.means["valid_json"]), s.errors.size, format("%.1fs", s.duration),
           s.tokens[:input_tokens], s.tokens[:output_tokens], dollars(s.tokens[:cost_usd])]
        end
        best = best_per_dataset(ranked)
        table(rows,
          header:    %w[dataset model effort temp accuracy exact restraint valid errors time tok_in tok_out cost],
          highlight: best)
        best.each do |index|
          s = ranked[index]
          value_line(" [#{s.dataset}] (#{contender_label(s)})", s.means["field_accuracy"], s.tokens[:cost_usd])
        end
        table(GLOSSARY.to_a, header: %w[Term Description], fill: 1, wrap: true)
        totals(summaries) if summaries.map(&:dataset).uniq.size > 1
        scores(summaries)
      end
    end
  end
end
