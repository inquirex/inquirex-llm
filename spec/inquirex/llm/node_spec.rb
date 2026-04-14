# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe Inquirex::LLM::Node do
  subject(:node) do
    described_class.new(
      id:          :extract_biz,
      verb:        :clarify,
      prompt:      "Extract business info from the description.",
      schema:      schema,
      from_steps:  [:description],
      model:       :claude_sonnet,
      temperature: 0.2,
      max_tokens:  1024,
      transitions: [Inquirex::Transition.new(target: :next_step)]
    )
  end

  let(:schema) { Inquirex::LLM::Schema.new(industry: :string, count: :integer) }

  describe "attributes" do
    its(:id) { is_expected.to eq :extract_biz }
    its(:verb) { is_expected.to eq :clarify }
    its(:prompt) { is_expected.to eq "Extract business info from the description." }
    its(:schema) { is_expected.to eq schema }
    its(:from_steps) { is_expected.to eq [:description] }
    its(:from_all) { is_expected.to be false }
    its(:model) { is_expected.to eq :claude_sonnet }
    its(:temperature) { is_expected.to eq 0.2 }
    its(:max_tokens) { is_expected.to eq 1024 }
    its(:fallback) { is_expected.to be_nil }
  end

  describe "#collecting?" do
    subject { node.collecting? }

    it { is_expected.to be true }
  end

  describe "#display?" do
    subject { node.display? }

    it { is_expected.to be false }
  end

  describe "#llm_verb?" do
    subject { node.llm_verb? }

    it { is_expected.to be true }
  end

  describe "#to_h" do
    subject(:hash) { node.to_h }

    it { is_expected.to include("verb" => "clarify") }
    it { is_expected.to include("requires_server" => true) }

    it "serializes LLM metadata under 'llm' key" do
      expect(hash["llm"]).to include(
        "prompt"      => "Extract business info from the description.",
        "from_steps"  => ["description"],
        "model"       => "claude_sonnet",
        "temperature" => 0.2,
        "max_tokens"  => 1024
      )
    end

    it "serializes schema" do
      expect(hash["llm"]["schema"]).to eq("industry" => "string", "count" => "integer")
    end

    it "serializes transitions" do
      expect(hash["transitions"]).to be_a(Array)
      expect(hash["transitions"].first["to"]).to eq("next_step")
    end

    it "strips fallback procs" do
      node_with_fallback = described_class.new(
        id:         :fb,
        verb:       :clarify,
        prompt:     "test",
        schema:     schema,
        from_steps: [:x],
        fallback:   -> { "fallback" }
      )
      expect(node_with_fallback.to_h["llm"]).not_to have_key("fallback")
    end
  end

  describe ".from_h" do
    subject(:restored) { described_class.from_h(:extract_biz, node.to_h) }

    its(:id) { is_expected.to eq :extract_biz }
    its(:verb) { is_expected.to eq :clarify }
    its(:prompt) { is_expected.to eq "Extract business info from the description." }
    its(:schema) { is_expected.to eq schema }
    its(:from_steps) { is_expected.to eq [:description] }
    its(:model) { is_expected.to eq :claude_sonnet }
    its(:temperature) { is_expected.to eq 0.2 }
    its(:max_tokens) { is_expected.to eq 1024 }

    it "round-trips transitions" do
      expect(restored.transitions.size).to eq 1
      expect(restored.transitions.first.target).to eq :next_step
    end
  end

  describe "from_all node" do
    subject(:node_all) do
      described_class.new(
        id:       :summary,
        verb:     :summarize,
        prompt:   "Summarize everything.",
        from_all: true
      )
    end

    its(:from_all) { is_expected.to be true }
    its(:from_steps) { is_expected.to be_empty }

    it "serializes from_all" do
      expect(node_all.to_h["llm"]["from_all"]).to be true
    end
  end

  describe ".llm_verb?" do
    it "recognizes all four LLM verbs" do
      %i[clarify describe summarize detour].each do |verb|
        expect(described_class.llm_verb?(verb)).to be true
      end
    end

    it "rejects core verbs" do
      %i[ask say header confirm].each do |verb|
        expect(described_class.llm_verb?(verb)).to be false
      end
    end
  end

  describe "immutability" do
    it { is_expected.to be_frozen }

    it "freezes from_steps" do
      expect(node.from_steps).to be_frozen
    end
  end
end
