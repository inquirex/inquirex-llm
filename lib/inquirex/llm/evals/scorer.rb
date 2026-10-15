# frozen_string_literal: true

module Inquirex
  module LLM
    module Evals
      # Grades one reply against one case, field by field, through
      # {FieldScore}. Pure: it reads the case, the reply and the schema the
      # adapter put in the context, and calls nothing.
      #
      # Four metrics per case. `score`, the primary, is the mean of the
      # fields' values. `exact` is 1 when every field is correct.
      # `hallucinated_rate` is, over the fields the text never answers, the
      # share the model answered anyway; it is nil when the truth has no
      # null, so a dataset of complete texts neither earns nor loses by it.
      # `invalid_rate` is the share of fields the schema would reject.
      class Scorer < Agent::Evals::Scorer
        METRICS = [
          Agent::Evals::Metric.new(name: "score",
            primary: true,
            description: "Mean field value: correct 1.0, missed 0.2, hallucinated 0.15, incorrect 0.1, invalid 0; " \
                         "a multi_enum is the mean of its elements."),
          Agent::Evals::Metric.new(name: "exact", description: "1 when every field is correct."),
          Agent::Evals::Metric.new(name: "hallucinated_rate",
            description: "Of the fields the text never answers (truth null), the share the model answered anyway; " \
                         "nothing recorded when the truth has no null."),
          Agent::Evals::Metric.new(name: "invalid_rate",
            description: "Share of fields whose value the schema does not allow: off the list, wrong type.")
        ].freeze

        # How the gem's field types read to {Agent::Evals::SchemaValidator}.
        VALIDATOR_TYPES = { enum: :enum, multi_enum: :multi_enum, integer: :integer, boolean: :boolean,
                            decimal: :number, currency: :number }.freeze

        # @return [Array<Agent::Evals::Metric>]
        def metrics = METRICS

        # @param kase [Agent::Evals::Case]
        # @param reply [Agent::Evals::Reply]
        # @param context [Hash] `:schema`, the {Inquirex::LLM::Schema} the dataset extracts
        # @return [Agent::Evals::Score]
        def call(kase, reply, context:)
          schema = context.fetch(:schema)
          fields = field_scores(schema, kase.expected, reply.raw)
          open = fields.select { kase.expected[it.field].nil? }
          Agent::Evals::Score.new(
            value:       mean(fields.map(&:value)),
            metrics:     { "score"             => mean(fields.map(&:value)),
                           "exact"             => fields.all?(&:correct?) ? 1.0 : 0.0,
                           "hallucinated_rate" => open.empty? ? nil : mean(open.map { it.share(:hallucinated) }),
                           "invalid_rate"      => mean(fields.map { it.share(:invalid) }) },
            outcomes:    fields.to_h { [it.field, it.outcome] },
            diagnostics: diagnostics(fields, kase.expected, reply.raw)
          )
        end

        # Grades every schema field. A reply that is not a JSON object fails
        # every field as invalid; the gem's canonicalization is deliberately
        # not consulted, see {FieldScore}.
        #
        # @param schema [Inquirex::LLM::Schema]
        # @param expected [Hash{String => Object}]
        # @param raw [Hash, nil] the reply as the model sent it, String or Symbol keys
        # @return [Array<FieldScore>]
        def field_scores(schema, expected, raw)
          got = raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : nil
          schema.field_specs.map do |name, spec|
            field = name.to_s
            next FieldScore.new(field: field, shares: { invalid: 1r }, note: "reply is not a JSON object") if got.nil?

            FieldScore.of(field, spec, expected[field], got[field], present: got.key?(field))
          end
        end

        # Checks expected.json against the schema, every field nullable: a
        # null is how the truth says the text never answers it.
        #
        # @param kase [Agent::Evals::Case]
        # @param context [Hash]
        # @return [Array<String>] unknown keys, missing keys, off-list values, wrong types
        def verify(kase, context:)
          schema = context.fetch(:schema)
          fields = schema.field_specs.to_h do |name, spec|
            [name.to_s, { type: VALIDATOR_TYPES.fetch(spec.type, :string), enum: spec.values, nullable: true }]
          end
          Agent::Evals::SchemaValidator.new(fields).problems(kase.expected)
        end

        # @param kase [Agent::Evals::Case]
        # @return [String] "answered 7/10"
        def summary(kase)
          return nil unless kase.expected.is_a?(Hash)

          "answered #{kase.expected.count { |_, value| !value.nil? }}/#{kase.expected.size}"
        end

        private

        def mean(values) = values.empty? ? 0.0 : values.sum.fdiv(values.size)

        # One entry per field that was not plainly correct, or that carries a
        # note (a repair, a form drift), with what was wanted and what came.
        def diagnostics(fields, expected, raw)
          got = raw.is_a?(Hash) ? raw.transform_keys(&:to_s) : {}
          fields.reject { it.correct? && it.note.nil? }.to_h do |score|
            [score.field, { outcome: score.outcome, want: expected[score.field], got: got[score.field], note: score.note }.compact]
          end
        end
      end
    end
  end
end
