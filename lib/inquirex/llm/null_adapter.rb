# frozen_string_literal: true

module Inquirex
  module LLM
    # Test adapter that returns schema-conformant placeholder values without
    # calling any LLM API. Useful for testing flows that include LLM steps.
    #
    # For clarify/detour steps with a schema, returns a hash of default values
    # matching each field's declared type. For describe/summarize steps, returns
    # a placeholder string.
    #
    # @example
    #   adapter = Inquirex::LLM::NullAdapter.new
    #   result = adapter.call(clarify_node, answers)
    #   # => { industry: "", employee_count: 0, ... }
    class NullAdapter < Adapter
      TYPE_DEFAULTS = {
        string:     "",
        text:       "",
        integer:    0,
        decimal:    0.0,
        currency:   0.0,
        boolean:    false,
        enum:       "",
        multi_enum: [],
        date:       "",
        email:      "",
        phone:      "",
        array:      [],
        hash:       {}
      }.freeze

      # Returns placeholder output matching the node's schema or verb.
      #
      # @param node [LLM::Node]
      # @param _answers [Hash] ignored
      # @return [Hash, String]
      def call(node, _answers = {})
        if node.schema
          node.schema.fields.each_with_object({}) do |(name, type), acc|
            acc[name] = TYPE_DEFAULTS.fetch(type, "")
          end
        else
          "(placeholder #{node.verb} output for #{node.id})"
        end
      end
    end
  end
end
