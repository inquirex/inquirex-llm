# frozen_string_literal: true

module Inquirex
  module LLM
    # Abstract interface for LLM adapters. Adapters bridge the gap between
    # LLM::Node definitions and actual LLM API calls.
    #
    # Implementations must:
    #   1. Accept an LLM::Node and current answers
    #   2. Construct the appropriate prompt (using node.prompt, node.from_steps, etc.)
    #   3. Call the LLM API
    #   4. Parse and validate the response against node.schema (if present)
    #   5. Return a Hash or String result
    #
    # The adapter is invoked server-side when the engine reaches an LLM step.
    # It is never called on the frontend.
    #
    # @example Implementing a custom adapter
    #   class MyLlmAdapter < Inquirex::LLM::Adapter
    #     def call(node, answers)
    #       prompt_text = build_prompt(node, answers)
    #       response = my_llm_client.complete(prompt_text, model: node.model)
    #       parse_response(response, node.schema)
    #     end
    #   end
    class Adapter
      # Processes an LLM step and returns the result.
      #
      # @param node [LLM::Node] the LLM step to process
      # @param answers [Hash] current collected answers
      # @return [Hash, String] structured output (for extract) or text (when no schema)
      # @raise [Errors::AdapterError] if the LLM call fails
      # @raise [Errors::SchemaViolationError] if output doesn't match schema
      def call(node, answers)
        raise NotImplementedError, "#{self.class}#call must be implemented"
      end

      # Produces the closing prose summary for a `summarize` step.
      #
      # Separate from {#call} because nothing about it is the same: the prompt
      # is the gem's rather than the node's, the input is the session
      # transcript rather than selected answers, and the result is markdown
      # rather than a schema-shaped Hash. Keeping it apart also means an
      # existing custom adapter that only implements #call keeps working for
      # `extract` and fails loudly — rather than subtly — if a flow starts
      # asking it to summarise.
      #
      # @param node [LLM::Node] the summarize step
      # @param transcript [String] everything the user was shown and answered
      # @param answers [Hash] collected answers, for adapters that want them
      # @return [String] markdown summary
      # @raise [Errors::AdapterError] if the LLM call fails
      def summarize(node, transcript, answers = {})
        raise NotImplementedError, "#{self.class}#summarize must be implemented"
      end

      # The user-side prompt for a summarize call: the transcript, and nothing
      # else that could compete with it for the model's attention.
      #
      # @param transcript [String]
      # @return [String]
      # @raise [Errors::AdapterError] when there is nothing to summarise
      def summary_input(transcript)
        text = transcript.to_s.strip
        raise Errors::AdapterError, "Cannot summarize an empty transcript" if text.empty?

        "Here is the session transcript.\n\n#{text}"
      end

      # Gathers the source answer data that feeds the LLM prompt.
      #
      # @param node [LLM::Node]
      # @param answers [Hash]
      # @return [Hash] relevant subset of answers
      def source_answers(node, answers)
        if node.from_all
          answers.dup
        else
          node.from_steps.each_with_object({}) do |step_id, acc|
            acc[step_id] = answers[step_id] if answers.key?(step_id)
          end
        end
      end

      # Validates adapter output against the node's schema.
      #
      # @param node [LLM::Node]
      # @param output [Hash, String]
      # @raise [Errors::SchemaViolationError] if validation fails
      def validate_output!(node, output)
        return unless node.schema

        missing = node.schema.missing_fields(output)
        return if missing.empty?

        raise Errors::SchemaViolationError,
          "LLM output for #{node.id.inspect} missing fields: #{missing.join(", ")}"
      end

      # Canonicalizes LLM output against the schema's value constraints — the
      # regression guard for "the model answered with a label or a case
      # variant". Every value-constrained field is matched against the
      # allowed form values: an exact match passes through, a
      # case-insensitive match is rewritten to the canonical value, and a
      # value outside the list becomes nil (enum) or is dropped from the
      # array (multi_enum) — "unknown, will ask" instead of junk that
      # prefills the wrong option downstream. Unconstrained fields are
      # untouched.
      #
      # @param node [LLM::Node]
      # @param output [Hash, Object] parsed LLM response
      # @return [Hash, Object] output with constrained fields canonicalized
      def normalize_output(node, output)
        schema = node.respond_to?(:schema) ? node.schema : nil
        return output unless schema && output.is_a?(Hash)

        output.to_h do |key, raw|
          values = schema.values_for(key)
          next [key, raw] unless values

          if schema.fields[key.to_sym] == :multi_enum
            [key, Array(raw).filter_map { |entry| canonical_value(values, entry) }]
          else
            [key, canonical_value(values, raw)]
          end
        end
      end

      protected

      # The canonical form value for a raw LLM answer, or nil when the answer
      # is outside the allowed list (after trimming and case-folding).
      #
      # @param values [Array<String>] allowed form values
      # @param raw [Object] one LLM-provided value
      # @return [String, nil]
      def canonical_value(values, raw)
        return nil if raw.nil?

        candidate = raw.to_s.strip
        values.find { |value| value == candidate } ||
          values.find { |value| value.casecmp?(candidate) }
      end

      # The schema as a JSON contract for the system prompt: enum-constrained
      # fields render as { "type": ..., "values": [...] } so the model knows
      # the exhaustive list of allowed answers.
      #
      # @param schema [Schema]
      # @return [String] pretty-printed JSON
      def schema_contract_json(schema)
        JSON.pretty_generate(schema.to_h)
      end

      # Prompt instruction spelling out how value-constrained fields must be
      # answered. Empty string when the schema has no constrained fields.
      #
      # @param schema [Schema]
      # @return [String]
      def values_instruction(schema)
        constrained = schema.field_names.select { |name| schema.values_for(name) }
        return "" if constrained.empty?

        "\nFor fields that declare \"values\", you MUST answer using ONLY values from that list — " \
          "return a single value for \"enum\" fields and an array of selected values for " \
          "\"multi_enum\" fields. Never invent a value outside the list."
      end

      # One human-readable line per schema field, used in user prompts:
      #   income_types (multi_enum: W2 | business | crypto)
      #   dependents (integer)
      #
      # @param schema [Schema]
      # @return [Array<String>]
      def field_descriptions(schema)
        schema.fields.map do |field, type|
          values = schema.values_for(field)
          values ? "  #{field} (#{type}: #{values.join(" | ")})" : "  #{field} (#{type})"
        end
      end
    end
  end
end
