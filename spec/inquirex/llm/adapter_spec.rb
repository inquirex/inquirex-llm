# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe "LLM Adapters" do
  describe Inquirex::LLM::Adapter do
    subject(:adapter) { described_class.new }

    let(:schema) { Inquirex::LLM::Schema.new(name: :string, count: :integer) }

    let(:extract_node) do
      Inquirex::LLM::Node.new(
        id:         :extract,
        verb:       :extract,
        prompt:     "Extract info.",
        schema:     schema,
        from_steps: [:input]
      )
    end

    let(:from_all_node) do
      Inquirex::LLM::Node.new(
        id:       :extract_all,
        verb:     :extract,
        prompt:   "Extract from everything.",
        schema:   schema,
        from_all: true
      )
    end

    # let(:summarize_node) do
    #   Inquirex::LLM::Node.new(
    #     id:       :summary,
    #     verb:     :summarize,
    #     prompt:   "Summarize.",
    #     from_all: true
    #   )
    # end

    describe "#call" do
      it "raises NotImplementedError" do
        expect { adapter.call(extract_node, {}) }.to raise_error(NotImplementedError)
      end
    end

    describe "#source_answers" do
      let(:answers) { { input: "hello", other: "world", extra: 42 } }

      it "returns from_steps subset" do
        result = adapter.source_answers(extract_node, answers)
        expect(result).to eq(input: "hello")
      end

      it "returns all answers when from_all" do
        result = adapter.source_answers(from_all_node, answers)
        expect(result).to eq answers
      end
    end

    describe "#validate_output!" do
      it "passes when all schema fields present" do
        output = { name: "Acme", count: 5 }
        expect { adapter.validate_output!(extract_node, output) }.not_to raise_error
      end

      it "raises SchemaViolationError when fields missing" do
        output = { name: "Acme" }
        expect { adapter.validate_output!(extract_node, output) }.to raise_error(
          Inquirex::LLM::Errors::SchemaViolationError, /missing fields.*count/
        )
      end

      it "skips validation when no schema" do
        bare = Inquirex::LLM::Node.new(
          id: :bare, verb: :extract, prompt: "p", from_steps: [:input]
        )
        expect { adapter.validate_output!(bare, "any text") }.not_to raise_error
      end
    end
  end

  describe Inquirex::LLM::NullAdapter do
    subject(:adapter) { described_class.new }

    let(:schema) { Inquirex::LLM::Schema.new(name: :string, count: :integer, active: :boolean) }

    let(:extract_node) do
      Inquirex::LLM::Node.new(
        id:         :extract,
        verb:       :extract,
        prompt:     "test",
        schema:     schema,
        from_steps: [:x]
      )
    end

    # let(:summarize_node) do
    #   Inquirex::LLM::Node.new(
    #     id:       :summary,
    #     verb:     :summarize,
    #     prompt:   "test",
    #     from_all: true
    #   )
    # end

    describe "#call with schema" do
      subject(:result) { adapter.call(extract_node) }

      it { is_expected.to be_a(Hash) }

      it "returns default values matching declared types" do
        expect(result[:name]).to eq ""
        expect(result[:count]).to eq 0
        expect(result[:active]).to be false
      end

      it "conforms to the schema" do
        expect(schema.valid_output?(result)).to be true
      end
    end

    describe "#call without schema" do
      subject(:result) do
        bare = Inquirex::LLM::Node.new(
          id: :bare, verb: :extract, prompt: "test", from_steps: [:x]
        )
        adapter.call(bare)
      end

      it { is_expected.to be_a(String) }
      it { is_expected.to include("extract") }
      it { is_expected.to include("bare") }
    end
  end
end
