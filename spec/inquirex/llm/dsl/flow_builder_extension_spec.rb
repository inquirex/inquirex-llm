# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe Inquirex::LLM::DSL::FlowBuilderExtension do
  describe "extract verb" do
    subject(:definition) do
      Inquirex.define id: "extract-test" do
        start :input

        ask :input do
          type :text
          question "Describe your business."
          transition to: :extracted
        end

        extract :extracted do
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

    describe "the extract node" do
      subject(:node) { definition.step(:extracted) }

      it { is_expected.to be_a(Inquirex::LLM::Node) }
      its(:verb) { is_expected.to eq :extract }
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

    it "treats clarify as an alias that still stores verb :extract" do
      via_alias = Inquirex.define id: "clarify-alias-test" do
        start :input
        ask(:input) { type :text; question "x"; transition to: :out }
        clarify(:out) { from :input; prompt "p"; schema name: :string; transition to: :done }
        say(:done) { text "Done." }
      end

      expect(via_alias.step(:out).verb).to eq :extract
    end
  end

  # describe "describe verb" do
  #   subject(:definition) do
  #     Inquirex.define id: "describe-test" do
  #       start :data
  #
  #       ask :data do
  #         type :string
  #         question "What data?"
  #         transition to: :described
  #       end
  #
  #       describe :described do
  #         from :data
  #         prompt "Describe this data in plain English."
  #         transition to: :done
  #       end
  #
  #       say :done do
  #         text "Done."
  #       end
  #     end
  #   end
  #
  #   describe "the describe node" do
  #     subject(:node) { definition.step(:described) }
  #
  #     it { is_expected.to be_a(Inquirex::LLM::Node) }
  #     its(:verb) { is_expected.to eq :describe }
  #     its(:schema) { is_expected.to be_nil }
  #   end
  # end

  # describe "summarize verb" do
  #   subject(:definition) do
  #     Inquirex.define id: "summarize-test" do
  #       start :q1
  #
  #       ask :q1 do
  #         type :string
  #         question "Question 1?"
  #         transition to: :summary
  #       end
  #
  #       summarize :summary do
  #         from_all
  #         prompt "Summarize the intake."
  #         transition to: :done
  #       end
  #
  #       say :done do
  #         text "Done."
  #       end
  #     end
  #   end
  #
  #   describe "the summarize node" do
  #     subject(:node) { definition.step(:summary) }
  #
  #     it { is_expected.to be_a(Inquirex::LLM::Node) }
  #     its(:verb) { is_expected.to eq :summarize }
  #     its(:from_all) { is_expected.to be true }
  #     its(:from_steps) { is_expected.to be_empty }
  #   end
  # end

  # describe "detour verb" do
  #   subject(:definition) do
  #     Inquirex.define id: "detour-test" do
  #       start :input
  #
  #       ask :input do
  #         type :text
  #         question "Describe your situation."
  #         transition to: :followup
  #       end
  #
  #       detour :followup do
  #         from :input
  #         prompt "Generate follow-up questions."
  #         schema questions: :array, answers: :hash
  #         transition to: :done
  #       end
  #
  #       say :done do
  #         text "Done."
  #       end
  #     end
  #   end
  #
  #   describe "the detour node" do
  #     subject(:node) { definition.step(:followup) }
  #
  #     it { is_expected.to be_a(Inquirex::LLM::Node) }
  #     its(:verb) { is_expected.to eq :detour }
  #   end
  # end

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
    it "raises when extract has no prompt" do
      expect do
        Inquirex.define do
          start :x
          extract(:x) { schema name: :string; from :y }
        end
      end.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires a prompt/)
    end

    it "raises when extract has no schema" do
      expect do
        Inquirex.define do
          start :x
          extract(:x) { prompt "test"; from :y }
        end
      end.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires a schema/)
    end

    it "raises when extract has no from source" do
      expect do
        Inquirex.define do
          start :x
          extract(:x) { prompt "test"; schema name: :string }
        end
      end.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires.*from/)
    end
  end

  describe "schema question references" do
    subject(:definition) do
      Inquirex.define id: "schema-refs" do
        start :describe_situation

        ask :describe_situation do
          type :text
          question "Tell us about your taxes."
          transition to: :extracted
        end

        # References resolve FORWARD: every referenced question is defined
        # below this step.
        extract :extracted do
          from :describe_situation
          prompt "Extract intake fields."
          schema :filing_status, :income_types, :dependents, :has_business, confidence: :decimal
          transition to: :filing_status
        end

        ask :filing_status do
          type :enum
          question "Filing status?"
          options({ "single" => "Single", "mfj" => "Married Filing Jointly" })
          transition to: :income_types
        end

        ask :income_types do
          type :multi_enum
          question "Income types?"
          options %w[W2 business crypto]
          transition to: :dependents
        end

        ask :dependents do
          type :integer
          question "How many dependents?"
          transition to: :has_business
        end

        confirm :has_business do
          question "Do you own a business?"
          transition to: :done
        end

        say :done do
          text "Thanks."
        end
      end
    end

    let(:schema) { definition.step(:extracted).schema }

    it "resolves each reference to the question's declared type" do
      expect(schema.fields).to eq(
        filing_status: :enum,
        income_types:  :multi_enum,
        dependents:    :integer,
        has_business:  :boolean,
        confidence:    :decimal
      )
    end

    it "folds enum option values into the schema" do
      expect(schema.values_for(:filing_status)).to eq %w[single mfj]
    end

    it "folds multi_enum option values into the schema" do
      expect(schema.values_for(:income_types)).to eq %w[W2 business crypto]
    end

    it "leaves non-enum fields unconstrained" do
      expect(schema.values_for(:dependents)).to be_nil
      expect(schema.values_for(:confidence)).to be_nil
    end

    it "resolves confirm references to :boolean" do
      expect(schema.fields[:has_business]).to eq :boolean
      expect(schema.values_for(:has_business)).to be_nil
    end

    it "serializes resolved values into the wire format" do
      wire = JSON.parse(definition.to_json)
      expect(wire.dig("steps", "extracted", "llm", "schema", "income_types")).to eq(
        "type" => "multi_enum", "values" => %w[W2 business crypto]
      )
      expect(wire.dig("steps", "extracted", "llm", "schema", "confidence")).to eq "decimal"
    end

    it "round-trips the resolved schema through LLM::Node.from_h" do
      node = definition.step(:extracted)
      restored = Inquirex::LLM::Node.from_h(:extracted, node.to_h)
      expect(restored.schema).to eq node.schema
      expect(restored.schema.values_for(:income_types)).to eq %w[W2 business crypto]
    end

    it "accepts an array argument as well as a splat" do
      defn = Inquirex.define id: "array-arg" do
        start :input
        ask(:input) { type :text; question "x"; transition to: :out }
        extract(:out) { from :input; prompt "p"; schema %i[status]; transition to: :status }
        ask(:status) { type :enum; question "Status?"; options %w[a b]; transition to: :done }
        say(:done) { text "Done." }
      end

      expect(defn.step(:out).schema.values_for(:status)).to eq %w[a b]
    end

    it "works through the clarify alias" do
      defn = Inquirex.define id: "alias-refs" do
        start :input
        ask(:input) { type :text; question "x"; transition to: :out }
        clarify(:out) { from :input; prompt "p"; schema :status; transition to: :status }
        ask(:status) { type :enum; question "Status?"; options %w[a b]; transition to: :done }
        say(:done) { text "Done." }
      end

      expect(defn.step(:out).schema.fields).to eq(status: :enum)
    end

    context "with prompt :auto" do
      subject(:auto_definition) do
        Inquirex.define id: "auto-prompt" do
          start :input
          ask(:input) { type :text; question "Tell us everything."; transition to: :out }

          extract :out do
            from :input
            prompt :auto
            schema :filing_status, :income_types, confidence: :decimal
            transition to: :filing_status
          end

          ask :filing_status do
            type :enum
            question "Filing status?"
            options %w[single mfj]
            transition to: :income_types
          end

          ask :income_types do
            type :multi_enum
            question "Income types?"
            options %w[W2 crypto]
            transition to: :done
          end

          say(:done) { text "Done." }
        end
      end

      let(:generated) { auto_definition.step(:out).prompt }

      it "generates a prompt enumerating each referenced question's wording" do
        expect(generated).to include("- filing_status: Filing status?")
        expect(generated).to include("- income_types: Income types?")
      end

      it "lists explicit fields by name and type" do
        expect(generated).to include("- confidence (decimal)")
      end

      it "serializes the generated prompt, never :auto, to the wire" do
        wire = JSON.parse(auto_definition.to_json)
        expect(wire.dig("steps", "out", "llm", "prompt")).to include("Filing status?")
      end

      it "raises when prompt :auto has no question references to generate from" do
        expect do
          Inquirex.define do
            start :input
            ask(:input) { type :text; question "x"; transition to: :out }
            extract(:out) { from :input; prompt :auto; schema name: :string }
          end
        end.to raise_error(
          Inquirex::LLM::Errors::DefinitionError, /prompt :auto.*requires schema question/m
        )
      end
    end

    context "with invalid references" do
      it "raises on a reference to an unknown question, listing known ones" do
        expect do
          Inquirex.define do
            start :input
            ask(:input) { type :text; question "x"; transition to: :out }
            extract(:out) { from :input; prompt "p"; schema :not_a_question }
          end
        end.to raise_error(
          Inquirex::LLM::Errors::DefinitionError,
          /unknown question :not_a_question.*Known questions: :input/m
        )
      end

      it "raises on a reference to a display-only step" do
        expect do
          Inquirex.define do
            start :input
            ask(:input) { type :text; question "x"; transition to: :out }
            extract(:out) { from :input; prompt "p"; schema :closing }
            say(:closing) { text "Bye." }
          end
        end.to raise_error(
          Inquirex::LLM::Errors::DefinitionError, /display-only.*say step/
        )
      end

      it "raises on a reference to another LLM step" do
        expect do
          Inquirex.define do
            start :input
            ask(:input) { type :text; question "x"; transition to: :first }
            extract(:first) { from :input; prompt "p"; schema :second }
            extract(:second) { from :input; prompt "p"; schema name: :string }
          end
        end.to raise_error(
          Inquirex::LLM::Errors::DefinitionError, /is an LLM step/
        )
      end

      it "raises when a field is both a reference and an explicit field" do
        expect do
          Inquirex.define do
            start :input
            ask(:input) { type :text; question "x"; transition to: :out }
            extract(:out) { from :input; prompt "p"; schema :status, status: :string }
            ask(:status) { type :enum; question "s?"; options %w[a b] }
          end
        end.to raise_error(
          Inquirex::LLM::Errors::DefinitionError, /both as a question reference and an explicit field/
        )
      end
    end
  end
end
