# frozen_string_literal: true

module ExtractEval
  module CLI
    # One Braintrust experiment per model, each with a per-case breakdown.
    # Without -m, every model config.yml lists. {Compare} runs the same
    # experiments, over several datasets, and prints only the leaderboard.
    class Run < ModelCommand
      desc "Run every case against a model, or every model in config.yml, with a per-case breakdown"

      option :models,
        type:    :array,
        aliases: ["-m"],
        default: [],
        desc:    "Model ids, comma-separated, instead of config.yml's vendors"
      option :dataset,
        type:    :array,
        aliases: ["-d"],
        default: [Fixture::DEFAULT_DATASET],
        desc:    "Datasets under datasets/, comma-separated; each model runs on each"

      example [
        "-d vague                                 # every model in config.yml",
        "-m anthropic/claude-haiku-5.5",
        "-m openai/gpt-4.1-mini -t 0 -c 08,09,10   # only the three hardest cases",
        "-m google/gemini-2.5-flash -e high --local",
        "-m typesafe/jev-router -d vague          # the vague, incomplete texts",
        "-d vague,clear -o                        # both; the breakdowns go to log/"
      ]

      def call(models:, dataset:, **options)
        config = Config.new(options[:config])
        contenders = contenders(config, models, options)
        Runtime.setup!(braintrust: !options[:local], keys: keys_for(contenders))
        ModelCatalog.verify!(contenders)
        runs = datasets(dataset).flat_map { |name| contenders.map { experiment(it, config, options, dataset: name) } }
        summaries = execute(runs)
        report(summaries, output: options[:output], open: options[:open]) do
          summaries.each { breakdown(it, titled: summaries.size > 1) }
        end
      end

      private

      def breakdown(summary, titled: false)
        status_box :info, "#{summary.model} effort=#{summary.effort || "default"} [#{summary.dataset}]" if titled
        rows = summary.cases.map do |result|
          wrong = result.wrong.map { |field, diff| "#{field}: #{diff["actual"].inspect} (want #{diff["expected"].inspect})" }
          [result.fixture.name, result.fixture.difficulty, percent(result.score), wrong.join("\n")]
        end
        table(rows, header: %w[case difficulty field_accuracy wrong], fill: 3, wrap: true)
      end
    end
  end
end
