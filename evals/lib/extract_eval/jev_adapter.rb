# frozen_string_literal: true

module ExtractEval
  # The gem's {Inquirex::LLM::JevAdapter}, shaped like every other contender:
  # one free-form text in, the schema's fields out. Adds `_confidence` and
  # `_usage`, which the scorers ignore and Braintrust records with each case.
  class JevAdapter
    # Model ids this adapter serves: "typesafe-api/<TypeSafe model>".
    PREFIX = "typesafe-api/"

    # TypeSafe bills input tokens only: $0.042 per million for jev-latest and
    # jev-preview (docs.typesafe.ai/models, read 2026-10-14). Output is free.
    USD_PER_INPUT_TOKEN = 0.042 / 1_000_000

    attr_reader :model

    # @param model [String] e.g. "typesafe-api/jev-latest"
    # @param api_key [String, nil] the TypeSafe key; the gem's configuration when nil
    def initialize(model:, api_key: nil)
      @model = model
      @jev = Inquirex::LLM::JevAdapter.new(api_key: api_key, model: model.delete_prefix(PREFIX))
    end

    # @param model [String]
    # @return [Boolean] whether this adapter serves the model id
    def self.serves?(model) = model.start_with?(PREFIX)

    # Jev takes no reasoning effort, temperature or output cap.
    def effort = nil
    def temperature = nil
    def max_tokens = nil

    # @param node [Inquirex::LLM::Node]
    # @param text [String] what the visitor wrote
    # @return [Hash{Symbol => Object}]
    def extract(node, text)
      extraction = @jev.extract(node, { node.from_steps.first => text })
      usage = extraction.usage.merge(cost_usd: extraction.usage[:input_tokens] * USD_PER_INPUT_TOKEN)
      extraction.values.merge(_confidence: extraction.confidence, _usage: usage)
    end
  end
end
