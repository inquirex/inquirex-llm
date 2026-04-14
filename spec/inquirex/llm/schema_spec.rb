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
end
