# frozen_string_literal: true

module Inquirex
  module LLM
    # Immutable definition of expected LLM output structure.
    # Each field maps a name to an Inquirex data type, forming the contract
    # between the LLM prompt and the structured data it must return.
    #
    # @example
    #   schema = Schema.new(
    #     industry:          :string,
    #     entity_type:       :enum,
    #     employee_count:    :integer,
    #     estimated_revenue: :currency
    #   )
    #   schema.fields          # => { industry: :string, ... }
    #   schema.field_names     # => [:industry, :entity_type, ...]
    #   schema.valid_output?({ industry: "Tech", ... })  # => true
    #
    # @attr_reader fields [Hash{Symbol => Symbol}] field_name => type mapping
    class Schema
      VALID_TYPES = %i[
        string text integer decimal currency boolean
        enum multi_enum date email phone
        array hash
      ].freeze

      attr_reader :fields

      # @param field_map [Hash{Symbol => Symbol}] field_name => type
      # @raise [Errors::DefinitionError] if any type is unrecognized
      def initialize(**field_map)
        raise Errors::DefinitionError, "Schema must have at least one field" if field_map.empty?

        validate_types!(field_map)
        @fields = field_map.transform_keys(&:to_sym)
                           .transform_values(&:to_sym)
                           .freeze
        freeze
      end

      # @return [Array<Symbol>] ordered list of field names
      def field_names = @fields.keys

      # @return [Integer] number of fields
      def size = @fields.size

      # Checks whether a Hash output conforms to the schema (all declared fields present).
      #
      # @param output [Hash] LLM output to validate
      # @return [Boolean]
      def valid_output?(output)
        return false unless output.is_a?(Hash)

        symbolized = output.transform_keys(&:to_sym)
        @fields.keys.all? { |key| symbolized.key?(key) }
      end

      # Returns the list of fields missing from the given output.
      #
      # @param output [Hash]
      # @return [Array<Symbol>]
      def missing_fields(output)
        return field_names unless output.is_a?(Hash)

        symbolized = output.transform_keys(&:to_sym)
        @fields.keys.reject { |key| symbolized.key?(key) }
      end

      # @return [Hash]
      def to_h
        @fields.transform_keys(&:to_s).transform_values(&:to_s)
      end

      # @return [String] JSON representation
      def to_json(*)
        JSON.generate(to_h)
      end

      # @param hash [Hash] string or symbol keys, values are type names
      # @return [Schema]
      def self.from_h(hash)
        field_map = hash.each_with_object({}) do |(k, v), acc|
          acc[k.to_sym] = v.to_sym
        end
        new(**field_map)
      end

      def ==(other)
        other.is_a?(Schema) && @fields == other.fields
      end

      def inspect
        "#<Inquirex::LLM::Schema #{@fields.map { |k, v| "#{k}:#{v}" }.join(", ")}>"
      end

      private

      def validate_types!(field_map)
        field_map.each do |name, type|
          next if VALID_TYPES.include?(type.to_sym)

          raise Errors::DefinitionError,
            "Unknown type #{type.inspect} for field #{name.inspect}. " \
            "Valid types: #{VALID_TYPES.join(", ")}"
        end
      end
    end
  end
end
