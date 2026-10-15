# frozen_string_literal: true

require "ruby_llm"

module ExtractEval
  # The gem's {Inquirex::LLM::OpenRouterAdapter} with the transport swapped.
  #
  # Everything the model sees and everything done to its answer is the gem's:
  # the system prompt, the schema contract, the user prompt built from the
  # step's `from` answers, the reasoning effort, fence stripping, JSON parsing
  # and canonicalization of enum values. Only the HTTP call goes through
  # RubyLLM instead of Net::HTTP, because Braintrust traces RubyLLM calls
  # (tokens, latency, cost) and not raw HTTP.
  class OpenRouterAdapter < Inquirex::LLM::OpenRouterAdapter
    attr_reader :model, :temperature, :max_tokens

    # @param model [String] an OpenRouter model id, e.g. "anthropic/claude-sonnet-5.5"
    # @param effort [String, nil] reasoning effort; nil leaves the model's default
    # @param temperature [Float, nil] nil leaves the model's default
    # @param max_tokens [Integer]
    # @param api_key [String, nil] the OpenRouter key; the gem's configuration when nil
    def initialize(model:, effort: nil, temperature: nil, max_tokens: 4096, api_key: nil)
      super(api_key: api_key, model: model, effort: effort)
      @model = model
      @temperature = temperature
      @max_tokens = max_tokens
    end

    # Extracts the node's schema from one free-form answer. Unlike #call, a
    # response that omits schema fields is returned rather than raised, so a
    # partial answer earns partial credit.
    #
    # @param node [Inquirex::LLM::Node]
    # @param text [String] what the visitor wrote
    # @return [Hash{Symbol => Object}] canonicalized output, plus `_usage`
    #   ({ input_tokens:, output_tokens:, cost_usd: }), which the scorers ignore
    # @raise [Inquirex::LLM::Errors::AdapterError] when the reply is not a JSON object
    def extract(node, text)
      answers = { node.from_steps.first => text }
      response = call_api(
        model:       @model,
        system:      build_system_prompt(node),
        user:        build_user_prompt(node, source_answers(node, answers), answers),
        temperature: @temperature,
        max_tokens:  @max_tokens
      )
      usage = response.fetch("usage")
      normalize_output(node, parse_response(response)).merge(_usage: usage)
    end

    private

    # Same contract as the parent's: an OpenAI-shaped response Hash, so
    # #parse_response is reused unchanged. Token counts and the cost
    # OpenRouter billed ride along under "usage", in the shape every adapter
    # here reports them.
    def call_api(model:, system:, user:, temperature:, max_tokens:)
      chat = RubyLLM.chat(model: model, provider: :openrouter, assume_model_exists: true)
      chat.with_instructions(system)
      chat.with_temperature(temperature) unless temperature.nil?
      chat.with_max_output_tokens(max_tokens)
      chat.with_thinking(effort: effort.to_sym) if effort
      chat.with_provider_options(response_format: { type: "json_object" })

      message = chat.ask(user)
      { "choices" => [{ "message" => { "content" => message.content.to_s } }],
        "usage"   => { input_tokens: message.tokens.input.to_i, output_tokens: message.tokens.output.to_i,
                       cost_usd: message.tokens.reported_cost.to_f } }
    end
  end
end
