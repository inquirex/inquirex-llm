# frozen_string_literal: true

RSpec.describe ExtractEval::JevAdapter do
  subject(:adapter) { described_class.new(model: "typesafe-api/jev-preview", api_key: "ts-test") }

  let(:fixture) { ExtractEval::Fixture.new("09_tax-preparation", dataset: "vague") }
  let(:jev) { instance_double(Inquirex::LLM::JevAdapter) }

  before do
    allow(Inquirex::LLM::JevAdapter).to receive(:new).and_return(jev)
    allow(jev).to receive(:extract).and_return(
      Inquirex::LLM::JevAdapter::Extraction.new(values: { irs_letter: true },
        confidence: { irs_letter: 0.97 },
        usage: { input_tokens: 1_000_000, output_tokens: 9 })
    )
  end

  its(:model) { is_expected.to eq("typesafe-api/jev-preview") }
  its(:effort) { is_expected.to be_nil }
  its(:temperature) { is_expected.to be_nil }
  its(:max_tokens) { is_expected.to be_nil }

  it "asks the gem's adapter for the model without the prefix" do
    adapter
    expect(Inquirex::LLM::JevAdapter).to have_received(:new).with(api_key: "ts-test", model: "jev-preview")
  end

  it "passes the text as the step's source answer, and adds confidences, tokens and cost" do
    expect(adapter.extract(fixture.node, fixture.text)).to eq(
      irs_letter:  true,
      _confidence: { irs_letter: 0.97 },
      _usage:      { input_tokens: 1_000_000, output_tokens: 9, cost_usd: 0.042 }
    )
    expect(jev).to have_received(:extract).with(fixture.node, { fixture.node.from_steps.first => fixture.text })
  end

  it "serves only typesafe-api models" do
    expect([described_class.serves?("typesafe-api/jev-latest"), described_class.serves?("typesafe/jev-router")])
      .to eq([true, false])
  end
end
