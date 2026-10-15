# frozen_string_literal: true

module ExtractEval
  # One model at one setting over every fixture: a single Braintrust
  # experiment, plus the per-case detail the terminal report needs.
  class Experiment
    DEFAULT_PROJECT = "inquirex-llm-extract"
    SCORERS = %w[field_accuracy exact_match valid_json restraint].freeze

    # What one finished experiment reports back.
    # tokens is { input_tokens:, output_tokens:, cost_usd: }, summed over the cases.
    Summary = Data.define(:model,
      :effort,
      :temperature,
      :dataset,
      :means,
      :cases,
      :errors,
      :duration,
      :permalink,
      :tokens)

    # What one finished case reports back.
    CaseResult = Data.define(:fixture, :score, :wrong)

    attr_reader :adapter, :fixtures, :dataset

    # @param adapter [OpenRouterAdapter]
    # @param fixtures [Array<Fixture>]
    # @param project [String, nil] Braintrust project name, created when missing
    # @param project_id [String, nil] Braintrust project UUID; wins over the name
    # @param parallelism [Integer] cases in flight at once
    # With neither project nor project_id the experiment runs locally.
    def initialize(adapter:, fixtures:, project: DEFAULT_PROJECT, project_id: nil, parallelism: 4)
      @adapter = adapter
      @fixtures = fixtures.to_h { [it.name, it] }
      @dataset = fixtures.first&.dataset || Fixture::DEFAULT_DATASET
      @project = project_id ? nil : project
      @project_id = project_id
      @parallelism = parallelism
      @cases = {}
      @tokens = { input_tokens: 0, output_tokens: 0, cost_usd: 0.0 }
      @lock = Mutex.new
      fixtures.each { it.node && it.schema && it.truth && it.text } # warm the memos before threads share them
    end

    # @return [String] e.g. "anthropic/claude-sonnet-5.5 effort=low t=0.0 [vague]"
    def name
      "#{adapter.model} effort=#{adapter.effort || "default"} " \
        "t=#{adapter.temperature.nil? ? "default" : adapter.temperature} [#{dataset}]"
    end

    # @param on_case [#call, nil] called once per finished case
    # @return [Summary]
    def run(on_case: nil)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Braintrust::Eval.run(
        project:     @project,
        project_id:  @project_id,
        experiment:  name,
        cases:       cases,
        task:        task,
        scorers:     scorers,
        parallelism: @parallelism,
        quiet:       true,
        on_progress: ->(_) { on_case&.call },
        metadata:    { model: adapter.model, effort: adapter.effort, temperature: adapter.temperature,
                       max_tokens: adapter.max_tokens, dataset: dataset, prompt: "Inquirex::LLM::OpenAIAdapter" },
        tags:        ["extract", adapter.model, "dataset-#{dataset}"]
      )
      summarize(result, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    # @return [Array<Hash>] Braintrust cases, one per fixture
    def cases
      @fixtures.values.map do |fixture|
        { input: { case: fixture.name, text: fixture.text }, expected: fixture.truth,
          metadata: { case: fixture.name, difficulty: fixture.difficulty, dataset: dataset },
          tags: ["difficulty-#{fixture.difficulty}", "dataset-#{dataset}"] }
      end
    end

    # The task: the extraction, or `_error` when the reply was not a JSON
    # object. A malformed reply is the model's failure and scores 0; a
    # transport error is not, and is left to raise so Braintrust records it.
    #
    # @return [#call]
    def task
      lambda do |input:|
        fixture = @fixtures.fetch(input[:case] || input["case"])
        output = adapter.extract(fixture.node, fixture.text)
        count(output[:_usage])
        output.transform_keys(&:to_s)
      rescue Inquirex::LLM::Errors::AdapterError => e
        { "_error" => e.message }
      end
    end

    # @return [Array<Braintrust::Scorer>]
    def scorers
      [
        Braintrust::Scorer.new("field_accuracy") { |expected:, output:, metadata:| field_accuracy(expected, output, metadata) },
        Braintrust::Scorer.new("exact_match") { |expected:, output:, metadata:| exact?(expected, output, metadata) ? 1.0 : 0.0 },
        Braintrust::Scorer.new("valid_json") { |output:, metadata:| valid?(output, metadata) ? 1.0 : 0.0 },
        Braintrust::Scorer.new("restraint") { |expected:, output:, metadata:| restraint(expected, output, metadata) }
      ]
    end

    private

    def count(usage)
      return unless usage

      @lock.synchronize { @tokens.each_key { @tokens[it] += usage.fetch(it, 0) || 0 } }
    end

    def fixture_for(metadata) = @fixtures.fetch(metadata[:case] || metadata["case"])

    def field_accuracy(expected, output, metadata)
      fixture = fixture_for(metadata)
      scores = Scoring.field_scores(fixture.schema, expected, output)
      score = scores.values.sum / scores.size
      wrong = scores.select { |_, value| value < 1.0 }.to_h do |field, _|
        [field, { "expected" => expected[field], "actual" => Scoring.stringify(output)[field] }]
      end
      @lock.synchronize { @cases[fixture.name] = CaseResult.new(fixture: fixture, score: score, wrong: wrong) }
      { score: score, metadata: { wrong: wrong, error: Scoring.stringify(output)["_error"] }.compact }
    end

    def exact?(expected, output, metadata)
      Scoring.field_scores(fixture_for(metadata).schema, expected, output).values.all?(1.0)
    end

    # No score at all (not 1.0) when the truth answers every field, so the
    # clear dataset does not inflate the mean with free points.
    def restraint(expected, output, metadata)
      score = Scoring.restraint(fixture_for(metadata).schema, expected, output)
      score.nil? ? [] : score
    end

    def valid?(output, metadata)
      output.is_a?(Hash) && !output.key?("_error") && fixture_for(metadata).schema.missing_fields(output).empty?
    end

    def summarize(result, duration)
      means = SCORERS.to_h do |scorer|
        values = Array(result.scores&.fetch(scorer, nil))
        [scorer, values.empty? ? nil : values.sum / values.size]
      end
      Summary.new(
        model:       adapter.model,
        effort:      adapter.effort,
        temperature: adapter.temperature,
        dataset:     dataset,
        means:       means,
        cases:       @cases.values.sort_by { it.fixture.name },
        errors:      result.errors,
        duration:    duration,
        permalink:   result.permalink,
        tokens:      @tokens.dup
      )
    end
  end
end
