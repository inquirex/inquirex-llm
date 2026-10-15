# frozen_string_literal: true

RSpec.describe ExtractEval::Experiment do
  subject(:experiment) do
    described_class.new(adapter: adapter, fixtures: ExtractEval::Fixture.all(only: %w[01 03 09]), project: nil, parallelism: 2)
  end

  let(:adapter) { FakeAdapter.new(junk: ["09_tax-preparation"], wrong: { "03_home-remodeling" => { "rooms" => ["kitchen"] } }) }

  its(:name) { is_expected.to eq("fake/model effort=default t=0.2 [clear]") }
  its(:dataset) { is_expected.to eq("clear") }
  its("cases.size") { is_expected.to eq(3) }
  its("cases.first") { is_expected.to include(expected: ExtractEval::Fixture.new("01_bookkeeping-cfo").truth) }

  describe "#run" do
    subject(:summary) { experiment.run(on_case: -> { ticks << 1 }) }

    let!(:ticks) { [] }

    its(:model) { is_expected.to eq("fake/model") }
    its(:errors) { is_expected.to eq([]) }
    it { expect(summary.means["exact_match"]).to be_within(0.001).of(1.0 / 3) }
    it { expect(summary.means["valid_json"]).to be_within(0.001).of(2.0 / 3) }

    it "gives partial credit on a multi_enum" do
      expect(summary.cases.find { it.fixture.name == "03_home-remodeling" }.wrong).to eq(
        "rooms" => { "expected" => %w[kitchen bath], "actual" => ["kitchen"] }
      )
    end

    it "scores a junk reply as zero rather than failing the case" do
      expect(summary.cases.find { it.fixture.name == "09_tax-preparation" }.score).to eq(0.0)
    end

    it "reports each finished case" do
      summary
      expect(ticks.size).to eq(3)
    end
  end

  context "with explicit settings" do
    let(:adapter) { FakeAdapter.new(effort: "high", temperature: nil) }

    its(:name) { is_expected.to eq("fake/model effort=high t=default [clear]") }
  end

  context "with the vague dataset" do
    subject(:summary) { experiment.run }

    let(:experiment) do
      described_class.new(adapter: adapter, fixtures: ExtractEval::Fixture.all(dataset: "vague", only: %w[09]), project: nil)
    end
    let(:adapter) { FakeAdapter.new(wrong: { "09_tax-preparation" => { "dependents" => 0, "multi_state" => false } }) }

    its(:dataset) { is_expected.to eq("vague") }

    it "counts a 0 or false for an unanswered field against restraint" do
      expect(summary.means["restraint"]).to eq(4.0 / 6)
    end
  end

  context "with the clear dataset" do
    subject(:summary) { experiment.run }

    let(:adapter) { FakeAdapter.new }

    it("records no restraint score") { expect(summary.means["restraint"]).to be_nil }
  end
end
