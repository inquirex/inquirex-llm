# frozen_string_literal: true

require "net/http"

RSpec.describe Inquirex::LLM::Extraction do
  subject(:extraction) do
    described_class.new(output: { filing_status: "single", dependents: nil },
      raw: { filing_status: "Single", dependents: "none" },
      usage: { input_tokens: 10, output_tokens: 2 })
  end

  describe "as the Hash it replaces" do
    it { is_expected.to be_a(Hash) }
    it { is_expected.to eq(filing_status: "single", dependents: nil) }
    it { is_expected.to be_frozen }
    its(:keys) { are_expected.to eq(%i[filing_status dependents]) }
    its(:output) { is_expected.to eq(filing_status: "single", dependents: nil) }
    its(:output) { is_expected.to be_an_instance_of(Hash) }

    it "answers [], fetch, dig and each" do
      expect(extraction[:filing_status]).to eq("single")
      expect(extraction.fetch(:dependents)).to be_nil
      expect(extraction.dig(:filing_status)).to eq("single")
      expect(extraction.map { |key, _| key }).to eq(%i[filing_status dependents])
    end

    it "compares equal to a plain Hash from either side" do
      expect(extraction == { filing_status: "single", dependents: nil }).to be(true)
      plain = { filing_status: "single", dependents: nil }
      expect(plain == extraction).to be(true) # Hash#== from the plain side
    end

    it "serializes as its values alone" do
      expect(JSON.parse(JSON.generate(extraction))).to eq("filing_status" => "single", "dependents" => nil)
    end

    it "is taken up by the engine's prefill!" do
      definition = Inquirex.define(id: "x") do
        start :tell_me
        ask(:tell_me) { type :text; question "Tell me."; transition to: :filing_status }
        ask(:filing_status) { type :text; question "Status?"; transition to: :done }
        say(:done) { text "Done." }
      end
      engine = Inquirex::Engine.new(definition)
      engine.answer("I'm single.")
      engine.prefill!(extraction)
      expect(engine.answers).to include(filing_status: "single")
    end
  end

  describe "what rides along" do
    its(:raw) { is_expected.to eq(filing_status: "Single", dependents: "none") }
    its(:raw) { is_expected.to be_frozen }
    its(:usage) { is_expected.to eq(input_tokens: 10, output_tokens: 2) }
    its(:inspect) { is_expected.to include("Inquirex::LLM::Extraction", "raw=", "usage=") }

    it "has no raw and an empty usage when the adapter knows neither" do
      bare = described_class.new(output: { a: 1 })
      expect(bare.raw).to be_nil
      expect(bare.usage).to eq({})
    end
  end

  describe "from the adapters" do
    let(:schema) { Inquirex::LLM::Schema.new(filing_status: { type: :enum, values: %w[single married] }, dependents: :integer) }
    let(:node) { Inquirex::LLM::Node.new(id: :extracted, verb: :extract, prompt: "Extract.", schema: schema, from_steps: [:tell_me]) }
    let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, :read_timeout= => nil, :open_timeout= => nil) }
    let(:requests) { [] }

    def ok(body)
      instance_double(Net::HTTPOK, body: JSON.generate(body)).tap { allow(it).to receive(:is_a?).and_return(true) }
    end

    before do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:request) { |request| requests << request and response }
    end

    shared_examples "one call, raw kept" do
      it "makes exactly one HTTP call per extraction" do
        adapter.call(node, { tell_me: "I'm SINGLE with a dog." })
        expect(requests.size).to eq(1)
      end

      it "repairs the case variant in the output and keeps the off-list value in raw" do
        extraction = adapter.call(node, { tell_me: "I'm SINGLE with a dog." })
        expect(extraction).to eq(filing_status: "single", dependents: nil)
        expect(extraction.raw).to eq(filing_status: "SINGLE", dependents: nil)
      end

      it "reports the tokens in one shape" do
        expect(adapter.call(node, { tell_me: "x" }).usage).to eq(input_tokens: 50, output_tokens: 7)
      end
    end

    context "with OpenAIAdapter" do
      let(:adapter) { Inquirex::LLM::OpenAIAdapter.new(api_key: "k") }
      let(:response) do
        ok("choices" => [{ "message" => { "content" => '{"filing_status":"SINGLE","dependents":null}' } }],
          "usage" => { "prompt_tokens" => 50, "completion_tokens" => 7 })
      end

      it_behaves_like "one call, raw kept"
    end

    context "with AnthropicAdapter" do
      let(:adapter) { Inquirex::LLM::AnthropicAdapter.new(api_key: "k") }
      let(:response) do
        ok("content" => [{ "type" => "text", "text" => '{"filing_status":"SINGLE","dependents":null}' }],
          "usage" => { "input_tokens" => 50, "output_tokens" => 7 })
      end

      it_behaves_like "one call, raw kept"
    end

    context "with OpenRouterAdapter, which reports the cost" do
      let(:adapter) { Inquirex::LLM::OpenRouterAdapter.new(api_key: "k") }
      let(:response) do
        ok("choices" => [{ "message" => { "content" => '{"filing_status":"married","dependents":2}' } }],
          "usage" => { "prompt_tokens" => 50, "completion_tokens" => 7, "cost" => 0.00012 })
      end

      it "carries the cost in usage" do
        expect(adapter.call(node, { tell_me: "x" }).usage).to eq(input_tokens: 50, output_tokens: 7, cost_usd: 0.00012)
      end
    end
  end
end
