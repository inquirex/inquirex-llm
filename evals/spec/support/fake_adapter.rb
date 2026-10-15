# frozen_string_literal: true

# Stands in for OpenRouterAdapter: answers every case with its ground truth,
# except the cases told to fail or to reply with junk.
class FakeAdapter
  attr_reader :model, :effort, :temperature, :max_tokens

  def initialize(model: "fake/model", effort: nil, temperature: 0.2, max_tokens: 4096, junk: [], wrong: {})
    @model = model
    @effort = effort
    @temperature = temperature
    @max_tokens = max_tokens
    @junk = junk
    @wrong = wrong
  end

  def extract(_node, text)
    fixture = ExtractEval::Fixture.datasets.flat_map { ExtractEval::Fixture.all(dataset: it) }.find { it.text == text }
    raise Inquirex::LLM::Errors::AdapterError, "not JSON" if @junk.include?(fixture.name)

    fixture.truth.merge(@wrong.fetch(fixture.name, {})).transform_keys(&:to_sym)
           .merge(_usage: { input_tokens: 100, output_tokens: 10, cost_usd: 0.001 })
  end
end
