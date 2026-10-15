# frozen_string_literal: true

module Inquirex
  module LLM
    module Evals
      # The gem's {OpenAIAdapter} with its transport swapped for an
      # agent-evals {Agent::Evals::Model}. Everything the model sees and
      # everything done to its answer is production's: the system prompt,
      # the schema contract, the user prompt built from the step's `from`
      # answers, fence stripping, JSON parsing and the canonicalization of
      # enum values. Only {#call_api} differs: it asks the eval model, which
      # carries its own provider, key, effort, temperature and token cap, so
      # the arguments production would have sent are ignored here.
      #
      # One of these is built per call: it remembers the prompt it sent and
      # the completion it got, so the adapter can report both.
      class ModelAdapter < OpenAIAdapter
        # OpenAIAdapter insists on a key; the eval model holds the real one.
        NO_KEY = "(unused: the eval model carries its own key)"

        # @return [Agent::Evals::Completion, nil] what the model answered, once asked
        attr_reader :completion

        # @return [Hash{Symbol => String}, nil] the system and user prompts, once sent
        attr_reader :prompt

        # @param model [Agent::Evals::Model]
        def initialize(model)
          super(api_key: NO_KEY, model: model.id)
          @model = model
        end

        # A partial answer is not an error here: the scorer counts each
        # missing key as a field the model missed, so it earns partial credit
        # instead of failing the case.
        #
        # @return [nil]
        def validate_output!(_node, _output) = nil

        private

        # Same contract as the parent's: an OpenAI-shaped response Hash, so
        # #parse_response and #usage_from are reused unchanged.
        def call_api(system:, user:, **)
          @prompt = { system: system, user: user }
          @completion = @model.complete(system: system, user: user, json: true)
          usage = @completion.usage
          { "choices" => [{ "message" => { "content" => @completion.text } }],
            "usage"   => { "prompt_tokens"     => usage.input_tokens,
                           "completion_tokens" => usage.output_tokens,
                           "cost"              => usage.cost_usd } }
        end

        def provider_name = "the eval model"
      end
    end
  end
end
