# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "inquirex/llm/adapter"
require "inquirex/llm/configuration"

module Inquirex
  module LLM
    # Real Anthropic Claude adapter for inquirex-llm.
    #
    # Usage:
    #   adapter = Inquirex::LLM::AnthropicAdapter.new  # key and model from Inquirex::LLM.configuration
    #   adapter = Inquirex::LLM::AnthropicAdapter.new(api_key: "sk-...", model: "claude-opus-5-5")
    #   result = adapter.call(engine.current_step, engine.answers)
    #
    # The adapter:
    #   1. Gathers source answers from the step's `from` / `from_all` declaration
    #   2. Builds a prompt that includes the schema as a JSON contract
    #   3. Calls the Anthropic Messages API
    #   4. Parses the JSON response
    #   5. Validates output against the declared schema
    #   6. Returns the structured hash
    class AnthropicAdapter < Adapter
      API_URL = "https://api.anthropic.com/v1/messages"
      API_VERSION = "2023-06-01"
      # The current Claude model ids. Kept as aliases of {Models} so callers
      # that read them here keep working; {Models} is where they are written.
      MODELS = Models::ANTHROPIC
      MODEL_MAP = Models::ANTHROPIC_ALIASES
      DEFAULT_MODEL = Models::ANTHROPIC_DEFAULT

      DEFAULT_MAX_TOKENS = Configuration::DEFAULT_MAX_TOKENS
      DEFAULT_SUMMARY_MAX_TOKENS = Configuration::DEFAULT_SUMMARY_MAX_TOKENS
      DEFAULT_SUMMARY_TEMPERATURE = Configuration::DEFAULT_SUMMARY_TEMPERATURE

      # @param api_key [String, nil] defaults to the configuration's anthropic_api_key (ANTHROPIC_API_KEY)
      # @param model   [String, nil] default model id when a node does not specify one;
      #   defaults to the configuration's anthropic_model (INQUIREX_LLM_ANTHROPIC_MODEL)
      # @raise [ArgumentError] when no key is passed or configured
      def initialize(api_key: nil, model: nil)
        super()
        @api_key = api_key || LLM.configuration.anthropic_api_key
        raise ArgumentError, "ANTHROPIC_API_KEY is required (pass api_key: or set the env var)" unless @api_key

        @default_model = model || LLM.configuration.anthropic_model
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
      # The system prompt is {Prompts::SUMMARIZE} — the node's own prompt is
      # that same constant, but reading it from the constant means a node
      # forged by hand or deserialized from a tampered definition still cannot
      # substitute its own instructions.
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

        MODEL_MAP[node.model.to_sym] || node.model.to_s
      end

      # The models in {MODELS} reject sampling parameters: a request carrying
      # `temperature` is answered with HTTP 400, whatever its value. The DSL's
      # `temperature` is therefore sent only to an explicitly named older
      # model that still accepts it.
      #
      # @param model [String] resolved model id
      # @param temperature [Float]
      # @return [Hash] `{}` or `{ temperature: }`
      def sampling(model, temperature)
        MODELS.include?(model) ? {} : { temperature: temperature }
      end

      def build_system_prompt(node)
        "You are a data extraction assistant for a questionnaire engine. " \
        "Your job is to analyze user input and extract structured data." +
          schema_instruction(node)
      end

      def schema_instruction(node)
        if node.respond_to?(:schema) && node.schema
          "\n\nYou MUST respond with ONLY a valid JSON object matching this schema:\n" \
            "#{schema_contract_json(node.schema)}\n" \
            "#{values_instruction(node.schema)}\n\n" \
            "#{missing_values_instruction}\n" \
            "Do not include any text before or after the JSON. No markdown fences. Just the raw JSON object."
        else
          "\n\nRespond with a valid JSON object containing your analysis. " \
            "No markdown fences. Just the raw JSON object."
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
          parts << "\nExtract these fields from the source data:"
          parts.concat(field_descriptions(node.schema))
        end

        if node.respond_to?(:from_all) && node.from_all && all_answers.any?
          parts << "\nAll collected answers:"
          all_answers.each { |key, value| parts << "  #{key}: #{value.inspect}" }
        end

        parts.join("\n")
      end

      def call_api(model:, system:, user:, temperature:, max_tokens:)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]      = "application/json"
        request["x-api-key"]         = @api_key
        request["anthropic-version"] = API_VERSION
        request.body = JSON.generate(
          model:      model,
          max_tokens: max_tokens,
          **sampling(model, temperature),
          system:     system,
          messages:   [{ role: "user", content: user }]
        )

        warn "[inquirex-llm] Calling #{model}..." if config.debug?

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Errors::AdapterError, "Anthropic API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      # The response's text content, with the model's habitual wrapping fence
      # removed. Unlike {#parse_response} it stays a String: a summary is
      # markdown for a human, not JSON for the engine.
      #
      # @param api_response [Hash]
      # @return [String]
      # @raise [Errors::AdapterError] when the response carries no text, or
      #   the model returned nothing usable
      def parse_text_response(api_response)
        text = response_text(api_response)
        text = text.gsub(/\A```(?:markdown|md)?\s*\n?/, "").gsub(/\n?```\s*\z/, "").strip
        raise Errors::AdapterError, "Anthropic returned an empty summary" if text.empty?

        text
      end

      # @return [String] the first text block's content
      # @raise [Errors::AdapterError] when there is none
      def response_text(api_response)
        content    = api_response["content"]
        text_block = content.is_a?(Array) ? content.find { |c| c["type"] == "text" } : nil
        raise Errors::AdapterError, "No text content in Anthropic response" unless text_block

        text_block["text"].to_s.strip
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
