# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe Inquirex::LLM do
  it { is_expected.to be_a(Module) }

  describe "::VERSION" do
    subject { described_class::VERSION }

    it { is_expected.not_to be_nil }
    it { is_expected.to match(/\A\d+\.\d+\.\d+\z/) }
  end

  describe "Inquirex.define gains LLM verbs after require" do
    subject(:definition) do
      Inquirex.define id: "test-flow" do
        start :greeting

        ask :greeting do
          type :text
          question "Tell me about yourself."
          transition to: :extracted
        end

        clarify :extracted do
          from :greeting
          prompt "Extract key facts."
          schema name: :string, age: :integer
          transition to: :done
        end

        say :done do
          text "Thanks!"
        end
      end
    end

    it { is_expected.to be_a(Inquirex::Definition) }
    its(:id) { is_expected.to eq "test-flow" }
    its(:step_ids) { is_expected.to include(:greeting, :extracted, :done) }

    it "builds LLM nodes via the core entry point" do
      expect(definition.step(:extracted)).to be_a(Inquirex::LLM::Node)
      expect(definition.step(:extracted).verb).to eq :clarify
    end

    it "core nodes are unaffected" do
      expect(definition.step(:greeting)).to be_a(Inquirex::Node)
      expect(definition.step(:greeting)).not_to be_a(Inquirex::LLM::Node)
    end
  end
end
