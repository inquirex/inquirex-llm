# frozen_string_literal: true

module ExtractEval
  # Compares an extraction with the ground truth, field by field.
  #
  # enum, boolean and integer fields score 1 or 0. A multi_enum field scores
  # the Jaccard overlap of the two sets, so naming two of three add-ons earns
  # 2/3 rather than nothing. Integers accept a whole Float or a numeric
  # String, since a model writing 3.0 for "three" got the answer right.
  #
  # A null in the ground truth means the text never answered that field, and
  # the right reply is "unset": null, "" or []. A 0 or false is an answer
  # (no dependents, not self-employed) that the engine would prefill, so it
  # scores 0 there.
  module Scoring
    module_function

    # @param schema [Inquirex::LLM::Schema]
    # @param expected [Hash{String => Object}]
    # @param output [Hash] the extraction; String or Symbol keys
    # @return [Hash{String => Float}] field name => score in 0.0..1.0
    def field_scores(schema, expected, output)
      actual = stringify(output)
      schema.field_specs.to_h do |field, spec|
        [field.to_s, field_score(spec.type, expected[field.to_s], actual[field.to_s])]
      end
    end

    # @return [Float]
    def field_score(type, expected, actual)
      return unset?(actual) ? 1.0 : 0.0 if expected.nil?

      case type
      when :multi_enum then jaccard(expected, actual)
      when :integer then integer(actual) == expected ? 1.0 : 0.0
      when :boolean then actual.equal?(expected) ? 1.0 : 0.0
      else actual.to_s == expected.to_s && !actual.nil? ? 1.0 : 0.0
      end
    end

    # The share of fields the text left unanswered that the model also left
    # unset; nil when the truth answers every field.
    #
    # @return [Float, nil]
    def restraint(schema, expected, output)
      open_fields = schema.field_names.map(&:to_s).select { expected.key?(it) && expected[it].nil? }
      return nil if open_fields.empty?

      actual = stringify(output)
      open_fields.count { unset?(actual[it]) }.fdiv(open_fields.size)
    end

    # @return [Boolean] whether a reply leaves the field unanswered
    def unset?(value) = value.nil? || value == "" || value == []

    # @return [Float] |A ∩ B| / |A ∪ B|; 1.0 when both are empty
    def jaccard(expected, actual)
      return 0.0 unless actual.is_a?(Array)

      wanted = Array(expected).to_set(&:to_s)
      got = actual.to_set(&:to_s)
      union = wanted | got
      union.empty? ? 1.0 : (wanted & got).size.fdiv(union.size)
    end

    # @return [Integer, nil]
    def integer(value)
      case value
      when Integer then value
      when Float then value.to_i if value == value.floor
      when String then Integer(value.strip, 10, exception: false)
      end
    end

    # @return [Hash{String => Object}]
    def stringify(output)
      output.is_a?(Hash) ? output.transform_keys(&:to_s) : {}
    end
  end
end
