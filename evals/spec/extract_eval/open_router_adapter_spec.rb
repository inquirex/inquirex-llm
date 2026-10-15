# frozen_string_literal: true

RSpec.describe ExtractEval::OpenRouterAdapter do
  subject(:adapter) { described_class.new(model: "acme/m1", effort: "low", temperature: 0.0, max_tokens: 500, api_key: "k") }

  let(:fixture) { ExtractEval::Fixture.new("04_immigration-law") }
  let(:chat) { instance_double(RubyLLM::Chat) }
  let(:reply) { "```json\n#{JSON.generate(fixture.truth.merge("current_status" => "Student"))}\n```" }

  before do
    allow(RubyLLM).to receive(:chat).and_return(chat)
    %i[with_instructions with_temperature with_max_output_tokens with_thinking with_provider_options].each do |name|
      allow(chat).to receive(name).and_return(chat)
    end
    tokens = RubyLLM::Tokens.new(input: 1200, output: 80, reported_cost: 0.0003)
    allow(chat).to receive(:ask).and_return(instance_double(RubyLLM::Message, content: reply, tokens: tokens))
  end

  it "returns the canonicalized extraction" do
    expect(adapter.extract(fixture.node, fixture.text).except(:_usage).transform_keys(&:to_s)).to eq(fixture.truth)
  end

  it "reports the tokens and the cost OpenRouter billed" do
    expect(adapter.extract(fixture.node, fixture.text)[:_usage])
      .to eq(input_tokens: 1200, output_tokens: 80, cost_usd: 0.0003)
  end

  it "sends the gem's prompts to the model through OpenRouter" do
    adapter.extract(fixture.node, fixture.text)
    expect(RubyLLM).to have_received(:chat).with(model: "acme/m1", provider: :openrouter, assume_model_exists: true)
  end

  it "puts the visitor's text in the user prompt" do
    adapter.extract(fixture.node, fixture.text)
    expect(chat).to have_received(:ask).with(include("situation: #{fixture.text.inspect}"))
  end

  describe "request settings" do
    before { adapter.extract(fixture.node, fixture.text) }

    it { expect(chat).to have_received(:with_thinking).with(effort: :low) }
    it { expect(chat).to have_received(:with_temperature).with(0.0) }
    it { expect(chat).to have_received(:with_max_output_tokens).with(500) }
    it { expect(chat).to have_received(:with_provider_options).with(response_format: { type: "json_object" }) }
  end

  context "with the model's own defaults" do
    subject(:adapter) { described_class.new(model: "acme/m1", api_key: "k") }

    before { adapter.extract(fixture.node, fixture.text) }

    it { expect(chat).not_to have_received(:with_thinking) }
    it { expect(chat).not_to have_received(:with_temperature) }
  end

  context "when the reply is not JSON" do
    let(:reply) { "Sure! The status is student." }

    it { expect { adapter.extract(fixture.node, fixture.text) }.to raise_error(Inquirex::LLM::Errors::AdapterError) }
  end

  it "raises without a key" do
    allow(Inquirex::LLM.configuration).to receive(:openrouter_api_key).and_return(nil)
    expect { described_class.new(model: "m") }.to raise_error(ArgumentError, /OPENROUTER_API_KEY/)
  end

  it { expect { described_class.new(model: "m", effort: "huge", api_key: "k") }.to raise_error(ArgumentError, /effort/) }
end
