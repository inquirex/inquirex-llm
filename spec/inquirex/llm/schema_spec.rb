# frozen_string_literal: true

require "rspec"
require "rspec/its"

RSpec.describe Inquirex::LLM::Schema do
  subject(:schema) do
    described_class.new(
      industry:          :string,
      entity_type:       :enum,
      employee_count:    :integer,
      estimated_revenue: :currency
    )
  end

  describe "#fields" do
    subject { schema.fields }

    it { is_expected.to be_a(Hash) }
    it { is_expected.to be_frozen }
    its(:size) { is_expected.to eq 4 }
  end

  describe "#field_names" do
    subject { schema.field_names }

    it { is_expected.to eq %i[industry entity_type employee_count estimated_revenue] }
  end

  describe "#size" do
    subject { schema.size }

    it { is_expected.to eq 4 }
  end

  describe "#valid_output?" do
    it "returns true when all fields present" do
      output = { industry: "Tech", entity_type: "LLC", employee_count: 10, estimated_revenue: 500_000 }
      expect(schema.valid_output?(output)).to be true
    end

    it "returns true with string keys" do
      output = { "industry" => "Tech", "entity_type" => "LLC", "employee_count" => 10, "estimated_revenue" => 500_000 }
      expect(schema.valid_output?(output)).to be true
    end

    it "returns false when field missing" do
      output = { industry: "Tech", employee_count: 10 }
      expect(schema.valid_output?(output)).to be false
    end

    it "returns false for non-hash" do
      expect(schema.valid_output?("not a hash")).to be false
    end
  end

  describe "#missing_fields" do
    it "returns empty array when complete" do
      output = { industry: "Tech", entity_type: "LLC", employee_count: 10, estimated_revenue: 500_000 }
      expect(schema.missing_fields(output)).to be_empty
    end

    it "returns missing field names" do
      output = { industry: "Tech" }
      expect(schema.missing_fields(output)).to eq %i[entity_type employee_count estimated_revenue]
    end

    it "returns all fields for non-hash input" do
      expect(schema.missing_fields("not a hash")).to eq schema.field_names
    end
  end

  describe "JSON round-trip" do
    subject(:restored) { described_class.from_h(schema.to_h) }

    it { is_expected.to eq schema }
    its(:field_names) { is_expected.to eq schema.field_names }
  end

  describe "immutability" do
    it { is_expected.to be_frozen }

    it "raises on field mutation attempt" do
      expect { schema.fields[:new_field] = :string }.to raise_error(FrozenError)
    end
  end

  describe "validation" do
    it "raises on empty field map" do
      expect { described_class.new }.to raise_error(Inquirex::LLM::Errors::DefinitionError, /at least one field/)
    end

    it "raises on unknown type" do
      expect { described_class.new(name: :banana) }.to raise_error(
        Inquirex::LLM::Errors::DefinitionError, /Unknown type.*banana/
      )
    end
  end

  describe "#inspect" do
    subject { schema.inspect }

    it { is_expected.to include("industry:string") }
    it { is_expected.to include("employee_count:integer") }
  end

  describe "value-constrained fields" do
    subject(:constrained) do
      described_class.new(
        filing_status: { type: :enum, values: %w[single married_filing_jointly head_of_household] },
        income_types:  { type: :multi_enum, values: %w[W2 business crypto] },
        dependents:    :integer
      )
    end

    describe "#fields" do
      subject { constrained.fields }

      it { is_expected.to eq(filing_status: :enum, income_types: :multi_enum, dependents: :integer) }
    end

    describe "#values_for" do
      it "returns the allowed values for constrained fields" do
        expect(constrained.values_for(:filing_status)).to eq %w[single married_filing_jointly head_of_household]
        expect(constrained.values_for(:income_types)).to eq %w[W2 business crypto]
      end

      it "returns nil for unconstrained fields" do
        expect(constrained.values_for(:dependents)).to be_nil
      end

      it "returns nil for unknown fields" do
        expect(constrained.values_for(:nope)).to be_nil
      end

      it "accepts string field names" do
        expect(constrained.values_for("income_types")).to eq %w[W2 business crypto]
      end
    end

    describe "#to_h wire format" do
      subject(:wire) { constrained.to_h }

      it "serializes constrained fields as type + values" do
        expect(wire["filing_status"]).to eq(
          "type" => "enum", "values" => %w[single married_filing_jointly head_of_household]
        )
      end

      it "serializes unconstrained fields as a plain type string" do
        expect(wire["dependents"]).to eq "integer"
      end
    end

    describe "JSON round-trip with values" do
      subject(:restored) { described_class.from_h(JSON.parse(constrained.to_json)) }

      it { is_expected.to eq constrained }

      it "preserves allowed values" do
        expect(restored.values_for(:income_types)).to eq %w[W2 business crypto]
      end
    end

    describe "validation" do
      it "raises when a hash spec has no :type" do
        expect { described_class.new(broken: { values: %w[a b] }) }.to raise_error(
          Inquirex::LLM::Errors::DefinitionError, /missing :type/
        )
      end

      it "raises on unknown type inside a hash spec" do
        expect { described_class.new(broken: { type: :banana }) }.to raise_error(
          Inquirex::LLM::Errors::DefinitionError, /Unknown type.*banana/
        )
      end
    end

    describe "#inspect" do
      subject { constrained.inspect }

      it { is_expected.to include("income_types:multi_enum(W2|business|crypto)") }
      it { is_expected.to include("dependents:integer") }
    end
  end
end
