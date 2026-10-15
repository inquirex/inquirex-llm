# frozen_string_literal: true

require "inquirex/llm/openai_adapter"

module Inquirex
  module LLM
    # OpenRouter adapter: any model OpenRouter hosts, through its
    # OpenAI-compatible Chat Completions endpoint. Prompts, parsing and
    # normalization are {OpenAIAdapter}'s; only the endpoint, the key, the
    # model ids and the optional reasoning effort differ.
    #
    # Usage:
    #   adapter = Inquirex::LLM::OpenRouterAdapter.new  # key and model from Inquirex::LLM.configuration
    #   adapter = Inquirex::LLM::OpenRouterAdapter.new(model: "google/gemini-2.5-flash", effort: "low")
    class OpenRouterAdapter < OpenAIAdapter
      API_URL = "https://openrouter.ai/api/v1/chat/completions"
      DEFAULT_MODEL = Models::OPENROUTER_DEFAULT

      # DSL symbols to OpenRouter ids. Written in {Models}.
      MODEL_MAP = Models::OPENROUTER_ALIASES

      # The reasoning efforts OpenRouter accepts.
      EFFORTS = %w[none minimal low medium high xhigh max].freeze

      attr_reader :effort

      # @param api_key [String, nil] defaults to the configuration's openrouter_api_key (OPENROUTER_API_KEY)
      # @param model [String, nil] defaults to the configuration's openrouter_model
      #   (INQUIREX_LLM_OPENROUTER_MODEL)
      # @param effort [String, nil] reasoning effort; nil sends none, and the model decides
      # @raise [ArgumentError] when no key is passed or configured, or the effort is unknown
      def initialize(api_key: nil, model: nil, effort: nil)
        key = api_key || LLM.configuration.openrouter_api_key
        raise ArgumentError, "OPENROUTER_API_KEY is required (pass api_key: or set the env var)" unless key
        if effort && !EFFORTS.include?(effort.to_s)
          raise ArgumentError, "effort must be one of #{EFFORTS.join(", ")} (got #{effort.inspect})"
        end

        super(api_key: key, model: model || LLM.configuration.openrouter_model)
        @effort = effort&.to_s
      end

      private

      def provider_name = "OpenRouter"

      def request_body(**)
        body = super
        effort ? body.merge(reasoning: { effort: effort }) : body
      end
    end
  end
end
