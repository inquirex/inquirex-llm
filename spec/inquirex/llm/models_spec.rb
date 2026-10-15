# frozen_string_literal: true

RSpec.describe Inquirex::LLM::Models do
  describe "ANTHROPIC" do
    it "lists only current ids, each once" do
      expect(described_class::ANTHROPIC).to eq(%w[claude-fable-5-1 claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5])
    end

    it "draws the default from the catalogue" do
      expect(described_class::ANTHROPIC).to include(described_class::ANTHROPIC_DEFAULT)
    end

    it "draws every alias value from the catalogue" do
      expect(described_class::ANTHROPIC_ALIASES.values).to all(satisfy { |id| described_class::ANTHROPIC.include?(id) })
    end

    it "keeps the short symbols flows already use" do
      expect(described_class::ANTHROPIC_ALIASES).to include(
        claude_sonnet: "claude-sonnet-5-5",
        claude_haiku:  "claude-haiku-5-5",
        claude_opus:   "claude-opus-5-5",
        claude_fable:  "claude-fable-5-1"
      )
    end
  end

  describe "OPENAI_ALIASES" do
    it "draws the default from the aliases" do
      expect(described_class::OPENAI_ALIASES.values).to include(described_class::OPENAI_DEFAULT)
    end

    it "does not map :claude_fable, which has no OpenAI equivalent" do
      expect(described_class::OPENAI_ALIASES).not_to have_key(:claude_fable)
    end
  end
end
