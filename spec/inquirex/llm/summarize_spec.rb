# frozen_string_literal: true

require "rspec/its"

RSpec.describe Inquirex::LLM, "#summarize" do
  # A help-style flow: it explains things, asks one steering question, and
  # closes with a summary. This is the shape `summarize` exists for.
  def help_flow(&extra)
    Inquirex.define id: "depreciation-help" do
      start :intro

      say(:intro) { text "Depreciation spreads an asset's cost over its useful life."; transition to: :asset }

      ask :asset do
        type :enum
        question "What kind of asset?"
        options vehicle: "A vehicle", building: "A building"
        transition to: :wrap_up
      end

      instance_eval(&extra) if extra
    end
  end

  describe "the node it builds" do
    subject(:node) { definition.step(:wrap_up) }

    let(:definition) { help_flow { summarize(:wrap_up) { temperature 0.7 } } }

    its(:verb)        { is_expected.to eq(:summarize) }
    its(:temperature) { is_expected.to eq(0.7) }
    its(:schema)      { is_expected.to be_nil }
    its(:transitions) { is_expected.to be_empty }

    it { is_expected.to be_llm_verb }
    it { is_expected.to be_narrative }
    it { is_expected.to be_summarize }

    it "carries the gem's prompt, not one the author supplied" do
      expect(node.prompt).to eq(Inquirex::LLM::Prompts::SUMMARIZE)
    end

    it "serializes as a server-side step with no schema" do
      hash = node.to_h
      expect(hash["requires_server"]).to be(true)
      expect(hash["llm"]).to include("temperature" => 0.7)
      expect(hash["llm"]).not_to have_key("schema")
    end

    it "round-trips through the wire format" do
      restored = Inquirex::LLM::Node.from_h(:wrap_up, node.to_h)
      expect(restored.verb).to eq(:summarize)
      expect(restored.temperature).to eq(0.7)
    end
  end

  describe "the transcript accumulator" do
    it "is added automatically when the flow declares none" do
      definition = help_flow { summarize(:wrap_up) }
      expect(definition.accumulators.keys).to include(:transcript)
      expect(definition.accumulators[:transcript].type).to eq(:text)
    end

    it "is not added when the flow already declares a text accumulator" do
      definition = Inquirex.define id: "own-transcript" do
        accumulator :session_log, type: :text
        start :intro
        say(:intro) { text "Hello."; transition to: :wrap_up }
        summarize :wrap_up
      end

      expect(definition.accumulators.keys).to eq([:session_log])
    end

    it "is not added to a flow with no summarize step" do
      expect(help_flow.accumulators).to be_empty
    end

    it "leaves a numeric accumulator alone and adds the transcript alongside it" do
      definition = Inquirex.define id: "both" do
        accumulator :price, type: :currency
        start :intro
        say(:intro) { text "Hello."; transition to: :wrap_up }
        summarize :wrap_up
      end

      expect(definition.accumulators.keys).to contain_exactly(:price, :transcript)
    end
  end

  describe "what summarize refuses" do
    def expect_rejection(message, &)
      expect { help_flow(&) }
        .to raise_error(Inquirex::LLM::Errors::DefinitionError, message)
    end

    it "refuses an author-supplied prompt" do
      expect_rejection(/prompt is owned by the gem/) do
        summarize(:wrap_up) { prompt "Summarise it however I like." }
      end
    end

    it "refuses a schema" do
      expect_rejection(/returns prose, not fields/) do
        summarize(:wrap_up) { schema total: :currency }
      end
    end

    it "refuses `from`" do
      expect_rejection(/reads the whole session transcript/) do
        summarize(:wrap_up) { from :asset }
      end
    end

    it "refuses `from_all`" do
      expect_rejection(/reads the whole session transcript/) do
        summarize(:wrap_up) { from_all }
      end
    end

    it "refuses a transition, because it must end the flow" do
      expect_rejection(/must be the last step in the flow/) do
        summarize(:wrap_up) { transition to: :intro }
      end
    end

    it "refuses to be followed by another step" do
      expect_rejection(/summarize must be the last step declared/) do
        summarize :wrap_up
        say(:afterword) { text "One more thing." }
      end
    end

    it "refuses a second summarize step" do
      expect_rejection(/may close with only one/) do
        summarize :wrap_up
        summarize :wrap_up_again
      end
    end
  end

  describe "the operational knobs it keeps" do
    subject(:node) { definition.step(:wrap_up) }

    let(:definition) do
      help_flow do
        summarize :wrap_up do
          temperature 0.9
          model :claude_haiku
          max_tokens 8000
        end
      end
    end

    # These change how the summary is generated, not what it may say, so they
    # stay available to the flow author.
    its(:temperature) { is_expected.to eq(0.9) }
    its(:model)       { is_expected.to eq(:claude_haiku) }
    its(:max_tokens)  { is_expected.to eq(8000) }
  end

  describe "extract is unaffected" do
    it "still requires a prompt and a schema" do
      expect {
        Inquirex.define id: "still-strict" do
          start :desc
          ask(:desc) { type :text; question "Describe."; transition to: :out }
          extract(:out) { from :desc }
        end
      }.to raise_error(Inquirex::LLM::Errors::DefinitionError, /requires a prompt/)
    end
  end
end
