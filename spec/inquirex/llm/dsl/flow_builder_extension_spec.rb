# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe Inquirex::LLM::DSL::FlowBuilderExtension do
  describe "clarify verb" do
    subject(:definition) do
      Inquirex.define id: "clarify-test" do
        start :input

        ask :input do
          type :text
          question "Describe your business."
          transition to: :extracted
        end

        clarify :extracted do
          from :input
          prompt "Extract structured business data."
          schema industry: :string, employee_count: :integer
          model :claude_sonnet
          temperature 0.3
          max_tokens 512
          transition to: :done
        end

        say :done do
          text "Complete."
        end
      end
    end

    it { is_expected.to be_a(Inquirex::Definition) }
    its(:step_ids) { is_expected.to include(:input, :extracted, :done) }

    describe "the clarify node" do
      subject(:node) { definition.step(:extracted) }

      it { is_expected.to be_a(Inquirex::LLM::Node) }
      its(:verb) { is_expected.to eq :clarify }
      its(:prompt) { is_expected.to eq "Extract structured business data." }
      its(:from_steps) { is_expected.to eq [:input] }
      its(:model) { is_expected.to eq :claude_sonnet }
      its(:temperature) { is_expected.to eq 0.3 }
      its(:max_tokens) { is_expected.to eq 512 }
      it { is_expected.to be_collecting }
      it { is_expected.not_to be_display }

      it "has correct schema fields" do
        expect(node.schema.field_names).to eq %i[industry employee_count]
      end
    end
  end

  describe "describe verb" do
    subject(:definition) do
      Inquirex.define id: "describe-test" do
        start :data

        ask :data do
          type :string
          question "What data?"
          transition to: :described
        end

        describe :described do # rubocop:disable RSpec/DescribeSymbol,RSpec/EmptyExampleGroup
          from :data
          prompt "Describe this data in plain English."
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    describe "the describe node" do
      subject(:node) { definition.step(:described) }

      it { is_expected.to be_a(Inquirex::LLM::Node) }
      its(:verb) { is_expected.to eq :describe }
      its(:schema) { is_expected.to be_nil }
    end
  end

  describe "summarize verb" do
    subject(:definition) do
      Inquirex.define id: "summarize-test" do
        start :q1

        ask :q1 do
          type :string
          question "Question 1?"
          transition to: :summary
        end

        summarize :summary do
          from_all
          prompt "Summarize the intake."
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    describe "the summarize node" do
      subject(:node) { definition.step(:summary) }

      it { is_expected.to be_a(Inquirex::LLM::Node) }
      its(:verb) { is_expected.to eq :summarize }
      its(:from_all) { is_expected.to be true }
      its(:from_steps) { is_expected.to be_empty }
    end
  end

  describe "detour verb" do
    subject(:definition) do
      Inquirex.define id: "detour-test" do
        start :input

        ask :input do
          type :text
          question "Describe your situation."
          transition to: :followup
        end

        detour :followup do
          from :input
          prompt "Generate follow-up questions."
          schema questions: :array, answers: :hash
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    describe "the detour node" do
      subject(:node) { definition.step(:followup) }

      it { is_expected.to be_a(Inquirex::LLM::Node) }
      its(:verb) { is_expected.to eq :detour }
    end
  end

  describe "core verbs still work" do
    subject(:definition) do
      Inquirex.define do
        start :greeting

        header :greeting do
          text "Welcome"
          transition to: :q1
        end

        ask :q1 do
          type :string
          question "Name?"
          transition to: :note
        end

        btw :note do
          text "This is a note."
          transition to: :warn
        end

        warning :warn do
          text "Careful!"
          transition to: :gate
        end

        confirm :gate do
          question "Continue?"
          transition to: :done
        end

        say :done do
          text "Done."
        end
      end
    end

    its(:step_ids) { is_expected.to include(:greeting, :q1, :note, :warn, :gate, :done) }

    it "core nodes remain Inquirex::Node (not LLM::Node)" do
      expect(definition.step(:q1)).to be_a(Inquirex::Node)
      expect(definition.step(:q1)).not_to be_a(Inquirex::LLM::Node)
    end
  end

  describe "validation errors" do
    it "raises when clarify has no prompt" do
      expect do
        Inquirex.define do
          start :x
          clarify(:x) { schema name: :string; from :y }
        end
      end.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires a prompt/)
    end

    it "raises when clarify has no schema" do
      expect do
        Inquirex.define do
          start :x
          clarify(:x) { prompt "test"; from :y }
        end
      end.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires a schema/)
    end

    it "raises when clarify has no from source" do
      expect do
        Inquirex.define do
          start :x
          clarify(:x) { prompt "test"; schema name: :string }
        end
      end.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires.*from/)
    end
  end
end
