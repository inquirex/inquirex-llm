# frozen_string_literal: true

module ExtractEval
  # Offline consistency checks for one fixture, so a typo in the ground truth
  # is caught before it is billed as a model's mistake.
  class Verifier
    # @param fixture [Fixture]
    def initialize(fixture)
      @fixture = fixture
    end

    # @return [Array<String>] problems found; empty when the fixture is sound
    def problems
      problems = []
      problems << "schema/#{@fixture.name}.rb differs from the DSL's extract schema" unless @fixture.schema == @fixture.node.schema
      problems << "#{@fixture.dataset}/extracted-answers/#{@fixture.name}.txt is empty" if @fixture.text.empty?
      problems.concat(truth_problems)
    rescue Errno::ENOENT, JSON::ParserError, Inquirex::Errors::Error, Error, SyntaxError => e
      ["#{e.class}: #{e.message}"]
    end

    private

    def truth_problems
      schema = @fixture.schema
      truth = @fixture.truth
      missing = schema.field_names.map(&:to_s) - truth.keys
      extra = truth.keys - schema.field_names.map(&:to_s)
      problems = []
      problems << "ground truth is missing #{missing.join(", ")}" if missing.any?
      problems << "ground truth has unknown fields #{extra.join(", ")}" if extra.any?
      schema.field_specs.each do |field, spec|
        next if truth[field.to_s].nil? # unanswered by the text: the model must leave it unset

        problem = value_problem(spec, truth[field.to_s])
        problems << "#{field}: #{problem}" if problem
      end
      problems
    end

    def value_problem(spec, value)
      case spec.type
      when :enum then "#{value.inspect} is not one of #{spec.values.join("|")}" unless spec.values.include?(value)
      when :multi_enum
        return "#{value.inspect} is not an array" unless value.is_a?(Array)

        stray = value - spec.values
        "#{stray.join(", ")} not in #{spec.values.join("|")}" if stray.any?
      when :integer then "#{value.inspect} is not an integer" unless value.is_a?(Integer)
      when :boolean then "#{value.inspect} is not a boolean" unless [true, false].include?(value)
      end
    end
  end
end
