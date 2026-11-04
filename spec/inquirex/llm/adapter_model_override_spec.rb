# frozen_string_literal: true

require "net/http"

# Routing passes `model:` to every built-in adapter; without it, each keeps
# choosing the model the way it did before 0.13.0.
RSpec.describe "Adapter model override" do
  let(:bodies) { [] }
  let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, :read_timeout= => nil, :open_timeout= => nil) }
  let(:node) do
    Inquirex::LLM::Node.new(id: :facts,
      verb: :extract,
      prompt: "p",
      from_steps: [:a],
      schema: Inquirex::LLM::Schema.new(name: :string),
      model: :claude_sonnet)
  end
  let(:summary) { Inquirex::LLM::Node.new(id: :summary, verb: :summarize, prompt: "s") }

  def ok(body) = instance_double(Net::HTTPOK, is_a?: true, body: JSON.generate(body), code: "200")

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) { |request| (bodies << JSON.parse(request.body)) && response }
  end

  describe Inquirex::LLM::OpenAIAdapter do
    subject(:adapter) { described_class.new(api_key: "k") }

    let(:response) do
      ok("choices" => [{ "message" => { "content" => '{"name":"Alan Turing"}' } }], "usage" => {})
    end

    it "extracts with the given model" do
      adapter.call(node, { a: "x" }, model: "gpt-4.1-mini")
      expect(bodies.last["model"]).to eq("gpt-4.1-mini")
    end

    it "summarizes with the given model" do
      adapter.summarize(summary, "Q: a\nA: b", {}, model: "gpt-4.1-mini")
      expect(bodies.last["model"]).to eq("gpt-4.1-mini")
    end

    it "keeps the node's hint without one" do
      adapter.call(node, { a: "x" })
      expect(bodies.last["model"]).not_to eq("gpt-4.1-mini")
    end
  end

  describe Inquirex::LLM::OpenRouterAdapter do
    subject(:adapter) { described_class.new(api_key: "k") }

    let(:response) do
      ok("choices" => [{ "message" => { "content" => '{"name":"Alan Turing"}' } }], "usage" => {})
    end

    it "sends the vendor/model name as is" do
      adapter.call(node, { a: "x" }, model: "deepseek/deepseek-v4.1-flash")
      expect(bodies.last["model"]).to eq("deepseek/deepseek-v4.1-flash")
    end
  end

  describe Inquirex::LLM::AnthropicAdapter do
    subject(:adapter) { described_class.new(api_key: "k") }

    let(:response) { ok("content" => [{ "type" => "text", "text" => '{"name":"Alan Turing"}' }], "usage" => {}) }

    it "extracts with the given model" do
      adapter.call(node, { a: "x" }, model: "claude-haiku-5-5")
      expect(bodies.last["model"]).to eq("claude-haiku-5-5")
    end

    it "summarizes with the given model" do
      adapter.summarize(summary, "Q: a\nA: b", {}, model: "claude-haiku-5-5")
      expect(bodies.last["model"]).to eq("claude-haiku-5-5")
    end
  end

  describe Inquirex::LLM::JevAdapter do
    subject(:adapter) { described_class.new(api_key: "k") }

    let(:node) do
      Inquirex::LLM::Node.new(id: :facts,
        verb: :extract,
        prompt: "p",
        from_steps: [:a],
        schema: Inquirex::LLM::Schema.new(single: :boolean))
    end
    let(:response) do
      ok("answers" => { "single" => { "type" => "choice", "choice" => "yes", "confidence" => 0.9 } }, "usage" => {})
    end

    it "asks the given Jev model" do
      adapter.call(node, { a: "I am single" }, model: "jev-preview")
      expect(bodies.last["model"]).to eq("jev-preview")
    end

    it "asks the configured model without one" do
      adapter.call(node, { a: "I am single" })
      expect(bodies.last["model"]).to eq(Inquirex::LLM::Models::JEV_DEFAULT)
    end
  end

  describe Inquirex::LLM::NullAdapter do
    subject(:adapter) { described_class.new }

    let(:response) { nil }

    it "accepts and ignores a model" do
      expect(adapter.call(node, {}, model: "openai/gpt-4o")).to be_a(Inquirex::LLM::Extraction).or be_a(Hash)
    end
  end
end
