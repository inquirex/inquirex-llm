# frozen_string_literal: true

RSpec.describe ExtractEval::Fixture do
  subject(:fixture) { described_class.new("03_home-remodeling") }

  its(:difficulty) { is_expected.to eq(3) }
  its(:source_step) { is_expected.to eq(:situation) }
  its(:text) { is_expected.to start_with("We want to redo our kitchen") }
  its(:truth) { is_expected.to include("scope" => "gut") }
  its(:schema) { is_expected.to eq(fixture.node.schema) }

  its(:dataset) { is_expected.to eq("clear") }
  its(:text_path) { is_expected.to end_with("datasets/clear/extracted-answers/03_home-remodeling.txt") }

  context "with the vague dataset" do
    subject(:fixture) { described_class.new("03_home-remodeling", dataset: "vague") }

    its(:text) { is_expected.to start_with("Thinking about finally doing something") }
    its(:truth) { is_expected.to include("finish_level" => nil) }
  end

  describe ".datasets" do
    it { expect(described_class.datasets).to eq(%w[clear vague]) }
  end

  describe ".all" do
    it { expect { described_class.all(dataset: "nope") }.to raise_error(ExtractEval::Error, /no dataset "nope"/) }
    it { expect(described_class.all(dataset: "vague").map(&:dataset).uniq).to eq(["vague"]) }
    it { expect(described_class.all.map(&:difficulty)).to eq((1..10).to_a) }
    it { expect(described_class.all(only: %w[09 10]).map(&:name)).to eq(%w[09_tax-preparation 10_wedding-photography]) }
  end

  context "when a flow has no extract step" do
    subject(:fixture) { described_class.new("plain", root: dir) }

    let(:dir) { Dir.mktmpdir }

    before do
      FileUtils.mkdir_p(File.join(dir, "dsls"))
      FileUtils.mkdir_p(File.join(dir, "datasets", "clear"))
      File.write(File.join(dir, "dsls", "plain.rb"), %(Inquirex.define { start :a\n say(:a) { text "hi" } }))
    end

    after { FileUtils.remove_entry(dir) }

    it { expect { fixture.node }.to raise_error(ExtractEval::Error, /found 0/) }
  end
end
