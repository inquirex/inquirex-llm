# frozen_string_literal: true

RSpec.describe "use_first_available_model" do
  def define(&)
    Inquirex.define id: "routing-test" do
      start :input

      ask :input do
        type :text
        question "Describe your situation."
        transition to: :facts
      end

      extract :facts do
        from :input
        prompt "Extract the facts."
        schema filing_status: :string
        instance_eval(&)
        transition to: :done
      end

      say :done do
        text "Thanks."
      end
    end
  end

  let(:models) { %w[deepseek/deepseek-v4.1-flash anthropic/claude-haiku-5.5] }

  describe "the node" do
    subject(:node) { define { use_first_available_model "deepseek/deepseek-v4.1-flash", "anthropic/claude-haiku-5.5" }.step(:facts) }

    its(:models) { is_expected.to eq(models) }
    its(:models) { is_expected.to be_frozen }

    it "takes one array as well as several names" do
      expect(define { use_first_available_model %w[deepseek/deepseek-v4.1-flash anthropic/claude-haiku-5.5] }.step(:facts).models)
        .to eq(models)
    end

    it "stays off the wire" do
      expect(node.to_h.to_s).not_to include("deepseek")
    end

    it "does not come back from JSON" do
      expect(Inquirex::LLM::Node.from_h(:facts, JSON.parse(JSON.generate(node.to_h))).models).to eq([])
    end
  end

  it "defaults to no models" do
    expect(define { temperature 0.1 }.step(:facts).models).to eq([])
  end

  it "rejects a name that is not vendor/model" do
    expect { define { use_first_available_model "gpt-4o" } }
      .to raise_error(Inquirex::LLM::Errors::DefinitionError, %r{:facts use_first_available_model needs "vendor/model" names.*"gpt-4o"})
  end

  it "warns when `model` is declared too" do
    expect { define { model :claude_sonnet; use_first_available_model "openai/gpt-4o" } }
      .to output(/declares both `model` and `use_first_available_model`; `model :claude_sonnet` is ignored/).to_stderr
  end

  it "is allowed in summarize" do
    definition = Inquirex.define id: "summary-test" do
      start :input
      ask(:input) { type :text; question "Q?"; transition to: :summary }
      summarize(:summary) { use_first_available_model "openai/gpt-4.1-mini" }
    end
    expect(definition.step(:summary).models).to eq(%w[openai/gpt-4.1-mini])
  end

  context "when dsl_can_use_unlisted_models is false" do
    before do
      Inquirex::LLM.configure do |c|
        c.llm_models_priority = %w[openai/gpt-4.1-mini]
        c.dsl_can_use_unlisted_models = false
      end
    end

    it "rejects a model llm_models_priority does not list" do
      expect { define { use_first_available_model "openai/gpt-4.1-mini", "openai/gpt-4o" } }
        .to raise_error(Inquirex::LLM::Errors::DefinitionError, %r{names openai/gpt-4o, which llm_models_priority does not list})
    end

    it "accepts listed models" do
      expect(define { use_first_available_model "openai/gpt-4.1-mini" }.step(:facts).models).to eq(%w[openai/gpt-4.1-mini])
    end
  end

  context "when routing is already settled" do
    around { |example| with_env(RoutingHelpers::ALL_KEYS) { example.run } }

    before do
      Inquirex::LLM.configure do |c|
        c.llm_vendors_priority = %i[openai]
        c.llm_models_priority = %w[openai/gpt-4.1-mini]
      end.ensure_provider_models!(catalog: RoutingHelpers::FakeCatalog.new(RoutingHelpers::CATALOGS), console: console)
    end

    it "warns at load time when no usable vendor serves any of the step's models" do
      expect { define { use_first_available_model "mistral/mistral-large" } }
        .to output(%r{:facts: no usable vendor serves mistral/mistral-large; its calls will fall back}).to_stderr
    end

    it "says nothing when one is served" do
      expect { define { use_first_available_model "openai/gpt-4.1-mini" } }.not_to output.to_stderr
    end
  end

  describe "through SafeSource" do
    let(:source) do
      <<~RUBY
        Inquirex.define id: "safe-routing" do
          start :input
          ask :input do
            type :text
            question "Describe your situation."
            transition to: :facts
          end
          extract :facts do
            from :input
            prompt "Extract the facts."
            schema filing_status: :string
            use_first_available_model "deepseek/deepseek-v4.1-flash", "anthropic/claude-haiku-5.5"
          end
        end
      RUBY
    end

    it "is allowed" do
      expect(Inquirex::SafeSource.validate(source)).to be_empty
    end

    it "loads through load_dsl" do
      expect(Inquirex.load_dsl(source).step(:facts).models).to eq(models)
    end

    it "accepts an array literal" do
      expect(Inquirex::SafeSource.validate(source.sub(/use_first_available_model .*$/, 'use_first_available_model ["openai/gpt-4o"]')))
        .to be_empty
    end

    it "rejects a computed argument" do
      expect(Inquirex::SafeSource.validate(source.sub(/use_first_available_model .*$/, "use_first_available_model ENV.fetch('M')")))
        .not_to be_empty
    end
  end
end
