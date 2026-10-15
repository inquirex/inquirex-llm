# frozen_string_literal: true

require "net/http"

RSpec.describe Inquirex::LLM::OpenRouterAdapter do
  subject(:adapter) { described_class.new(api_key: "sk-or-test", effort: effort) }

  let(:effort) { nil }
  let(:node) do
    Inquirex::LLM::Node.new(
      id:         :extracted,
      verb:       :extract,
      prompt:     "Extract the filing details.",
      schema:     Inquirex::LLM::Schema.new(filing_status: :string),
      from_steps: [:tell_me],
      model:      :claude_haiku
    )
  end
  let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, :read_timeout= => nil, :open_timeout= => nil) }
  let(:sent) { {} }

  def ok(text)
    instance_double(Net::HTTPOK, body: JSON.generate("choices" => [{ "message" => { "content" => text } }]))
      .tap { allow(it).to receive(:is_a?).and_return(true) }
  end

  before do
    allow(Net::HTTP).to receive(:new) { |host, _| sent[:host] = host and http }
    allow(http).to receive(:request) do |request|
      sent[:auth] = request["Authorization"]
      sent[:body] = JSON.parse(request.body)
      ok('{"filing_status":"single"}')
    end
  end

  it { is_expected.to be_a(Inquirex::LLM::OpenAIAdapter) }

  describe "#call" do
    subject(:result) { adapter.call(node, { tell_me: "I'm single." }) }

    it { is_expected.to eq(filing_status: "single") }

    it "posts to OpenRouter with its key" do
      result
      expect(sent).to include(host: "openrouter.ai", auth: "Bearer sk-or-test")
    end

    it "maps the DSL symbol to an OpenRouter id" do
      result
      expect(sent[:body]["model"]).to eq("anthropic/claude-haiku-5.5")
    end

    it "sends no reasoning field without an effort" do
      result
      expect(sent[:body]).not_to have_key("reasoning")
    end

    context "with an effort" do
      let(:effort) { "low" }

      it "sends it as OpenRouter's reasoning effort" do
        result
        expect(sent[:body]["reasoning"]).to eq("effort" => "low")
      end
    end

    it "names OpenRouter in an API error" do
      error = instance_double(Net::HTTPBadRequest, code: "402", body: "no credits")
      allow(error).to receive(:is_a?).and_return(false)
      allow(http).to receive(:request).and_return(error)
      expect { result }.to raise_error(Inquirex::LLM::Errors::AdapterError, /OpenRouter API error 402/)
    end
  end

  describe "#initialize" do
    it "reads the key and model from the configuration" do
      with_env("OPENROUTER_API_KEY" => "sk-cfg", "INQUIREX_LLM_OPENROUTER_MODEL" => "google/gemini-2.5-flash") do
        expect(described_class.new.instance_variable_get(:@default_model)).to eq("google/gemini-2.5-flash")
      end
    end

    it "raises without a key" do
      with_env("OPENROUTER_API_KEY" => nil) do
        expect { described_class.new }.to raise_error(ArgumentError, /OPENROUTER_API_KEY/)
      end
    end

    it "rejects an unknown effort" do
      expect { described_class.new(api_key: "k", effort: "turbo") }.to raise_error(ArgumentError, /effort must be one of/)
    end
  end
end
