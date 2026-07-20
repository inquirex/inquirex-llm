# frozen_string_literal: true

require "rspec"
require "rspec/its"

# End-to-end check of examples/tax-preparation-estimator.rb: the extract
# step's schema is declared purely as question references, so every field's
# type — and every enum's allowed values — must be resolved from the
# questions defined further down the flow.
RSpec.describe "examples/tax-preparation-estimator.rb" do
  # Evaluated inside a method so the example's DSL is parsed against a clean
  # binding (top-level locals would otherwise shadow DSL methods like schema).
  def load_example(path) = eval(File.read(path), binding, path) # rubocop:disable Security/Eval

  subject(:definition) do
    load_example(File.expand_path("../../examples/tax-preparation-estimator.rb", __dir__))
  end

  let(:schema) { definition.step(:summary).schema }

  it { is_expected.to be_a(Inquirex::Definition) }
  its(:id) { is_expected.to eq "tax-preparer-2025" }

  it "resolves every schema reference to its question's type" do
    expect(schema.fields).to eq(
      filing_status:          :enum,
      dependents:             :enum,
      income_types:           :multi_enum,
      state_filing:           :multi_enum,
      residency_status:       :enum,
      prior_return_available: :enum,
      business_entities:      :multi_enum
    )
  end

  it "folds the income_types options into the schema" do
    expect(schema.values_for(:income_types)).to include("W2", "1099_nec", "business", "crypto", "none")
    expect(schema.values_for(:income_types).size).to eq 14
  end

  it "folds all 50 states plus DC into state_filing" do
    expect(schema.values_for(:state_filing).size).to eq 51
    expect(schema.values_for(:state_filing)).to include("CA", "NY", "DC")
  end

  it "resolves bucketed enum values exactly as the question declares them" do
    expect(schema.values_for(:dependents)).to eq %w[0 1 2 3 4+]
  end

  it "marks the extract step requires_server in the wire format" do
    wire = JSON.parse(definition.to_json)
    expect(wire.dig("steps", "summary", "requires_server")).to be true
  end

  it "ships enum values to the frontend in the wire format" do
    wire = JSON.parse(definition.to_json)
    filing = wire.dig("steps", "summary", "llm", "schema", "filing_status")
    expect(filing["type"]).to eq "enum"
    expect(filing["values"]).to include("single", "married_filing_jointly")
  end

  describe "NullAdapter output against the resolved schema" do
    subject(:result) { Inquirex::LLM::NullAdapter.new.call(definition.step(:summary)) }

    it "conforms to the schema" do
      expect(schema.valid_output?(result)).to be true
    end

    it "answers every enum with a value the downstream question accepts" do
      expect(definition.step(:filing_status).options).to include(result[:filing_status])
      expect(definition.step(:income_types).options).to include(*result[:income_types])
    end
  end
end
