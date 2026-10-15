# frozen_string_literal: true

RSpec.describe ExtractEval::Runtime do
  let(:dir) { Dir.mktmpdir }
  let(:env_file) { File.join(dir, ".env") }

  after do
    FileUtils.remove_entry(dir)
    %w[EXTRACT_EVAL_A EXTRACT_EVAL_B EXTRACT_EVAL_C].each { ENV.delete(it) }
  end

  describe ".load_env" do
    before do
      stub_const("#{described_class}::ENV_FILES", [env_file, File.join(dir, "missing")])
      ENV["EXTRACT_EVAL_B"] = "from-shell"
      File.write(env_file, "# comment\n\nEXTRACT_EVAL_A=\"quoted\"\nEXTRACT_EVAL_B=from-file\n")
      described_class.load_env
    end

    it { expect(ENV.fetch("EXTRACT_EVAL_A")).to eq("quoted") }
    it { expect(ENV.fetch("EXTRACT_EVAL_B")).to eq("from-shell") }
  end

  describe ".require_env!" do
    before { stub_const("#{described_class}::ENV_FILES", [env_file]) }

    it "passes when every variable is set" do
      ENV["EXTRACT_EVAL_A"] = "set"
      expect { described_class.require_env!(%w[EXTRACT_EVAL_A]) }.not_to raise_error
    end

    it "names the missing variables, and says there is no .env" do
      expect { described_class.require_env!(%w[EXTRACT_EVAL_A EXTRACT_EVAL_B]) }
        .to raise_error(ExtractEval::Error, /missing EXTRACT_EVAL_A, EXTRACT_EVAL_B: .*there is no #{Regexp.escape(env_file)}/)
    end

    it "says so when .env exists but lacks them" do
      File.write(env_file, "OTHER=1\n")
      expect { described_class.require_env!(%w[EXTRACT_EVAL_C]) }.to raise_error(ExtractEval::Error, /checked the environment, then #{Regexp.escape(env_file)}/)
    end
  end

  describe ".setup!" do
    before { stub_const("#{described_class}::ENV_FILES", []) }

    it "configures RubyLLM for OpenRouter" do
      described_class.setup!(braintrust: false)
      expect(RubyLLM.config.openrouter_app_name).to eq("inquirex-llm extract evals")
    end

    it "refuses to start without the adapters' keys" do
      expect { described_class.setup!(braintrust: false, keys: %w[EXTRACT_EVAL_C]) }
        .to raise_error(ExtractEval::Error, /missing EXTRACT_EVAL_C/)
    end

    it "refuses to log to Braintrust without a key" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("BRAINTRUST_API_KEY").and_return(nil)
      expect { described_class.setup!(braintrust: true) }.to raise_error(ExtractEval::Error, /BRAINTRUST_API_KEY/)
    end

    it "logs in and instruments RubyLLM when it has a key" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("BRAINTRUST_API_KEY").and_return("k")
      allow(Braintrust).to receive(:init)
      allow(Braintrust).to receive(:instrument!)
      described_class.setup!(braintrust: true)
      expect(Braintrust).to have_received(:instrument!).with(:ruby_llm)
    end
  end

  describe ".browse" do
    before { allow(described_class).to receive(:system).and_return(nil) }

    it { expect(described_class.browse("https://example.com")).to be(false) }

    it "hands the URL to the platform opener" do
      described_class.browse("https://example.com")
      expect(described_class).to have_received(:system).with(a_string_matching(/open/), "https://example.com", out: File::NULL, err: File::NULL)
    end
  end
end
