# frozen_string_literal: true

RSpec.describe ExtractEval::CLI::ModelCommand do
  subject(:command) { described_class.new }

  describe "#best_value" do
    def best(entries) = command.send(:best_value, entries)

    it "picks the cheapest entry within two points of the best accuracy" do
      expect(best([[0.98, 0.0486, 0], [0.969, 0.0037, 0], [0.894, 0.0014, 0]])).to eq(1)
    end

    it "never picks a cheap entry that falls outside the margin" do
      expect(best([[0.98, 0.05, 0], [0.95, 0.001, 0]])).to eq(0)
    end

    it "skips entries with errors or no accuracy" do
      expect(best([[0.99, 0.0, 10], [nil, 0.0, 0], [0.9, 0.01, 0]])).to eq(2)
    end

    it { expect(best([[nil, 0.0, 3]])).to be_nil }
  end
end
