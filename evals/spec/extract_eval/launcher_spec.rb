# frozen_string_literal: true

RSpec.describe ExtractEval::Launcher do
  subject(:status) { described_class.new(argv, StringIO.new, stdout, stderr, kernel).execute! }

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:kernel) { class_double(Kernel, exit: nil) }

  before do
    allow(ExtractEval::Runtime).to receive(:setup!)
    allow(ExtractEval::ModelCatalog).to receive(:verify!)
    allow(ExtractEval::OpenRouterAdapter).to receive(:new) { |**settings| FakeAdapter.new(**settings) }
    allow(ExtractEval::JevAdapter).to receive(:new) { |model:| FakeAdapter.new(model: model) }
  end

  def run_cli
    status
    stdout.string
  end

  context "with no arguments" do
    let(:argv) { [] }

    it("prints help") { expect(run_cli).to include("compare") }
    it("exits 0") { run_cli && expect(kernel).to(have_received(:exit).with(0)) }
  end

  context "with version" do
    let(:argv) { ["version"] }

    it { expect(run_cli).to eq("#{ExtractEval::VERSION}\n") }
  end

  context "with cases" do
    let(:argv) { ["cases"] }

    it { expect(run_cli).to include("10_wedding-photography", "vague", "2/8") }
  end

  context "with run on the vague dataset" do
    let(:argv) { %w[run -m fake/one -d vague -c 09 --local] }

    it { expect(run_cli).to include("vague", "100.0%") }
  end

  context "with run over two datasets" do
    let(:argv) { %w[run -m fake/one -d vague,clear -c 09 --local] }

    it { expect(run_cli).to include("fake/one effort=default [vague]", "fake/one effort=default [clear]") }
  end

  context "with run writing its report to a file" do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, "report.log") }
    let(:argv) { ["run", "-m", "fake/one,fake/two", "-c", "09", "--local", "-o", path] }

    after { FileUtils.remove_entry(dir) }

    it "keeps the breakdowns off the screen" do
      expect(run_cli).not_to include("fake/one effort=default [clear]", "difficulty")
    end

    it "keeps the leaderboard, glossary and scores on the screen" do
      expect(run_cli).to include("restraint", "Description", "braintrust_url")
    end

    it "writes all of it to the file, in color, ending with the time" do
      run_cli
      expect(File.read(path)).to include("difficulty", "Description", "braintrust_url", "\e[1m").and(match(/Closed at .+\n\z/))
    end
  end

  context "with run, scoring every experiment" do
    let(:argv) { %w[run -m fake/one -d vague -c 09 --local] }

    it { expect(run_cli).to match(%r{│ fake/one +│ default │ vague   │ +\d+\.\d% │ +\$0\.\d{4} │ -}) }
  end

  context "with run holding back its warnings" do
    let(:argv) { %w[run -m fake/one -c 09 --local] }
    let(:log) { Dir.mktmpdir }

    before do
      allow(Dry::CLI::UI::Invocation).to receive(:root).and_return(log)
      failing = FakeAdapter.new(model: "fake/one")
      allow(failing).to receive(:extract).and_raise(RuntimeError, "out of credits")
      allow(ExtractEval::OpenRouterAdapter).to receive(:new).and_return(failing)
    end

    after { FileUtils.remove_entry(log) }

    it "prints only how many, and where" do
      run_cli
      expect(stderr.string.delete("│\n ")).to match(/1Warningwasrecordedin.*run\.warnings\.\d{4}-\d\d-\d\d\.\d{6}\.log/)
    end

    it "keeps them off the screen" do
      run_cli
      expect(stderr.string).not_to include("out of credits")
    end

    it "saves them" do
      run_cli
      expect(File.read(Dir[File.join(log, "log", "*.warnings.*")].first)).to include("[fake/one effort=default clear]", "out of credits")
    end
  end

  context "with compare over two datasets" do
    let(:argv) { %w[compare -m fake/a -d clear,vague -c 01 --local] }

    it { expect(run_cli).to include("clear", "vague") }
  end

  context "with compare over an unknown dataset" do
    let(:argv) { %w[compare -n -d nope] }

    it { run_cli && expect(stderr.string).to(include('no dataset "nope"')) }
  end

  context "with verify" do
    let(:argv) { ["verify"] }

    it { expect(run_cli).to include("20 cases verified across clear, vague") }
  end

  context "with verify over a broken fixture" do
    let(:argv) { %w[verify] }

    before { allow(ExtractEval::Verifier).to receive(:new).and_return(instance_double(ExtractEval::Verifier, problems: ["bad"])) }

    it "exits 1" do
      run_cli
      expect(kernel).to have_received(:exit).with(1)
    end

    it { run_cli && expect(stderr.string).to(include("20 case(s) failed verification")) }
  end

  context "with run" do
    let(:argv) { %w[run -m fake/one -c 01,02 -e low -t default --max-tokens 100 --local] }

    it { expect(run_cli).to include("01_bookkeeping-cfo", "02_couples-family-therapy", "fake/one", "100.0%") }

    it "builds the adapter from the flags" do
      run_cli
      expect(ExtractEval::OpenRouterAdapter).to have_received(:new).with(model: "fake/one", effort: "low", temperature: nil, max_tokens: 100)
    end
  end

  context "with run and an unknown case" do
    let(:argv) { %w[run -m fake/one -c 99 --local] }

    it { run_cli && expect(stderr.string).to(include("no cases match 99")) }
  end

  context "with compare over explicit models" do
    let(:argv) { %w[compare -m fake/a,fake/b -c 01 -t 0 --local --concurrency 1] }

    it { expect(run_cli).to include("fake/a", "fake/b") }
  end

  context "with compare explaining its columns" do
    let(:argv) { %w[compare -m fake/a -c 01 --local] }

    it { expect(run_cli).to include("Term", "Description", "restraint", "Of the fields the text never answers") }
  end

  context "with compare totalling two datasets" do
    let(:argv) { %w[compare -m fake/a -d clear,vague -c 01 --local] }

    it "totals tokens and cost per model across them" do
      expect(run_cli).to include("tok_in", "200", "$0.0020")
    end
  end

  context "with run and no model" do
    let(:argv) { %w[run -d vague -c 09 --local --config spec/fixtures/config.yml] }

    it "runs every model in config.yml, each with its breakdown" do
      expect(run_cli).to include("typesafe/jev-router effort=default [vague]", "anthropic/claude-haiku-5.5", "09_tax-preparation")
    end
  end

  context "with run on a native Jev model" do
    let(:argv) { %w[run -m typesafe-api/jev-latest -c 01 --local] }

    it "asks for the key that model needs" do
      run_cli
      expect(ExtractEval::Runtime).to have_received(:setup!).with(braintrust: false, keys: ["TYPESAFE_API_KEY"])
    end
  end

  context "with compare over config.yml" do
    let(:argv) { %w[compare -c 01 --local --config spec/fixtures/config.yml] }

    it("runs every contender") { expect(run_cli).to include("typesafe/jev-router", "typesafe-api/jev-latest", "anthropic/claude-haiku-5.5") }
  end

  context "with compare --dry-run" do
    let(:argv) { %w[compare -n --config spec/fixtures/config.yml] }

    it { expect(run_cli).to include("max_tokens", "openai/gpt-4o-mini") }

    it "calls nothing" do
      run_cli
      expect(ExtractEval::Runtime).not_to have_received(:setup!)
    end
  end

  context "with compare and an empty config" do
    let(:argv) { ["compare", "--config", "/nonexistent/config.yml", "--local"] }

    it { run_cli && expect(stderr.string).to(include("no models")) }
  end

  context "with --verbose and a failure" do
    let(:argv) { %w[run -m fake/one -c 99 --local -v] }

    it { run_cli && expect(stderr.string).to(include("launcher.rb")) }
  end

  context "with completion" do
    let(:argv) { %w[completion zsh] }

    it { expect(run_cli).to include("#compdef extract-eval") }
  end

  context "with a run logged to Braintrust" do
    let(:argv) { %w[run -m fake/one -c 01] }
    let(:summary) do
      ExtractEval::Experiment::Summary.new(
        model:       "fake/one",
        effort:      nil,
        temperature: 0.2,
        dataset:     "clear",
        means:       { "field_accuracy" => 1.0 },
        cases:       [],
        errors:      [],
        duration:    1.0,
        permalink:   "https://example.com/exp",
        tokens:      { input_tokens: 0, output_tokens: 0, cost_usd: 0.0 }
      )
    end
    let(:opened) { true }

    before do
      allow(ExtractEval::Runtime).to receive(:browse).and_return(opened)
      allow(ExtractEval::Experiment).to receive(:new).and_return(
        instance_double(ExtractEval::Experiment, name: "fake", fixtures: [ExtractEval::Fixture.new("01_bookkeeping-cfo")], run: summary)
      )
    end

    it { expect(run_cli).to include("https://example.com/exp") }

    it "opens the experiment" do
      run_cli
      expect(ExtractEval::Runtime).to have_received(:browse).with("https://example.com/exp")
    end

    context "when the browser cannot be opened" do
      let(:opened) { false }

      it { run_cli && expect(stderr.string).to(include("could not open")) }
    end

    context "with --no-open" do
      let(:argv) { %w[run -m fake/one -c 01 --no-open] }

      it "leaves the browser alone" do
        run_cli
        expect(ExtractEval::Runtime).not_to have_received(:browse)
      end
    end
  end
end
