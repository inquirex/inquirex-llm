# frozen_string_literal: true

module Inquirex
  module LLM
    # Enriched node for LLM-powered steps. Extends Inquirex::Node with attributes
    # needed by the server-side LLM adapter: prompt template, output schema, source
    # step references, and model configuration.
    #
    # LLM verbs:
    #   :clarify   — extract structured data from a free-text answer
    #   :describe  — generate natural-language text from structured data
    #   :summarize — produce a summary of all or selected answers
    #   :detour    — dynamically generate follow-up questions based on an answer
    #
    # All LLM nodes are collecting (they produce answers) and require server
    # round-trips. The frontend shows a "thinking" state while the server processes.
    #
    # @attr_reader prompt [String] LLM prompt template
    # @attr_reader schema [Schema, nil] expected output structure (required for clarify/detour)
    # @attr_reader from_steps [Array<Symbol>] source step ids whose answers feed the LLM
    # @attr_reader from_all [Boolean] whether to pass all collected answers to the LLM
    # @attr_reader model [Symbol, nil] optional model hint (e.g. :claude_sonnet)
    # @attr_reader temperature [Float, nil] optional sampling temperature
    # @attr_reader max_tokens [Integer, nil] optional max output tokens
    # @attr_reader fallback [Proc, nil] server-side fallback (stripped from JSON)
    class Node < Inquirex::Node
      LLM_VERBS = %i[clarify describe summarize detour].freeze

      attr_reader :prompt,
        :schema,
        :from_steps,
        :from_all,
        :model,
        :temperature,
        :max_tokens,
        :fallback

      def initialize(prompt:, schema: nil, from_steps: [], from_all: false,
        model: nil, temperature: nil, max_tokens: nil, fallback: nil, **)
        @prompt = prompt
        @schema = schema
        @from_steps = Array(from_steps).map(&:to_sym).freeze
        @from_all = !!from_all
        @model = model&.to_sym
        @temperature = temperature&.to_f
        @max_tokens = max_tokens&.to_i
        @fallback = fallback
        super(**)
      end
      # rubocop:enable Metrics/ParameterLists

      # LLM verbs always collect output (the LLM provides the "answer").
      def collecting? = true

      # LLM verbs are never display-only.
      def display? = false

      # Whether this is an LLM-powered step requiring server processing.
      def llm_verb? = true

      # Serializes to a plain Hash. LLM metadata is nested under "llm".
      # Fallback procs are stripped (server-side only).
      # All transitions are marked requires_server: true.
      #
      # @return [Hash]
      def to_h
        hash = { "verb" => @verb.to_s }
        hash["question"] = @question if @question
        hash["text"] = @text if @text
        hash["transitions"] = @transitions.map(&:to_h) unless @transitions.empty?
        hash["skip_if"] = @skip_if.to_h if @skip_if
        hash["requires_server"] = true

        llm_hash = { "prompt" => @prompt }
        llm_hash["schema"] = @schema.to_h if @schema
        llm_hash["from_steps"] = @from_steps.map(&:to_s) unless @from_steps.empty?
        llm_hash["from_all"] = true if @from_all
        llm_hash["model"] = @model.to_s if @model
        llm_hash["temperature"] = @temperature if @temperature
        llm_hash["max_tokens"] = @max_tokens if @max_tokens
        hash["llm"] = llm_hash

        hash
      end

      # Deserializes from a plain Hash (string or symbol keys).
      #
      # @param id [Symbol, String]
      # @param hash [Hash]
      # @return [LLM::Node]
      def self.from_h(id, hash)
        verb             = hash["verb"]        || hash[:verb]
        question         = hash["question"]    || hash[:question]
        text             = hash["text"]        || hash[:text]
        transitions_data = hash["transitions"] || hash[:transitions] || []
        skip_if_data     = hash["skip_if"]     || hash[:skip_if]
        llm_data         = hash["llm"]         || hash[:llm] || {}

        transitions = transitions_data.map { |t| Inquirex::Transition.from_h(t) }
        skip_if = skip_if_data ? Inquirex::Rules::Base.from_h(skip_if_data) : nil

        prompt     = llm_data["prompt"]     || llm_data[:prompt]
        schema_raw = llm_data["schema"]     || llm_data[:schema]
        from_raw   = llm_data["from_steps"] || llm_data[:from_steps] || []
        from_all   = llm_data["from_all"]   || llm_data[:from_all] || false
        model      = llm_data["model"]      || llm_data[:model]
        temp       = llm_data["temperature"] || llm_data[:temperature]
        max_tok    = llm_data["max_tokens"]  || llm_data[:max_tokens]

        schema = schema_raw ? Schema.from_h(schema_raw) : nil
        from_steps = from_raw.map(&:to_sym)

        new(
          id:,
          verb:,
          question:,
          text:,
          transitions:,
          skip_if:,
          prompt:,
          schema:,
          from_steps:,
          from_all:,
          model:,
          temperature: temp,
          max_tokens:  max_tok
        )
      end

      # Whether this verb is a recognized LLM verb.
      def self.llm_verb?(verb)
        LLM_VERBS.include?(verb.to_sym)
      end
    end
  end
end
