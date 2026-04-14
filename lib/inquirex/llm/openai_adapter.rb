# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "inquirex/llm/adapter"

module Inquirex
  module LLM
    # OpenAI Chat Completions adapter for inquirex-llm.
    #
    # Uses the Chat Completions API with response_format: { type: "json_object" }
    # so the model is constrained to return a valid JSON object — more reliable
    # than prompt-only "please return JSON" approaches for structured extraction.
    #
    # Usage:
    #   adapter = Inquirex::LLM::OpenAIAdapter.new(
    #     api_key: ENV["OPENAI_API_KEY"],
    #     model:   "gpt-4o-mini"
    #   )
    #   result = adapter.call(engine.current_step, engine.answers)
    class OpenAIAdapter < Adapter
      API_URL = "https://api.openai.com/v1/chat/completions"
      DEFAULT_MODEL = "gpt-4o-mini"
      DEFAULT_MAX_TOKENS = 2048

      # Maps Inquirex DSL model symbols to concrete OpenAI model ids. Accepts
      # Claude symbols too — we substitute sensible OpenAI equivalents so flow
      # definitions written against Anthropic still run against this adapter.
      MODEL_MAP = {
        gpt_4o:        "gpt-4o",
        gpt_4o_mini:   "gpt-4o-mini",
        gpt_4_1:       "gpt-4.1",
        gpt_4_1_mini:  "gpt-4.1-mini",
        claude_sonnet: "gpt-4o",
        claude_haiku:  "gpt-4o-mini",
        claude_opus:   "gpt-4o"
      }.freeze

      # @param api_key [String, nil] defaults to ENV["OPENAI_API_KEY"]
      # @param model   [String, nil] default model id when a node does not specify one
      def initialize(api_key: nil, model: nil)
        super()
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY") {
          raise ArgumentError, "OPENAI_API_KEY is required (pass api_key: or set the env var)"
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
        "Your job is to analyze user input and extract structured data. " \
        "You MUST respond with a single valid JSON object and nothing else." +
          schema_instruction(node)
      end

      def schema_instruction(node)
        if node.respond_to?(:schema) && node.schema
          schema_json = node.schema.fields.transform_values(&:to_s)
          "\n\nThe JSON object MUST match this schema exactly (same keys, appropriate types):\n" \
            "#{JSON.pretty_generate(schema_json)}\n\n" \
            "Every key in the schema must be present in your output. Use null, \"\", 0, or [] " \
            "for values the source text does not provide."
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
          node.schema.fields.each { |field, type| parts << "  #{field} (#{type})" }
        end

        if node.respond_to?(:from_all) && node.from_all && all_answers.any?
          parts << "\nAll collected answers:"
          all_answers.each { |key, value| parts << "  #{key}: #{value.inspect}" }
        end

        parts << "\nReturn ONLY the JSON object."
        parts.join("\n")
      end

      def call_api(model:, system:, user:, temperature:, max_tokens:)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request.body = JSON.generate(
          model:           model,
          max_tokens:      max_tokens,
          temperature:     temperature,
          response_format: { type: "json_object" },
          messages:        [
            { role: "system", content: system },
            { role: "user",   content: user }
          ]
        )

        warn "[inquirex-llm] Calling OpenAI #{model}..." if ENV["INQUIREX_DEBUG"]

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Errors::AdapterError, "OpenAI API error #{response.code}: #{response.body}"
        end

        JSON.parse(response.body)
      end

      def parse_response(api_response)
        choices = api_response["choices"]
        message = choices.is_a?(Array) ? choices.first&.dig("message") : nil
        raw_text = message&.dig("content")
        raise Errors::AdapterError, "No message content in OpenAI response" unless raw_text

        raw_text = raw_text.to_s.strip
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
