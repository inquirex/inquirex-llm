# frozen_string_literal: true

RSpec.describe Inquirex::LLM::Routing::ModelId do
  describe ".valid?" do
    it "accepts OpenRouter-style names" do
      expect(%w[openai/gpt-4.1-mini anthropic/claude-haiku-5.5 deepseek/deepseek-v4.1-flash-1017].map { described_class.valid?(it) }).to all(be(true))
    end

    it "accepts a symbol" do
      expect(described_class.valid?(:'openai/gpt-4o')).to be(true)
    end

    it "rejects a bare model, a blank model, spaces and a capitalised vendor" do
      expect(["gpt-4o", "openai/", "openai/gpt 4", "OpenAI/gpt-4o", :claude_sonnet].map { described_class.valid?(it) }).to all(be(false))
    end
  end

  describe ".parse" do
    subject(:id) { described_class.parse("anthropic/claude-haiku-5.5") }

    its(:vendor) { is_expected.to eq(:anthropic) }
    its(:name) { is_expected.to eq("claude-haiku-5.5") }
    its(:to_s) { is_expected.to eq("anthropic/claude-haiku-5.5") }
    its(:native_provider) { is_expected.to eq(:anthropic) }
    its(:native_id) { is_expected.to eq("claude-haiku-5-5") }

    it "keeps everything after the first slash as the model" do
      expect(described_class.parse("meta-llama/llama-3.3-70b-instruct:free").name).to eq("llama-3.3-70b-instruct:free")
    end

    it "raises on a name that is not vendor/model" do
      expect { described_class.parse("gpt-4o") }.to raise_error(ArgumentError, %r{vendor/model})
    end
  end

  describe "#native_id and #native_provider" do
    it "strips only the prefix for OpenAI" do
      expect(described_class.parse("openai/gpt-4.1-mini")).to have_attributes(native_provider: :openai, native_id: "gpt-4.1-mini")
    end

    it "strips only the prefix for TypeSafe" do
      expect(described_class.parse("typesafe/jev-latest")).to have_attributes(native_provider: :typesafe, native_id: "jev-latest")
    end

    it "has no native provider for a vendor reached only through OpenRouter" do
      expect(described_class.parse("deepseek/deepseek-v4.1-flash").native_provider).to be_nil
    end
  end

  describe ".from_hint" do
    it "maps an old DSL symbol through the OpenRouter aliases" do
      expect(described_class.from_hint(:claude_sonnet)).to eq("anthropic/claude-sonnet-5.5")
    end

    it "passes a vendor/model hint through" do
      expect(described_class.from_hint("google/gemini-2.5-flash")).to eq("google/gemini-2.5-flash")
    end

    it "returns nil for nothing, or for a symbol with no alias" do
      expect([described_class.from_hint(nil), described_class.from_hint(:mystery)]).to all(be_nil)
    end
  end
end
