# frozen_string_literal: true

# The routing fixtures (keys, vendors, models, catalogs) vary independently per context.
# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Inquirex::LLM::Routing::Registry do
  subject(:registry) { described_class.new(config, catalog: fake_catalog, console: console).ensure! }

  let(:keys) { RoutingHelpers::ALL_KEYS }
  let(:catalogs) { RoutingHelpers::CATALOGS }
  let(:vendors) { %i[openrouter openai anthropic typesafe] }
  let(:models) { %w[deepseek/deepseek-v4.1-flash anthropic/claude-haiku-5.5 openai/gpt-4.1-mini] }
  let(:config) { routing_config(keys:, vendors:, models:) }
  let(:fake_catalog) { RoutingHelpers::FakeCatalog.new(catalogs) }

  let(:jev_ok) do
    Inquirex::LLM::Node.new(id: :x,
      verb: :extract,
      prompt: "p",
      schema: Inquirex::LLM::Schema.new(filing: { type: :enum, values: %w[single joint] }),
      from_steps: [:a])
  end
  let(:jev_unsupported) do
    Inquirex::LLM::Node.new(id: :y,
      verb: :extract,
      prompt: "p",
      schema: Inquirex::LLM::Schema.new(name: :string),
      from_steps: [:a])
  end

  context "with every key and catalog" do
    its(:vendors) { is_expected.to eq(vendors) }
    its(:models) { is_expected.to eq(models) }

    it "prints nothing" do
      registry
      expect(console_io.string).to be_empty
    end

    it "routes by vendor priority: OpenRouter first, so even OpenAI models go through it" do
      expect(registry.route_for("openai/gpt-4.1-mini"))
        .to have_attributes(provider: :openrouter, native_id: "openai/gpt-4.1-mini", adapter: be_a(Inquirex::LLM::OpenRouterAdapter))
    end
  end

  context "with native vendors ahead of OpenRouter" do
    let(:vendors) { %i[anthropic openai openrouter] }

    it "calls Anthropic natively, by its own id" do
      expect(registry.route_for("anthropic/claude-haiku-5.5"))
        .to have_attributes(model: "anthropic/claude-haiku-5.5",
          provider: :anthropic,
          native_id: "claude-haiku-5-5",
          adapter: be_a(Inquirex::LLM::AnthropicAdapter))
    end

    it "accepts a dated Anthropic snapshot as the model" do
      expect(registry.route_for("anthropic/claude-sonnet-5.5")).to have_attributes(provider: :anthropic)
    end

    it "calls OpenAI natively, without the prefix" do
      expect(registry.route_for("openai/gpt-4.1-mini")).to have_attributes(provider: :openai, native_id: "gpt-4.1-mini")
    end

    it "still reaches vendors that have no adapter through OpenRouter" do
      expect(registry.route_for("deepseek/deepseek-v4.1-flash")).to have_attributes(provider: :openrouter)
    end

    it "falls through to OpenRouter for a model the native catalog lacks" do
      expect(registry.route_for("anthropic/claude-haiku-5.5")).to have_attributes(provider: :anthropic)
      expect(registry.route_for("openai/gpt-6")).to be_nil
    end
  end

  context "when ANTHROPIC_API_KEY and OPENAI_API_KEY are missing" do
    let(:keys) { RoutingHelpers::ALL_KEYS.except("ANTHROPIC_API_KEY", "OPENAI_API_KEY") }
    let(:vendors) { %i[anthropic openai openrouter] }

    its(:vendors) { is_expected.to eq(%i[openrouter]) }

    it "warns for each, then names what is left" do
      registry
      expect(console_io.string).to include("anthropic is in llm_vendors_priority, but ANTHROPIC_API_KEY is not set",
        "openai is in llm_vendors_priority, but OPENAI_API_KEY is not set",
        "LLM vendors in use, by priority: openrouter")
    end

    it "sends the same model name through OpenRouter" do
      expect(registry.route_for("anthropic/claude-haiku-5.5")).to have_attributes(provider: :openrouter)
    end

    it "does not download catalogs it has no key for" do
      registry
      expect(fake_catalog.fetched).to eq(%i[openrouter])
    end
  end

  context "when a catalog cannot be downloaded" do
    let(:catalogs) { RoutingHelpers::CATALOGS.merge(openai: Inquirex::LLM::Errors::AdapterError.new("HTTP 503")) }

    its(:vendors) { is_expected.to eq(%i[openrouter anthropic typesafe]) }

    it "drops that vendor for the life of the process, saying why" do
      registry
      expect(console_io.string).to include("openai's model catalog could not be downloaded (HTTP 503)", "until this process restarts")
    end
  end

  context "when no vendor is usable" do
    let(:keys) { {} }

    it "raises MissingProviderAPIKeysError naming the variables to set" do
      expect { registry }.to raise_error(Inquirex::LLM::Errors::MissingProviderAPIKeysError,
        /OPENROUTER_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY, TYPESAFE_API_KEY/)
    end
  end

  context "when a listed model has no vendor" do
    let(:keys) { RoutingHelpers::ALL_KEYS.except("OPENROUTER_API_KEY") }

    its(:models) { is_expected.to eq(%w[anthropic/claude-haiku-5.5 openai/gpt-4.1-mini]) }

    it "warns and drops it" do
      registry
      expect(console_io.string).to include("deepseek/deepseek-v4.1-flash is in llm_models_priority, but no usable vendor serves it")
    end
  end

  context "when no listed model has a vendor" do
    let(:models) { %w[mistral/mistral-large] }
    let(:vendors) { %i[anthropic] }

    it "raises NoAvailableModelsError" do
      expect { registry }.to raise_error(Inquirex::LLM::Errors::NoAvailableModelsError, %r{none of mistral/mistral-large})
    end
  end

  context "when llm_models_priority is empty" do
    let(:models) { [] }

    it "raises NoAvailableModelsError" do
      expect { registry }.to raise_error(Inquirex::LLM::Errors::NoAvailableModelsError, /llm_models_priority is empty/)
    end
  end

  describe "Jev, through TypeSafe" do
    let(:vendors) { %i[typesafe] }
    let(:models) { %w[typesafe/jev-latest] }

    it "serves an extract whose every field it can answer" do
      expect(registry.route_for("typesafe/jev-latest", verb: :extract, node: jev_ok))
        .to have_attributes(provider: :typesafe, native_id: "jev-latest", adapter: be_a(Inquirex::LLM::JevAdapter))
    end

    it "does not serve a field it cannot answer" do
      expect(registry.route_for("typesafe/jev-latest", verb: :extract, node: jev_unsupported)).to be_nil
    end

    it "does not serve summarize" do
      expect(registry.route_for("typesafe/jev-latest", verb: :summarize)).to be_nil
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
