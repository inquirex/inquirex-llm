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
    #     model:   "claude-sonnet-5-5"
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
      # The current Claude model ids, and the only place they are written.
      # The default and every short alias below are looked up here, so a
      # model generation is retired in one edit instead of three that drift
      # apart (0.10.0 still defaulted to a 4.x id after 5.x shipped).
      MODELS = %w[
        claude-fable-5-1
        claude-opus-5-5
        claude-sonnet-5-5
        claude-haiku-5-5
      ].freeze

      # Maps Inquirex short model symbols to concrete Anthropic model ids,
      # one per family: :claude_opus => "claude-opus-5-5", and so on.
      MODEL_MAP = MODELS.to_h { |id| [:"claude_#{id.split("-")[1]}", id] }.freeze

      DEFAULT_MODEL = MODEL_MAP.fetch(:claude_sonnet)
      DEFAULT_MAX_TOKENS = 2048

      # Summaries want a little more room than an extraction (prose, not a
      # handful of fields) and a little more warmth than one (0.2 produces
      # summaries that read like a database dump).
      DEFAULT_SUMMARY_MAX_TOKENS = 4096
      DEFAULT_SUMMARY_TEMPERATURE = 0.4

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
          temperature: node.respond_to?(:temperature) ? (node.temperature || DEFAULT_SUMMARY_TEMPERATURE) : DEFAULT_SUMMARY_TEMPERATURE,
          max_tokens:  node.respond_to?(:max_tokens) ? (node.max_tokens || DEFAULT_SUMMARY_MAX_TOKENS) : DEFAULT_SUMMARY_MAX_TOKENS
        )
        parse_text_response(response)
      end

      private

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

        warn "[inquirex-llm] Calling #{model}..." if ENV["INQUIREX_DEBUG"]

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
