# frozen_string_literal: true

RSpec.describe Inquirex::LLM::Numbers do
  {
    "about 150 transactions across 3 accounts" => [150, 3],
    "a hundred and forty people, give or take" => [140],
    "forty-five staff and two servers"         => [45, 2],
    "1,200 square feet, twenty-two rooms"      => [1200, 22],
    "two dogs and three cats"                  => [2, 3],
    "two thousand and five"                    => [2005],
    "one hundred twenty"                       => [120],
    "a dozen eggs, then another dozen"         => [12],
    "a few months"                             => [],
    "version 2.5 of 3"                         => [3]
  }.each do |text, expected|
    it "finds #{expected.inspect} in #{text.inspect}" do
      expect(described_class.find(text)).to eq(expected)
    end
  end
end
