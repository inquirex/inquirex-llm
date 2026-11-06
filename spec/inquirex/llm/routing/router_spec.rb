# frozen_string_literal: true

# The routing fixtures (keys, vendors, models, catalogs) vary independently per context.
# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Inquirex::LLM::Routing::Router do
  subject(:router) { described_class.new(config, registry, console: console) }

  let(:keys) { RoutingHelpers::ALL_KEYS }
  let(:vendors) { %i[anthropic openai openrouter] }
  let(:models) { %w[deepseek/deepseek-v4.1-flash anthropic/claude-haiku-5.5 openai/gpt-4.1-mini] }
  let(:settings) { {} }
  let(:config) { routing_config(keys:, vendors:, models:, **settings) }
  let(:registry) do
    Inquirex::LLM::Routing::Registry.new(config,
      catalog: RoutingHelpers::FakeCatalog.new(RoutingHelpers::CATALOGS),
      console: console).ensure!
  end
  let(:step_models) { [] }
  let(:hint) { nil }
  let(:node) do
    Inquirex::LLM::Node.new(id: :facts,
      verb: :extract,
      prompt: "p",
      schema: Inquirex::LLM::Schema.new(name: :string),
      from_steps: [:a],
      model: hint,
      models: step_models)
  end

  context "when the step names no models" do
    it "uses the first model in llm_models_priority" do
      expect(router.route(node)).to have_attributes(model: "deepseek/deepseek-v4.1-flash", provider: :openrouter)
    end
  end

  context "when the step names its own models" do
    let(:step_models) { %w[mistral/nope openai/gpt-4.1-mini anthropic/claude-haiku-5.5] }

    it "uses the first one a usable vendor serves" do
      expect(router.route(node)).to have_attributes(model: "openai/gpt-4.1-mini", provider: :openai, native_id: "gpt-4.1-mini")
    end

    it "caches the choice per step" do
      expect(router.route(node)).to equal(router.route(node))
    end

    it "chooses separately per verb" do
      expect(router.route(node, verb: :summarize)).not_to equal(router.route(node))
    end
  end

  context "when none of the step's models is served" do
    let(:step_models) { %w[mistral/nope] }

    it "falls back to llm_models_priority, with a warning" do
      expect(router.route(node).model).to eq("deepseek/deepseek-v4.1-flash")
      expect(console_io.string).to include('step :facts: no usable vendor serves mistral/nope; falling back')
    end
  end

  context "with an old `model` hint" do
    let(:hint) { :claude_haiku }

    it "treats it as a one-entry list" do
      expect(router.route(node).model).to eq("anthropic/claude-haiku-5.5")
    end

    context "when use_first_available_model is also given" do
      let(:step_models) { %w[openai/gpt-4.1-mini] }

      it "ignores the hint" do
        expect(router.route(node).model).to eq("openai/gpt-4.1-mini")
      end
    end
  end

  context "when dsl_can_reprioritize is false" do
    let(:settings) { { dsl_can_reprioritize: false } }
    let(:step_models) { %w[openai/gpt-4.1-mini deepseek/deepseek-v4.1-flash] }

    it "keeps the step's models, in llm_models_priority's order" do
      expect(router.route(node).model).to eq("deepseek/deepseek-v4.1-flash")
    end
  end

  context "when dsl_can_use_unlisted_models is false" do
    let(:settings) { { dsl_can_use_unlisted_models: false } }
    let(:step_models) { %w[openai/gpt-4o openai/gpt-4.1-mini] }

    it "ignores models llm_models_priority does not list" do
      expect(router.route(node).model).to eq("openai/gpt-4.1-mini")
    end
  end

  context "when no model at all can serve the step" do
    let(:vendors) { %i[typesafe] }
    let(:models) { %w[typesafe/jev-latest] }

    it "raises NoAvailableModelsError naming the step" do
      expect { router.route(node, verb: :summarize) }
        .to raise_error(Inquirex::LLM::Errors::NoAvailableModelsError, /summarize step :facts/)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
