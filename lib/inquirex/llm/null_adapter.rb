# frozen_string_literal: true

module Inquirex
  module LLM
    # Test adapter that returns schema-conformant placeholder values without
    # calling any LLM API. Useful for testing flows that include LLM steps.
    #
    # For extract steps with a schema, returns a hash of default values
    # matching each field's declared type. Fields constrained to a list of
    # allowed values (enum/multi_enum resolved from questions) return the
    # first allowed value, so placeholders stay valid answers for the
    # downstream question. Without a schema, returns a placeholder string.
    #
    # @example
    #   adapter = Inquirex::LLM::NullAdapter.new
    #   result = adapter.call(extract_node, answers)
    #   # => { industry: "", employee_count: 0, entity_type: "llc", ... }
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
            acc[name] = placeholder_for(node.schema, name, type)
          end
        else
          "(placeholder #{node.verb} output for #{node.id})"
        end
      end

      private

      def placeholder_for(schema, name, type)
        values = schema.values_for(name)
        return TYPE_DEFAULTS.fetch(type, "") if values.nil? || values.empty?

        type == :multi_enum ? [values.first] : values.first
      end
    end
  end
end
