# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe Inquirex::LLM do
  it { is_expected.to be_a(Module) }

  describe "::VERSION" do
    subject { described_class::VERSION }

    it { is_expected.not_to be_nil }
    it { is_expected.to match(/\A\d+\.\d+\.\d+\z/) }
  end

  describe "Inquirex.define gains LLM verbs after require" do
    subject(:definition) do
      Inquirex.define id: "test-flow" do
        start :greeting

        ask :greeting do
          type :text
          question "Tell me about yourself."
          transition to: :extracted
        end

        extract :extracted do
          from :greeting
          prompt "Extract key facts."
          schema name: :string, age: :integer
          transition to: :done
        end

        say :done do
          text "Thanks!"
        end
      end
    end

    it { is_expected.to be_a(Inquirex::Definition) }
    its(:id) { is_expected.to eq "test-flow" }
    its(:step_ids) { is_expected.to include(:greeting, :extracted, :done) }

    it "builds LLM nodes via the core entry point" do
      expect(definition.step(:extracted)).to be_a(Inquirex::LLM::Node)
      expect(definition.step(:extracted).verb).to eq :extract
    end

    it "core nodes are unaffected" do
      expect(definition.step(:greeting)).to be_a(Inquirex::Node)
      expect(definition.step(:greeting)).not_to be_a(Inquirex::LLM::Node)
    end
  end

  describe ".configuration" do
    it "is memoized" do
      expect(described_class.configuration).to equal(described_class.configuration)
    end
  end

  describe ".configure" do
    it "yields the configuration and returns it" do
      result = described_class.configure { |c| c.anthropic_model = "claude-opus-5-5" }
      expect(result).to equal(described_class.configuration)
      expect(described_class.configuration.anthropic_model).to eq("claude-opus-5-5")
    end
  end

  describe ".reset_configuration!" do
    it "discards writes and re-reads ENV" do
      described_class.configure { |c| c.max_tokens = 99 }
      with_env("INQUIREX_LLM_MAX_TOKENS" => "300") do
        expect(described_class.configuration.max_tokens).to eq(300)
      end
    end
  end

  describe ".adapter" do
    let(:clean) do
      { "INQUIREX_LLM_ADAPTER" => nil, "ANTHROPIC_API_KEY" => nil, "OPENAI_API_KEY" => nil, "TYPESAFE_API_KEY" => nil,
        "OPENROUTER_API_KEY" => nil }
    end

    {
      {}                                                                                             => Inquirex::LLM::NullAdapter,
      { "INQUIREX_LLM_ADAPTER" => "null", "ANTHROPIC_API_KEY" => "k" }                               => Inquirex::LLM::NullAdapter,
      { "INQUIREX_LLM_ADAPTER" => "anthropic", "ANTHROPIC_API_KEY" => "k", "OPENAI_API_KEY" => "k" } =>
                                                                                                        Inquirex::LLM::AnthropicAdapter,
      { "INQUIREX_LLM_ADAPTER" => "openai", "ANTHROPIC_API_KEY" => "k", "OPENAI_API_KEY" => "k" }    =>
                                                                                                        Inquirex::LLM::OpenAIAdapter,
      { "ANTHROPIC_API_KEY" => "k", "OPENAI_API_KEY" => "k" }                                        => Inquirex::LLM::AnthropicAdapter,
      { "OPENAI_API_KEY" => "k" }                                                                    => Inquirex::LLM::OpenAIAdapter,
      { "TYPESAFE_API_KEY" => "k" }                                                                  => Inquirex::LLM::NullAdapter,
      { "OPENROUTER_API_KEY" => "k" }                                                                => Inquirex::LLM::NullAdapter,
      { "INQUIREX_LLM_ADAPTER" => "openrouter", "OPENROUTER_API_KEY" => "k" }                        =>
                                                                                                        Inquirex::LLM::OpenRouterAdapter,
      { "INQUIREX_LLM_ADAPTER" => "jev", "TYPESAFE_API_KEY" => "k" }                                 =>
                                                                                                        Inquirex::LLM::JevAdapter
    }.each do |vars, adapter_class|
      it "builds #{adapter_class.name.split("::").last} from #{vars.empty? ? "nothing" : vars.keys.join(", ")}" do
        with_env(clean.merge(vars)) do
          expect(described_class.adapter).to be_a(adapter_class)
        end
      end
    end

    it "raises when a forced provider has no key" do
      with_env(clean.merge("INQUIREX_LLM_ADAPTER" => "anthropic")) do
        expect { described_class.adapter }.to raise_error(ArgumentError, /ANTHROPIC_API_KEY/)
      end
    end

    it "follows a configure block" do
      with_env(clean) do
        described_class.configure do |c|
          c.provider = :openai
          c.openai_api_key = "sk-configured"
        end
        expect(described_class.adapter).to be_a(Inquirex::LLM::OpenAIAdapter)
      end
    end
  end
end
