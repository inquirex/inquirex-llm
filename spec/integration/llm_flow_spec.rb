# frozen_string_literal: true

require "rspec"
require "rspec/its"

# Realistic tax intake flow that mixes core verbs with LLM verbs.
# The LLM steps are server-side only; the engine treats them as collecting steps
# whose answers are provided by the server adapter.
LLM_TAX_FLOW = Inquirex.define id: "tax-intake-llm", version: "1.0.0" do
  meta title: "Smart Tax Intake",
    subtitle: "AI-powered qualification",
    brand: { name: "Agentica", color: "#2563eb" }

  start :filing_status

  ask :filing_status do
    type :enum
    question "What is your filing status?"
    options single: "Single", married_jointly: "Married Filing Jointly"
    transition to: :business_description, if_rule: equals(:filing_status, "married_jointly")
    transition to: :simple_summary
  end

  ask :business_description do
    type :text
    question "Describe your business in a few sentences."
    transition to: :business_extracted
  end

  clarify :business_extracted do
    from :business_description
    prompt "Extract structured business information from the user's description."
    schema industry: :string,
      entity_type: :string,
      employee_count: :integer,
      estimated_revenue: :currency
    model :claude_sonnet
    temperature 0.2
    transition to: :intake_summary
  end

  summarize :intake_summary do
    from_all
    prompt "Summarize this client's tax situation and flag complexity concerns."
    transition to: :review
  end

  summarize :simple_summary do
    from_all
    prompt "Provide a brief summary for this simple filing."
    transition to: :review
  end

  say :review do
    text "Thank you! We have all the information we need."
  end
end

RSpec.describe "LLM flow integration" do
  let(:adapter) { Inquirex::LLM::NullAdapter.new }

  describe "simple path (single filer)" do
    subject(:engine) { Inquirex::Engine.new(LLM_TAX_FLOW) }

    it "walks the short path through summarize to review" do
      engine.answer("single")
      expect(engine.current_step_id).to eq(:simple_summary)

      # Server processes the summarize step via LLM adapter
      summary = adapter.call(engine.current_step)
      engine.answer(summary)

      expect(engine.current_step_id).to eq(:review)
      engine.advance
      expect(engine).to be_finished
    end
  end

  describe "complex path (business filer)" do
    subject(:engine) { Inquirex::Engine.new(LLM_TAX_FLOW) }

    it "routes through business description, clarify, and summarize" do
      engine.answer("married_jointly")
      expect(engine.current_step_id).to eq(:business_description)

      engine.answer("I run an LLC selling SaaS products with 15 employees.")
      expect(engine.current_step_id).to eq(:business_extracted)

      # Server processes clarify step
      extracted = adapter.call(engine.current_step)
      expect(extracted).to be_a(Hash)
      expect(extracted).to include(:industry, :entity_type, :employee_count, :estimated_revenue)
      engine.answer(extracted)

      expect(engine.current_step_id).to eq(:intake_summary)

      # Server processes summarize step
      summary = adapter.call(engine.current_step)
      expect(summary).to be_a(String)
      engine.answer(summary)

      expect(engine.current_step_id).to eq(:review)
      engine.advance
      expect(engine).to be_finished
    end
  end

  describe "JSON serialization" do
    subject(:json) { LLM_TAX_FLOW.to_json }

    let(:parsed) { JSON.parse(json) }

    it "includes flow metadata" do
      expect(parsed["id"]).to eq "tax-intake-llm"
      expect(parsed["version"]).to eq "1.0.0"
    end

    it "marks LLM steps with requires_server" do
      expect(parsed["steps"]["business_extracted"]["requires_server"]).to be true
      expect(parsed["steps"]["intake_summary"]["requires_server"]).to be true
    end

    it "serializes LLM metadata under 'llm' key" do
      clarify_step = parsed["steps"]["business_extracted"]
      expect(clarify_step["llm"]["prompt"]).to include("Extract structured")
      expect(clarify_step["llm"]["schema"]).to eq(
        "industry"          => "string",
        "entity_type"       => "string",
        "employee_count"    => "integer",
        "estimated_revenue" => "currency"
      )
      expect(clarify_step["llm"]["model"]).to eq "claude_sonnet"
      expect(clarify_step["llm"]["temperature"]).to eq 0.2
    end

    it "serializes summarize steps correctly" do
      summary_step = parsed["steps"]["intake_summary"]
      expect(summary_step["verb"]).to eq "summarize"
      expect(summary_step["llm"]["from_all"]).to be true
      expect(summary_step["llm"]["prompt"]).to include("Summarize")
    end

    it "preserves core steps without LLM metadata" do
      ask_step = parsed["steps"]["filing_status"]
      expect(ask_step["verb"]).to eq "ask"
      expect(ask_step).not_to have_key("llm")
      expect(ask_step).not_to have_key("requires_server")
    end
  end

  describe "mixed node types" do
    it "LLM nodes are Inquirex::LLM::Node" do
      expect(LLM_TAX_FLOW.step(:business_extracted)).to be_a(Inquirex::LLM::Node)
      expect(LLM_TAX_FLOW.step(:intake_summary)).to be_a(Inquirex::LLM::Node)
    end

    it "core nodes remain Inquirex::Node" do
      expect(LLM_TAX_FLOW.step(:filing_status)).to be_a(Inquirex::Node)
      expect(LLM_TAX_FLOW.step(:filing_status)).not_to be_a(Inquirex::LLM::Node)
    end

    it "all LLM nodes report collecting" do
      %i[business_extracted intake_summary simple_summary].each do |id|
        expect(LLM_TAX_FLOW.step(id)).to be_collecting
      end
    end
  end
end
