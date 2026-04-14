# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "inquirex/llm/adapter"

module Inquirex
  module LLM
    # Real Anthropic Claude adapter for inquirex-llm.
    #
    # Usage:
    #   adapter = Inquirex::LLM::AnthropicAdapter.new(
    #     api_key: ENV["ANTHROPIC_API_KEY"],
    #     model:   "claude-sonnet-4-20250514"
    #   )
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
      DEFAULT_MODEL = "claude-sonnet-4-20250514"
      DEFAULT_MAX_TOKENS = 2048

      # Maps Inquirex short model symbols to concrete Anthropic model ids.
      MODEL_MAP = {
        claude_sonnet: "claude-sonnet-4-20250514",
        claude_haiku:  "claude-haiku-4-5-20251001",
        claude_opus:   "claude-opus-4-20250514"
      }.freeze

      # @param api_key [String, nil] defaults to ENV["ANTHROPIC_API_KEY"]
      # @param model   [String, nil] default model id when a node does not specify one
      def initialize(api_key: nil, model: nil)
        super()
        @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY") {
          raise ArgumentError, "ANTHROPIC_API_KEY is required (pass api_key: or set the env var)"
        }
        @default_model = model || DEFAULT_MODEL
      end

      # @param node [Inquirex::LLM::Node] the current LLM step
      # @param answers [Hash] all collected answers so far
      # @return [Hash] structured data matching the node's schema
      # @raise [Errors::AdapterError] on API / parse failures
      # @raise [Errors::SchemaViolationError] when the LLM output misses schema fields
      def call(node, answers = {})
        source      = source_answers(node, answers)
        model       = resolve_model(node)
        temperature = node.respond_to?(:temperature) ? (node.temperature || 0.2) : 0.2
        max_tokens  = node.respond_to?(:max_tokens)  ? (node.max_tokens  || DEFAULT_MAX_TOKENS) : DEFAULT_MAX_TOKENS

        response = call_api(
          model:       model,
          system:      build_system_prompt(node),
          user:        build_user_prompt(node, source, answers),
          temperature: temperature,
          max_tokens:  max_tokens
        )

        result = parse_response(response)
        validate_output!(node, result)
        result
      end

      private

      def resolve_model(node)
        return @default_model unless node.respond_to?(:model) && node.model

        MODEL_MAP[node.model.to_sym] || node.model.to_s
      end

      def build_system_prompt(node)
        "You are a data extraction assistant for a questionnaire engine. " \
        "Your job is to analyze user input and extract structured data." +
          schema_instruction(node)
      end

      def schema_instruction(node)
        if node.respond_to?(:schema) && node.schema
          schema_json = node.schema.fields.transform_values(&:to_s)
          "\n\nYou MUST respond with ONLY a valid JSON object matching this schema:\n" \
            "#{JSON.pretty_generate(schema_json)}\n\n" \
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
          node.schema.fields.each { |field, type| parts << "  #{field} (#{type})" }
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
          model:       model,
          max_tokens:  max_tokens,
          temperature: temperature,
          system:      system,
          messages:    [{ role: "user", content: user }]
        )

        warn "[inquirex-llm] Calling #{model}..." if ENV["INQUIREX_DEBUG"]

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Errors::AdapterError, "Anthropic API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def parse_response(api_response)
        content    = api_response["content"]
        text_block = content.is_a?(Array) ? content.find { |c| c["type"] == "text" } : nil
        raise Errors::AdapterError, "No text content in Anthropic response" unless text_block

        raw_text = text_block["text"].to_s.strip
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
