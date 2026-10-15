# frozen_string_literal: true

require "inquirex/llm/evals"
require "dotenv"
require "net/http"
require "stringio"

# The suite end to end, through agent-evals' own executable path: the
# config-only evals/.agent-eval.config.yml found from the repository root,
# the gem's Adapter and Scorer named in it, and a fake provider standing in
# for OpenRouter. Nothing here reaches the network.
RSpec.describe "the extraction eval suite" do
  let(:root) { File.expand_path("../../../..", __dir__) }
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:kernel) { Class.new { attr_reader :status; def exit(status) = @status = status }.new }

  def launch(*argv)
    Dir.chdir(root) { Agent::Evals::Launcher.new(argv, $stdin, out, err, kernel).execute! }
    kernel.status
  end

  before do
    # The suite's own config, instead of whatever a previous example resolved.
    Agent::Evals.reset!
    Agent::Evals.configuration.suite("inquirex-llm-extract", root: File.join(root, "evals"))
    # Any HTTP from here would be a real call; make it fail loudly instead.
    allow(Net::HTTP).to receive(:new).and_raise("the suite must not reach the network")
  end

  it "resolves the adapter and the scorer from the config file alone" do
    expect(Agent::Evals::Helper.locate(from: root).config).to eq(File.join(root, "evals", ".agent-eval.config.yml"))
    configuration = Agent::Evals.configuration.require_suite!
    expect(configuration.adapter).to be_a(Inquirex::LLM::Evals::Adapter)
    expect(configuration.scorer).to be_a(Inquirex::LLM::Evals::Scorer)
  end

  it "lists the 20 cases" do
    expect(launch("cases")).to eq(0), err.string
    rows = out.string.lines.grep(/complete|vague/)
    expect(rows.size).to eq(20)
    expect(out.string).to include("05-managed-it-services", "answered 10/10", "answered 5/10")
    expect(err.string).to be_empty
  end

  it "verifies every case" do
    expect(launch("verify")).to eq(0), err.string
    expect(out.string).to include("20 cases verified")
  end

  it "prints the matrix for a dry run and calls nothing" do
    expect(launch("run", "--local", "-n", "-m", "openai/gpt-4o-mini")).to eq(0), err.string
    expect(out.string.scan("openai/gpt-4o-mini").size).to eq(10)
    expect(out.string).to include("8192", "0.1")
  end

  describe "a local run" do
    let(:provider) do
      cases = Agent::Evals.configuration.discovery.all
      Agent::Evals::Testing::FakeProvider.new(answers: lambda { |user|
        kase = cases.find { user.include?(it.input.inspect) }
        kase.id == "vague" ? JSON.generate(kase.expected.merge("growth_planned" => false)) : JSON.generate(kase.expected)
      })
    end

    before do
      Agent::Evals.configuration.provider(provider)
      allow(Dotenv).to receive(:load) # the owner's .env is not this spec's business
    end

    it "runs one dataset through the fake model and scores it" do
      expect(launch("run", "--local", "--no-open", "-m", "fake/echo", "-d", "05-managed-it-services")).to eq(0), err.string
      expect(provider.calls.size).to eq(2)
      expect(out.string).to include("100.0%") # the complete case, answered perfectly
      expect(out.string).to include("growth_planned") # the vague case: an answer where the text is silent
      expect(out.string).to include("hallucinated_rate")
    end
  end
end
