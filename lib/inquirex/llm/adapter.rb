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
      # @return [Hash, String] structured output (for clarify/detour) or text (for describe/summarize)
      # @raise [Errors::AdapterError] if the LLM call fails
      # @raise [Errors::SchemaViolationError] if output doesn't match schema
      def call(node, answers)
        raise NotImplementedError, "#{self.class}#call must be implemented"
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
    end
  end
end
