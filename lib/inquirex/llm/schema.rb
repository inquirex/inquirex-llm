# frozen_string_literal: true

module Inquirex
  module LLM
    # Immutable definition of expected LLM output structure.
    # Each field maps a name to a spec: an Inquirex data type, plus — for
    # :enum / :multi_enum fields — the exhaustive list of allowed values.
    # Together they form the contract between the LLM prompt and the
    # structured data it must return.
    #
    # A field spec is given either as a bare type symbol or as a Hash with
    # :type and optional :values:
    #
    # @example
    #   schema = Schema.new(
    #     industry:       :string,
    #     employee_count: :integer,
    #     entity_type:    { type: :enum, values: %w[llc s_corp c_corp] }
    #   )
    #   schema.fields                    # => { industry: :string, ... }
    #   schema.values_for(:entity_type)  # => ["llc", "s_corp", "c_corp"]
    #   schema.valid_output?({ industry: "Tech", ... })  # => true
    #
    # @attr_reader field_specs [Hash{Symbol => Field}] field_name => spec mapping
    class Schema
      VALID_TYPES = %i[
        string text integer decimal currency boolean
        enum multi_enum date email phone
        array hash
      ].freeze

      # A single field's contract: its data type and, for enum-like types,
      # the allowed values the LLM must choose from.
      Field = Data.define(:type, :values)

      attr_reader :field_specs

      # @param field_map [Hash{Symbol => Symbol, Hash}] field_name => type,
      #   or field_name => { type: Symbol, values: Array }
      # @raise [Errors::DefinitionError] if any type is unrecognized
      def initialize(**field_map)
        raise Errors::DefinitionError, "Schema must have at least one field" if field_map.empty?

        @field_specs = field_map.to_h { |name, spec| [name.to_sym, build_field(name, spec)] }.freeze
        @fields = @field_specs.transform_values(&:type).freeze
        freeze
      end

      # @return [Hash{Symbol => Symbol}] field_name => type mapping
      attr_reader :fields

      # @return [Array<Symbol>] ordered list of field names
      def field_names = @field_specs.keys

      # @return [Integer] number of fields
      def size = @field_specs.size

      # Allowed values for an enum/multi_enum field, or nil when unconstrained.
      #
      # @param name [Symbol, String]
      # @return [Array<String>, nil]
      def values_for(name)
        @field_specs[name.to_sym]&.values
      end

      # Checks whether a Hash output conforms to the schema (all declared fields present).
      #
      # @param output [Hash] LLM output to validate
      # @return [Boolean]
      def valid_output?(output)
        return false unless output.is_a?(Hash)

        symbolized = output.transform_keys(&:to_sym)
        @field_specs.keys.all? { |key| symbolized.key?(key) }
      end

      # Returns the list of fields missing from the given output.
      #
      # @param output [Hash]
      # @return [Array<Symbol>]
      def missing_fields(output)
        return field_names unless output.is_a?(Hash)

        symbolized = output.transform_keys(&:to_sym)
        @field_specs.keys.reject { |key| symbolized.key?(key) }
      end

      # Wire format. Fields without value constraints serialize as a plain
      # type string (the pre-0.6 shape); constrained fields serialize as
      # { "type" => ..., "values" => [...] }.
      #
      # @return [Hash]
      def to_h
        @field_specs.each_with_object({}) do |(name, field), acc|
          acc[name.to_s] =
            if field.values
              { "type" => field.type.to_s, "values" => field.values }
            else
              field.type.to_s
            end
        end
      end

      # @return [String] JSON representation
      def to_json(*)
        JSON.generate(to_h)
      end

      # Accepts both wire shapes: plain type strings and rich
      # { "type" => ..., "values" => [...] } specs.
      #
      # @param hash [Hash] string or symbol keys
      # @return [Schema]
      def self.from_h(hash)
        field_map = hash.each_with_object({}) do |(k, v), acc|
          acc[k.to_sym] = v
        end
        new(**field_map)
      end

      def ==(other)
        other.is_a?(Schema) && @field_specs == other.field_specs
      end

      def inspect
        parts = @field_specs.map do |name, field|
          field.values ? "#{name}:#{field.type}(#{field.values.join("|")})" : "#{name}:#{field.type}"
        end
        "#<Inquirex::LLM::Schema #{parts.join(", ")}>"
      end

      private

      def build_field(name, spec)
        case spec
        when Hash
          type = spec[:type] || spec["type"]
          values = spec[:values] || spec["values"]
          raise Errors::DefinitionError, "Field #{name.inspect} spec is missing :type" if type.nil?

          Field.new(type: validated_type(name, type), values: values&.map(&:to_s)&.freeze)
        else
          Field.new(type: validated_type(name, spec), values: nil)
        end
      end

      def validated_type(name, type)
        sym = type.to_sym
        return sym if VALID_TYPES.include?(sym)

        raise Errors::DefinitionError,
          "Unknown type #{type.inspect} for field #{name.inspect}. " \
          "Valid types: #{VALID_TYPES.join(", ")}"
      end
    end
  end
end
