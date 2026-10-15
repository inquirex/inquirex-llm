# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "inquirex/llm/adapter"
require "inquirex/llm/configuration"

module Inquirex
  module LLM
    # OpenAI Chat Completions adapter for inquirex-llm.
    #
    # Uses the Chat Completions API with response_format: { type: "json_object" }
    # so the model is constrained to return a valid JSON object — more reliable
    # than prompt-only "please return JSON" approaches for structured extraction.
    #
    # Usage:
    #   adapter = Inquirex::LLM::OpenAIAdapter.new  # key and model from Inquirex::LLM.configuration
    #   adapter = Inquirex::LLM::OpenAIAdapter.new(api_key: "sk-...", model: "gpt-4.1")
    #   result = adapter.call(engine.current_step, engine.answers)
    class OpenAIAdapter < Adapter
      API_URL = "https://api.openai.com/v1/chat/completions"
      DEFAULT_MODEL = Models::OPENAI_DEFAULT
      DEFAULT_MAX_TOKENS = Configuration::DEFAULT_MAX_TOKENS
      DEFAULT_SUMMARY_MAX_TOKENS = Configuration::DEFAULT_SUMMARY_MAX_TOKENS
      DEFAULT_SUMMARY_TEMPERATURE = Configuration::DEFAULT_SUMMARY_TEMPERATURE

      # Maps Inquirex DSL model symbols to concrete OpenAI model ids,
      # including OpenAI equivalents for the Claude symbols. Written in {Models}.
      MODEL_MAP = Models::OPENAI_ALIASES

      # @param api_key [String, nil] defaults to the configuration's openai_api_key (OPENAI_API_KEY)
      # @param model   [String, nil] default model id when a node does not specify one;
      #   defaults to the configuration's openai_model (INQUIREX_LLM_OPENAI_MODEL)
      # @raise [ArgumentError] when no key is passed or configured
      def initialize(api_key: nil, model: nil)
        super()
        @api_key = api_key || LLM.configuration.openai_api_key
        raise ArgumentError, "OPENAI_API_KEY is required (pass api_key: or set the env var)" unless @api_key

        @default_model = model || LLM.configuration.openai_model
      end

      # @param node [Inquirex::LLM::Node] the current LLM step
      # @param answers [Hash] all collected answers so far
      # @return [Hash] structured data matching the node's schema
      # @raise [Errors::AdapterError] on API / parse failures
      # @raise [Errors::SchemaViolationError] when the LLM output misses schema fields
      def call(node, answers = {})
        source      = source_answers(node, answers)
        model       = resolve_model(node)
        temperature = node.respond_to?(:temperature) ? (node.temperature || config.temperature) : config.temperature
        max_tokens  = node.respond_to?(:max_tokens)  ? (node.max_tokens  || config.max_tokens) : config.max_tokens

        response = call_api(
          model:       model,
          system:      build_system_prompt(node),
          user:        build_user_prompt(node, source, answers),
          temperature: temperature,
          max_tokens:  max_tokens
        )

        result = normalize_output(node, parse_response(response))
        validate_output!(node, result)
        result
      end

      # Generates the closing summary for a `summarize` step.
      #
      # The system prompt is read from {Prompts::SUMMARIZE} rather than from
      # the node, so a hand-forged or tampered node cannot substitute its own
      # instructions.
      #
      # @param node [Inquirex::LLM::Node] the summarize step
      # @param transcript [String] the session transcript
      # @param answers [Hash] unused; accepted for interface symmetry
      # @return [String] markdown summary
      # @raise [Errors::AdapterError] on API / parse failures
      def summarize(node, transcript, _answers = {})
        response = call_api(
          model:       resolve_model(node),
          system:      Prompts::SUMMARIZE,
          user:        summary_input(transcript),
          temperature: node.respond_to?(:temperature) ? (node.temperature || config.summary_temperature) : config.summary_temperature,
          max_tokens:  node.respond_to?(:max_tokens) ? (node.max_tokens || config.summary_max_tokens) : config.summary_max_tokens
        )
        parse_text_response(response)
      end

      private

      # Read on every call rather than kept from #initialize, so limits set
      # through Inquirex::LLM.configure after the adapter was built still apply.
      #
      # @return [Configuration]
      def config = LLM.configuration

      def resolve_model(node)
        return @default_model unless node.respond_to?(:model) && node.model

        self.class::MODEL_MAP[node.model.to_sym] || node.model.to_s
      end

      def build_system_prompt(node)
        "You are a data extraction assistant for a questionnaire engine. " \
        "Your job is to analyze user input and extract structured data. " \
        "You MUST respond with a single valid JSON object and nothing else." +
          schema_instruction(node)
      end

      def schema_instruction(node)
        if node.respond_to?(:schema) && node.schema
          "\n\nThe JSON object MUST match this schema exactly (same keys, appropriate types):\n" \
            "#{schema_contract_json(node.schema)}\n" \
            "#{values_instruction(node.schema)}\n\n" \
            "#{missing_values_instruction}"
        else
          ""
        end
      end

      def build_user_prompt(node, source, all_answers)
        parts = []
        parts << "Task: #{node.prompt}" if node.respond_to?(:prompt) && node.prompt

        if source.is_a?(Hash) && source.any?
          parts << "\nSource data from previous answers:"
          source.each { |key, value| parts << "  #{key}: #{value.inspect}" }
        end

        if node.respond_to?(:schema) && node.schema
          parts << "\nExtract these fields as a JSON object:"
          parts.concat(field_descriptions(node.schema))
        end

        if node.respond_to?(:from_all) && node.from_all && all_answers.any?
          parts << "\nAll collected answers:"
          all_answers.each { |key, value| parts << "  #{key}: #{value.inspect}" }
        end

        parts << "\nReturn ONLY the JSON object."
        parts.join("\n")
      end

      # @return [String] the Chat Completions endpoint; subclasses point elsewhere
      def api_url = self.class::API_URL

      # @return [String] the provider's name, for errors and debug lines
      def provider_name = "OpenAI"

      # The request body. Subclasses add provider-specific fields here.
      #
      # @return [Hash]
      def request_body(model:, system:, user:, temperature:, max_tokens:)
        {
          model:           model,
          max_tokens:      max_tokens,
          temperature:     temperature,
          response_format: { type: "json_object" },
          messages:        [
            { role: "system", content: system },
            { role: "user",   content: user }
          ]
        }
      end

      def call_api(model:, system:, user:, temperature:, max_tokens:)
        uri = URI(api_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request.body = JSON.generate(
          request_body(model: model, system: system, user: user, temperature: temperature, max_tokens: max_tokens)
        )

        warn "[inquirex-llm] Calling #{provider_name} #{model}..." if config.debug?

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Errors::AdapterError, "#{provider_name} API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      # The response's message content, with the model's habitual wrapping
      # fence removed. Unlike {#parse_response} it stays a String: a summary
      # is markdown for a human, not JSON for the engine.
      #
      # @param api_response [Hash]
      # @return [String]
      # @raise [Errors::AdapterError] when the response carries no content, or
      #   the model returned nothing usable
      def parse_text_response(api_response)
        text = response_text(api_response)
        text = text.gsub(/\A```(?:markdown|md)?\s*\n?/, "").gsub(/\n?```\s*\z/, "").strip
        raise Errors::AdapterError, "#{provider_name} returned an empty summary" if text.empty?

        text
      end

      # @return [String] the first choice's message content
      # @raise [Errors::AdapterError] when there is none
      def response_text(api_response)
        choices = api_response["choices"]
        message = choices.is_a?(Array) ? choices.first&.dig("message") : nil
        raw_text = message&.dig("content")
        raise Errors::AdapterError, "No message content in #{provider_name} response" unless raw_text

        raw_text.to_s.strip
      end

      def parse_response(api_response)
        raw_text = response_text(api_response)
        raw_text = raw_text.gsub(/\A```(?:json)?\s*\n?/, "").gsub(/\n?```\s*\z/, "").strip

        parsed = JSON.parse(raw_text, symbolize_names: true)
        raise Errors::AdapterError, "Expected JSON object from LLM, got #{parsed.class}" unless parsed.is_a?(Hash)

        parsed
      rescue JSON::ParserError => e
        raise Errors::AdapterError,
          "Failed to parse LLM response as JSON: #{e.message}\nRaw: #{raw_text.inspect}"
      end
    end
  end
end
