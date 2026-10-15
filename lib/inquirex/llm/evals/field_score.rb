# frozen_string_literal: true

module Inquirex
  module LLM
    module Evals
      # One field of one reply, graded against the truth. Every field ends in
      # one of five outcomes, each worth a fixed share of the point:
      #
      #   correct       1.0   what the text says, as the schema spells it
      #   missed        0.2   the text answers it and the reply left it unset (or the key out)
      #   hallucinated  0.15  the text never answers it and the reply answered anyway
      #   incorrect     0.1   an allowed value, the wrong one
      #   invalid       0     a value the schema does not allow: off the list, wrong type
      #
      # Missing beats inventing, and a wrong-but-legal answer beats junk,
      # because of what the engine does next: a missed field is asked, an
      # invented one is prefilled and skipped. A multi_enum is graded per
      # element, so two of three add-ons right is two thirds correct and one
      # third missed, and the field's value is the mean of its elements.
      #
      # The reply is read before the gem canonicalized it ({Extraction#raw}),
      # so a case variant the gem would repair is correct and noted, and an
      # off-list value the gem would turn into nil is invalid rather than
      # missed. `""` and `[]` where the truth is null are correct, with a note
      # about the form; `0` and `false` there are answers, and hallucinated.
      class FieldScore
        WEIGHTS = { correct: 1.0, missed: 0.2, hallucinated: 0.15, incorrect: 0.1, invalid: 0.0 }.freeze
        OUTCOMES = WEIGHTS.keys.freeze

        attr_reader :field, :shares, :note

        # @param field [String]
        # @param shares [Hash{Symbol => Rational}] each outcome's share of the field; they sum to 1
        # @param note [String, nil] what to tell a human about it, when there is something to tell
        def initialize(field:, shares:, note: nil)
          @field = field
          @shares = OUTCOMES.to_h { [it, shares.fetch(it, 0r)] }.freeze
          @note = note
          freeze
        end

        # @return [Float] the field's value in 0..1
        def value = shares.sum { |outcome, share| WEIGHTS.fetch(outcome) * share }.to_f

        # @param outcome [Symbol]
        # @return [Rational] how much of the field ended in the outcome
        def share(outcome) = shares.fetch(outcome)

        # @return [Boolean] whether the whole field was correct
        def correct? = share(:correct) == 1

        # @return [String] "correct", or "1/2 correct, 1/2 hallucinated"
        def outcome
          parts = shares.reject { |_, share| share.zero? }
          return parts.keys.first.to_s if parts.size == 1

          parts.map { |name, share| "#{share} #{name}" }.join(", ")
        end

        class << self
          # Grades one field.
          #
          # @param field [String]
          # @param spec [Inquirex::LLM::Schema::Field]
          # @param truth [Object, nil] the expected value; nil when the text never answers the field
          # @param got [Object, nil] the reply's value, as the model sent it
          # @param present [Boolean] whether the reply had the key at all
          # @return [FieldScore]
          def of(field, spec, truth, got, present: true)
            return whole(field, :missed, "key absent") unless present
            return multi(field, spec, truth, got) if spec.type == :multi_enum
            return silent(field, spec, got) if truth.nil?
            return whole(field, :missed) if unset?(got)

            answered(field, spec, truth, got)
          end

          # @return [Boolean] whether a value counts as "left unset"
          def unset?(value) = value.nil? || value == "" || value == []

          # The reply's Integer, when it can be read as one: an Integer, a
          # whole Float (3.0 for "three"), or a base-10 String.
          #
          # @param value [Object]
          # @return [Integer, nil]
          def integer(value)
            case value
            when Integer then value
            when Float then value.to_i if value == value.floor
            when String then Integer(value.strip, 10, exception: false)
            end
          end

          private

          def whole(field, outcome, note = nil) = new(field: field, shares: { outcome => 1r }, note: note)

          # The text never answers the field.
          def silent(field, spec, got)
            return whole(field, :correct) if got.nil?
            return whole(field, :correct, "form drift: expected null, got #{got.inspect}") if unset?(got)

            problem = problem(spec, got)
            problem ? whole(field, :invalid, problem) : whole(field, :hallucinated, "expected null, got #{got.inspect}")
          end

          # The text answers the field and the reply gave a value.
          def answered(field, spec, truth, got)
            problem = problem(spec, got)
            return whole(field, :invalid, problem) if problem

            value, repaired = read(spec, got)
            return whole(field, :incorrect, "expected #{truth.inspect}, got #{got.inspect}") unless value == truth

            whole(field, :correct, repaired ? "repaired: #{got.inspect} read as #{value.inspect}" : nil)
          end

          # What the schema objects to in a single value, or nil.
          def problem(spec, got)
            case spec.type
            when :enum then "#{got.inspect} is not one of #{spec.values.join("|")}" unless canonical(spec.values, got)
            when :boolean then "#{got.inspect} is not a boolean" unless [true, false].include?(got)
            when :integer then "#{got.inspect} is not an integer" unless integer(got)
            when :decimal, :currency then "#{got.inspect} is not a number" unless got.is_a?(Numeric) || Float(got, exception: false)
            else "#{got.inspect} is not a string" unless got.is_a?(String) || got.is_a?(Numeric)
            end
          end

          # The value as the schema spells it, and whether reading it changed it.
          #
          # @return [Array(Object, Boolean)]
          def read(spec, got)
            case spec.type
            when :enum then [canonical(spec.values, got), canonical(spec.values, got) != got]
            when :integer then [integer(got), !got.is_a?(Integer)]
            when :decimal, :currency then [Float(got), !got.is_a?(Numeric)]
            when :boolean then [got, false]
            else [got.to_s.strip, got.to_s.strip != got]
            end
          end

          # The allowed value a reply names, exactly or up to case and
          # whitespace, as {Adapter#normalize_output} reads it; nil when off the list.
          def canonical(values, got)
            candidate = got.to_s.strip
            values.find { it == candidate } || values.find { it.casecmp?(candidate) }
          end

          # Each element of a multi_enum is graded on its own: in both lists is
          # correct, truth-only is missed, reply-only is hallucinated, off the
          # list is invalid. An empty or absent reply against a null truth is
          # correct; against a list it misses every element.
          def multi(field, spec, truth, got)
            return whole(field, :invalid, "#{got.inspect} is not an array") unless got.nil? || got.is_a?(Array)
            return silent(field, spec, got) if truth.nil? && (got.nil? || got.empty?)

            wanted = Array(truth).map(&:to_s)
            named = Array(got).map { [it, canonical(spec.values, it)] }
            on = named.filter_map(&:last).uniq
            off = named.select { |_, value| value.nil? }.map(&:first)
            repaired = named.select { |raw, value| value && value != raw }.map(&:first)
            counts = { correct: (wanted & on).size, missed: (wanted - on).size, hallucinated: (on - wanted).size, invalid: off.size }
            total = counts.values.sum
            return whole(field, :correct) if total.zero?

            notes = [("missed #{(wanted - on).join(", ")}" if counts[:missed].positive?),
                     ("hallucinated #{(on - wanted).join(", ")}" if counts[:hallucinated].positive?),
                     ("invalid #{off.map(&:inspect).join(", ")}" if counts[:invalid].positive?),
                     ("repaired #{repaired.map(&:inspect).join(", ")}" if repaired.any?)].compact
            new(field: field, shares: counts.transform_values { Rational(it, total) }, note: notes.empty? ? nil : notes.join("; "))
          end
        end
      end
    end
  end
end
