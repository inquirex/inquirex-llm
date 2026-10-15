# frozen_string_literal: true

RSpec.describe ExtractEval::Verifier do
  subject(:problems) { described_class.new(fixture).problems }

  context "with every shipped fixture" do
    it "finds nothing wrong" do
      all = ExtractEval::Fixture.datasets.flat_map { ExtractEval::Fixture.all(dataset: it) }
      expect(all.flat_map { described_class.new(it).problems }).to eq([])
    end
  end

  context "with a broken copy" do
    let(:dir) { Dir.mktmpdir }
    let(:fixture) { ExtractEval::Fixture.new("09_tax-preparation", root: dir) }
    let(:truth) do
      JSON.parse(File.read(ExtractEval::Fixture.new("09_tax-preparation").truth_path)).merge(
        "filing_status" => "widowed", "dependents" => "2", "self_employed" => "yes", "bogus" => 1
      ).except("irs_letter")
    end

    before do
      %w[dsls schema datasets].each do |folder|
        FileUtils.cp_r(File.join(ExtractEval::ROOT, folder), dir)
      end
      File.write(fixture.truth_path, JSON.generate(truth))
      File.write(fixture.text_path, "  ")
    end

    after { FileUtils.remove_entry(dir) }

    it "reports each problem" do
      expect(problems).to contain_exactly(
        /is empty/,
        /missing irs_letter/,
        /unknown fields bogus/,
        /widowed" is not one of/,
        /"2" is not an integer/,
        /"yes" is not a boolean/
      )
    end

    it "notices a schema copy that drifted from its DSL" do
      File.write(fixture.schema_path, File.read(fixture.schema_path).sub("head_of_household", "hoh"))
      expect(problems.first).to include('differs from the DSL')
    end
  end

  context "with a bad multi_enum and a missing file" do
    let(:dir) { Dir.mktmpdir }
    let(:fixture) { ExtractEval::Fixture.new("10_wedding-photography", root: dir) }

    before do
      %w[dsls schema datasets].each do |folder|
        FileUtils.cp_r(File.join(ExtractEval::ROOT, folder), dir)
      end
      truth = JSON.parse(File.read(fixture.truth_path))
      File.write(fixture.truth_path, JSON.generate(truth.merge("add_ons" => %w[drone yacht], "formats" => "both")))
    end

    after { FileUtils.remove_entry(dir) }

    it { is_expected.to eq(["add_ons: yacht not in drone|album|engagement_session|second_shooter|same_day_edit"]) }

    it "turns a missing file into a problem rather than an exception" do
      File.delete(fixture.truth_path)
      expect(problems.first).to start_with("Errno::ENOENT")
    end

    it "flags a multi_enum that is not an array" do
      File.write(fixture.truth_path, JSON.generate(JSON.parse(File.read(ExtractEval::Fixture.new("10_wedding-photography").truth_path)).merge("add_ons" => "drone")))
      expect(problems).to eq(['add_ons: "drone" is not an array'])
    end
  end
end
