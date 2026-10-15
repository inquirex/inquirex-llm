# frozen_string_literal: true

module Inquirex
  module LLM
    module Evals
      # Runs one case against one model, as production would: the case's text
      # is the answer to the step the dataset's extract reads from, the
      # prompts are {OpenAIAdapter}'s, and the reply is parsed and
      # canonicalized by the gem. It never scores; {Scorer} does that.
      #
      # A reply that is not a JSON object is the model's failure and comes
      # back as a {Agent::Evals::Reply} with `error` set. A transport failure
      # raises, and the run counts it as an error rather than a wrong answer.
      class Adapter < Agent::Evals::Adapter
        # Recorded with every experiment: which prompt the models saw.
        PROMPT = "Inquirex::LLM::OpenAIAdapter"

        # @param root [String, nil] the suite root holding datasets/; the configured suite's when nil
        def initialize(root: nil)
          super()
          @root = root
          @datasets = {}
          @lock = Mutex.new
        end

        # @return [String]
        def root = @root || Agent::Evals.configuration.root

        # Loads the dataset's flow and schema once, before its cases run in threads.
        #
        # @param dataset [String]
        # @return [void]
        def prepare(dataset)
          set = dataset(dataset)
          set.node
          set.schema
        end

        # @param kase [Agent::Evals::Case]
        # @param model [Agent::Evals::Model]
        # @return [Agent::Evals::Reply]
        def call(kase, model:)
          set = dataset(kase.dataset)
          adapter = ModelAdapter.new(model)
          extraction = adapter.call(set.node, { set.source_step => kase.input })
          Agent::Evals::Reply.new(
            output:   extraction.output.transform_keys(&:to_s),
            raw:      extraction.raw.transform_keys(&:to_s),
            usage:    adapter.completion.usage,
            metadata: { prompt: adapter.prompt }
          )
        rescue Errors::AdapterError => e
          raise if adapter.completion.nil? # nothing was asked: not the model's doing

          Agent::Evals::Reply.new(error: e.message.lines.first.strip,
            raw: adapter.completion.text,
            usage: adapter.completion.usage,
            metadata: { prompt: adapter.prompt })
        end

        # @param kase [Agent::Evals::Case]
        # @return [Hash] the schema the scorer grades against
        def context(kase) = { schema: dataset(kase.dataset).schema }

        # @param dataset [String]
        # @return [Array<String>] drift between schema.rb and the DSL, or a flow that will not load
        def verify(dataset) = dataset(dataset).problems

        # @return [Hash]
        def metadata = { prompt: PROMPT, 'inquirex-llm': Inquirex::LLM::VERSION }

        private

        # @return [Dataset] one per name, shared by the threads of an experiment
        def dataset(name)
          @lock.synchronize { @datasets[name] ||= Dataset.new(name, root: root) }
        end
      end
    end
  end
end
