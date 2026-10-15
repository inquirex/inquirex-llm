# frozen_string_literal: true

module ExtractEval
  module CLI
    # Several models at one setting, side by side: one experiment each.
    class Compare < ModelCommand
      desc "Run every case against several models and print a leaderboard"

      option :models,
        type:    :array,
        aliases: ["-m"],
        default: [],
        desc:    "OpenRouter model ids, comma-separated, instead of config.yml's vendors"
      option :dataset,
        type:    :array,
        aliases: ["-d"],
        default: [Fixture::DEFAULT_DATASET],
        desc:    "Datasets under datasets/, comma-separated; each contender runs on each"
      option :concurrency, default: "0", desc: "Models running at once; 0 runs them all together"
      option :dry_run,
        type:    :boolean,
        default: false,
        aliases: ["-n"],
        desc:    "Print the experiments that would run, and call nothing"

      example [
        "                                     # everything config.yml lists",
        "-m anthropic/claude-haiku-5.5,openai/gpt-4o-mini -t 0",
        "-e low -c 06,07,08,09,10 --concurrency 2",
        "-n                                   # show the matrix, spend nothing"
      ]

      def call(models:, concurrency:, dry_run:, dataset:, **options)
        config = Config.new(options[:config])
        contenders = contenders(config, models, options)

        datasets = datasets(dataset)
        return matrix(datasets, contenders) if dry_run

        Runtime.setup!(braintrust: !options[:local], keys: keys_for(contenders))
        ModelCatalog.verify!(contenders)
        runs = datasets.flat_map { |name| contenders.map { experiment(it, config, options, dataset: name) } }
        report(execute(runs, concurrency: Integer(concurrency)), output: options[:output], open: options[:open])
      end

      private

      def matrix(datasets, contenders)
        rows = datasets.product(contenders).map { |name, c| [name, c.model, c.effort, c.temperature, c.max_tokens] }
        table(rows, header: %w[dataset model effort temp max_tokens])
      end
    end
  end
end
