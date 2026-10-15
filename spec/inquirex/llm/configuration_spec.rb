# frozen_string_literal: true

RSpec.describe Inquirex::LLM::Configuration do
  subject(:config) { described_class.new(env) }

  let(:env) { {} }

  describe "defaults" do
    it "auto-detects the provider" do
      expect(config.provider).to be_nil
    end

    it "has no credentials" do
      expect([config.anthropic_api_key, config.openai_api_key, config.typesafe_api_key]).to all(be_nil)
    end

    it "takes the models from the catalogue" do
      expect(config.anthropic_model).to eq(Inquirex::LLM::Models::ANTHROPIC_DEFAULT)
      expect(config.openai_model).to eq(Inquirex::LLM::Models::OPENAI_DEFAULT)
      expect(config.jev_model).to eq(Inquirex::LLM::Models::JEV_DEFAULT)
    end

    it "keeps today's generation limits" do
      expect(config).to have_attributes(
        max_tokens:          described_class::DEFAULT_MAX_TOKENS,
        temperature:         described_class::DEFAULT_TEMPERATURE,
        summary_max_tokens:  described_class::DEFAULT_SUMMARY_MAX_TOKENS,
        summary_temperature: described_class::DEFAULT_SUMMARY_TEMPERATURE,
        debug:               false
      )
    end
  end

  describe "reading ENV" do
    # variable => [raw value, attribute, expected value]
    def self.cases
      {
        "INQUIREX_LLM_ADAPTER"             => ["OpenAI", :provider, :openai],
        "ANTHROPIC_API_KEY"                => ["sk-ant", :anthropic_api_key, "sk-ant"],
        "OPENAI_API_KEY"                   => ["sk-oai", :openai_api_key, "sk-oai"],
        "OPENROUTER_API_KEY"               => ["sk-or", :openrouter_api_key, "sk-or"],
        "TYPESAFE_API_KEY"                 => ["ts-key", :typesafe_api_key, "ts-key"],
        "INQUIREX_LLM_ANTHROPIC_MODEL"     => ["claude-opus-5-5", :anthropic_model, "claude-opus-5-5"],
        "INQUIREX_LLM_OPENAI_MODEL"        => ["gpt-4.1", :openai_model, "gpt-4.1"],
        "INQUIREX_LLM_OPENROUTER_MODEL"    => ["google/gemini-2.5-flash", :openrouter_model, "google/gemini-2.5-flash"],
        "INQUIREX_LLM_JEV_MODEL"           => ["jev-2.0.0", :jev_model, "jev-2.0.0"],
        "INQUIREX_LLM_MAX_TOKENS"          => [" 1024 ", :max_tokens, 1024],
        "INQUIREX_LLM_TEMPERATURE"         => ["0.7", :temperature, 0.7],
        "INQUIREX_LLM_SUMMARY_MAX_TOKENS"  => ["8192", :summary_max_tokens, 8192],
        "INQUIREX_LLM_SUMMARY_TEMPERATURE" => ["1", :summary_temperature, 1.0],
        "INQUIREX_DEBUG"                   => ["1", :debug, true]
      }
    end

    cases.each do |var, (raw, attribute, expected)|
      it "reads #{attribute} from #{var}" do
        expect(described_class.new(var => raw).public_send(attribute)).to eq(expected)
      end
    end

    it "covers every setting, each under its own variable" do
      expect(self.class.cases.to_h { |var, (_, attribute, _)| [attribute, var] })
        .to eq(described_class::SETTINGS.transform_values(&:env))
    end

    it "treats a blank variable as unset" do
      config = described_class.new("ANTHROPIC_API_KEY" => "  ", "INQUIREX_LLM_ADAPTER" => "", "INQUIREX_DEBUG" => "")
      expect(config).to have_attributes(anthropic_api_key: nil, provider: nil, debug: false)
    end

    it "reads the real ENV by default" do
      with_env("INQUIREX_LLM_ANTHROPIC_MODEL" => "claude-haiku-5-5") do
        expect(described_class.new.anthropic_model).to eq("claude-haiku-5-5")
      end
    end
  end

  describe "invalid ENV values" do
    {
      "INQUIREX_LLM_ADAPTER"             => "gemini",
      "INQUIREX_LLM_MAX_TOKENS"          => "lots",
      "INQUIREX_LLM_SUMMARY_MAX_TOKENS"  => "0",
      "INQUIREX_LLM_TEMPERATURE"         => "warm",
      "INQUIREX_LLM_SUMMARY_TEMPERATURE" => "2.5"
    }.each do |var, raw|
      it "raises a ConfigurationError naming #{var} for #{raw.inspect}" do
        expect { described_class.new(var => raw) }
          .to raise_error(Inquirex::LLM::Errors::ConfigurationError, /\A#{var} must be .*"#{Regexp.escape(raw)}"/)
      end
    end

    it "lists the accepted providers" do
      expect { described_class.new("INQUIREX_LLM_ADAPTER" => "gemini") }
        .to raise_error(/one of anthropic, openai, openrouter, jev, null/)
    end
  end

  describe "writers" do
    it "coerce and validate like ENV, naming the writer" do
      config.provider = "anthropic"
      config.max_tokens = "512"
      expect(config).to have_attributes(provider: :anthropic, max_tokens: 512)
      expect { config.max_tokens = -1 }
        .to raise_error(Inquirex::LLM::Errors::ConfigurationError, /Inquirex::LLM.configuration.max_tokens/)
      expect { config.temperature = Object.new }.to raise_error(Inquirex::LLM::Errors::ConfigurationError)
    end

    it "restore the default when given nil" do
      config.anthropic_model = "claude-opus-5-5"
      config.anthropic_model = nil
      expect(config.anthropic_model).to eq(Inquirex::LLM::Models::ANTHROPIC_DEFAULT)
    end

    it "set debug from a boolean" do
      config.debug = true
      expect(config.debug?).to be(true)
      config.debug = false
      expect(config.debug?).to be(false)
    end
  end

  describe "credentials in output" do
    let(:env) {
      { "ANTHROPIC_API_KEY" => "sk-ant-secret", "OPENAI_API_KEY" => "sk-oai-secret",
                  "OPENROUTER_API_KEY" => "sk-or-secret", "TYPESAFE_API_KEY" => "ts-secret" }
    }

    it "are redacted by #to_h" do
      expect(config.to_h).to include(
        anthropic_api_key:  described_class::REDACTED,
        openai_api_key:     described_class::REDACTED,
        openrouter_api_key: described_class::REDACTED,
        typesafe_api_key:   described_class::REDACTED
      )
    end

    it "never appear in #inspect or #to_s" do
      [config.inspect, config.to_s].each do |text|
        expect(text).not_to include('secret')
        expect(text).to include("anthropic_model=")
      end
    end

    it "show as nil when unset" do
      expect(described_class.new({}).to_h[:anthropic_api_key]).to be_nil
    end
  end
end
