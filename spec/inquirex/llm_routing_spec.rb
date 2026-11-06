# frozen_string_literal: true

RSpec.describe Inquirex::LLM do
  let(:fake_catalog) { RoutingHelpers::FakeCatalog.new(RoutingHelpers::CATALOGS) }
  let(:node) do
    Inquirex::LLM::Node.new(id: :facts,
      verb: :extract,
      prompt: "p",
      schema: Inquirex::LLM::Schema.new(name: :string),
      from_steps: [:a],
      models: %w[openai/gpt-4.1-mini])
  end
  let(:summary) { Inquirex::LLM::Node.new(id: :summary, verb: :summarize, prompt: "s") }

  describe "configuration attributes" do
    subject(:config) { Inquirex::LLM::Configuration.new({}) }

    its(:llm_vendors_priority) { is_expected.to be_nil }
    its(:llm_models_priority) { is_expected.to eq([]) }
    its(:dsl_can_reprioritize) { is_expected.to be(true) }
    its(:dsl_can_use_unlisted_models) { is_expected.to be(true) }
    its(:routing?) { is_expected.to be(false) }

    it "normalises vendors" do
      config.llm_vendors_priority = ["OpenRouter", :anthropic, :anthropic]
      expect(config.llm_vendors_priority).to eq(%i[openrouter anthropic])
    end

    it "turns routing back off with nil" do
      config.llm_vendors_priority = %i[openai]
      config.llm_vendors_priority = nil
      expect(config.routing?).to be(false)
    end

    it "rejects an unknown vendor" do
      expect { config.llm_vendors_priority = %i[gemini] }.to raise_error(Inquirex::LLM::Errors::ConfigurationError, /gemini/)
    end

    it "rejects a model that is not vendor/model" do
      expect { config.llm_models_priority = %w[gpt-4o] }.to raise_error(Inquirex::LLM::Errors::ConfigurationError, /gpt-4o/)
    end

    it "refuses ensure_provider_models! without vendors" do
      expect { config.ensure_provider_models! }.to raise_error(Inquirex::LLM::Errors::ConfigurationError, /llm_vendors_priority/)
    end
  end

  describe ".ensure_provider_models!" do
    it "chains off configure and returns the configuration" do
      with_env(RoutingHelpers::ALL_KEYS) do
        result = described_class.configure do |c|
          c.llm_vendors_priority = %i[openrouter]
          c.llm_models_priority = %w[deepseek/deepseek-v4.1-flash]
        end.ensure_provider_models!(catalog: fake_catalog, console: console)
        expect(result).to equal(described_class.configuration)
        expect(result.routing_ready?).to be(true)
      end
    end

    it "downloads the catalogs only once" do
      with_env(RoutingHelpers::ALL_KEYS) do
        described_class.configure { it.llm_vendors_priority = %i[openrouter] }
        described_class.configuration.llm_models_priority = %w[deepseek/deepseek-v4.1-flash]
        2.times { described_class.ensure_provider_models!(catalog: fake_catalog, console: console) }
        expect(fake_catalog.fetched).to eq(%i[openrouter])
      end
    end
  end

  describe ".route, .extract and .summarize" do
    context "with routing on" do
      let(:openai) { instance_double(Inquirex::LLM::OpenAIAdapter) }

      around { |example| with_env(RoutingHelpers::ALL_KEYS) { example.run } }

      before do
        allow(Inquirex::LLM::OpenAIAdapter).to receive(:new).and_return(openai)
        described_class.configure do |c|
          c.llm_vendors_priority = %i[openai]
          c.llm_models_priority = %w[openai/gpt-4.1-mini]
        end.ensure_provider_models!(catalog: fake_catalog, console: console)
      end

      it "routes a step to its model" do
        expect(described_class.route(node)).to have_attributes(provider: :openai, native_id: "gpt-4.1-mini")
      end

      it "extracts with the routed model" do
        allow(openai).to receive(:call).and_return({ name: "Alan Turing" })
        described_class.extract(node, { a: "x" })
        expect(openai).to have_received(:call).with(node, { a: "x" }, model: "gpt-4.1-mini")
      end

      it "summarizes with the routed model" do
        allow(openai).to receive(:summarize).and_return("recap")
        expect(described_class.summarize(summary, "transcript")).to eq("recap")
        expect(openai).to have_received(:summarize).with(summary, "transcript", {}, model: "gpt-4.1-mini")
      end
    end

    context "with routing off" do
      around { |example| with_env("ANTHROPIC_API_KEY" => nil, "OPENAI_API_KEY" => nil, "INQUIREX_LLM_ADAPTER" => nil) { example.run } }

      it "routes through the legacy adapter, with no model override" do
        expect(described_class.route(node)).to have_attributes(model: nil, native_id: nil, adapter: be_a(Inquirex::LLM::NullAdapter))
      end

      it "extracts and summarizes through it" do
        expect(described_class.extract(node, {})).to be_a(Inquirex::LLM::Extraction).or be_a(Hash)
        expect(described_class.summarize(summary, "Q: a\nA: b")).to be_a(String)
      end
    end
  end
end
