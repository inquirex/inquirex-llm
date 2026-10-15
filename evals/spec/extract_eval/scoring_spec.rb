# frozen_string_literal: true

RSpec.describe ExtractEval::Scoring do
  describe ".field_score" do
    it { expect(described_class.field_score(:enum, "gut", "gut")).to eq(1.0) }
    it { expect(described_class.field_score(:enum, "gut", "refresh")).to eq(0.0) }
    it { expect(described_class.field_score(:enum, "gut", nil)).to eq(0.0) }
    it { expect(described_class.field_score(:boolean, false, false)).to eq(1.0) }
    it { expect(described_class.field_score(:boolean, false, nil)).to eq(0.0) }
    it { expect(described_class.field_score(:boolean, true, "true")).to eq(0.0) }
    it { expect(described_class.field_score(:integer, 3, 3)).to eq(1.0) }
    it { expect(described_class.field_score(:integer, 3, 3.0)).to eq(1.0) }
    it { expect(described_class.field_score(:integer, 3, 3.5)).to eq(0.0) }
    it { expect(described_class.field_score(:integer, 3, " 3 ")).to eq(1.0) }
    it { expect(described_class.field_score(:integer, 3, "three")).to eq(0.0) }
    it { expect(described_class.field_score(:integer, 3, nil)).to eq(0.0) }
    it { expect(described_class.field_score(:multi_enum, %w[a b c], %w[a b])).to be_within(0.001).of(2.0 / 3) }
    it { expect(described_class.field_score(:multi_enum, [], [])).to eq(1.0) }
    it { expect(described_class.field_score(:multi_enum, %w[a], "a")).to eq(0.0) }
  end

  describe ".field_scores" do
    subject(:scores) { described_class.field_scores(schema, { "a" => "x", "n" => 2 }, { a: "x", n: 5 }) }

    let(:schema) { Inquirex::LLM::Schema.new(a: { type: :enum, values: %w[x y] }, n: :integer) }

    it { is_expected.to eq("a" => 1.0, "n" => 0.0) }
  end

  describe ".stringify" do
    it { expect(described_class.stringify(nil)).to eq({}) }
    it { expect(described_class.stringify(a: 1)).to eq("a" => 1) }
  end

  describe "a field the text never answered" do
    it { expect(described_class.field_score(:integer, nil, nil)).to eq(1.0) }
    it { expect(described_class.field_score(:enum, nil, "")).to eq(1.0) }
    it { expect(described_class.field_score(:multi_enum, nil, [])).to eq(1.0) }
    it { expect(described_class.field_score(:integer, nil, 0)).to eq(0.0) }
    it { expect(described_class.field_score(:boolean, nil, false)).to eq(0.0) }
    it { expect(described_class.field_score(:enum, nil, "unsure")).to eq(0.0) }
    it { expect(described_class.field_score(:multi_enum, nil, ["none"])).to eq(0.0) }
  end

  describe ".restraint" do
    let(:schema) { Inquirex::LLM::Schema.new(a: :integer, b: :boolean, c: :integer) }

    it "is the share of unanswered fields left unset" do
      expect(described_class.restraint(schema, { "a" => nil, "b" => nil, "c" => 3 }, { a: nil, b: false, c: 3 })).to eq(0.5)
    end

    it "is nil when the truth answers every field" do
      expect(described_class.restraint(schema, { "a" => 1, "b" => true, "c" => 3 }, {})).to be_nil
    end
  end
end
