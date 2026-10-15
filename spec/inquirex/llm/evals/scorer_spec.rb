# frozen_string_literal: true

require "inquirex/llm/evals"

RSpec.describe Inquirex::LLM::Evals::Scorer do
  subject(:scorer) { described_class.new }

  let(:schema) do
    Inquirex::LLM::Schema.new(
      seat_count:        :integer,
      work_model:        { type: :enum, values: %w[mostly_office mostly_remote hybrid] },
      infrastructure:    { type: :enum, values: %w[cloud_only on_prem hybrid] },
      server_count:      :integer,
      current_support:   { type: :enum, values: %w[none internal_person another_provider] },
      compliance:        { type: :multi_enum, values: %w[hipaa soc2 pci other none] },
      security_incident: :boolean,
      growth_planned:    :boolean,
      response_time:     { type: :enum, values: %w[next_business_day four_hours one_hour] },
      biggest_pain:      { type: :enum, values: %w[downtime slow_support security_worries cost scaling] }
    )
  end
  let(:context) { { schema: schema } }

  def kase(expected) = Agent::Evals::Case.new(id: "x", dataset: "d", variant: "x", input: "t", expected: expected, path: "/", metadata: {})
  def reply(raw) = Agent::Evals::Reply.new(output: raw, raw: raw)
  def score(spec, truth, got, present: true) = Inquirex::LLM::Evals::FieldScore.of("f", spec, truth, got, present: present)

  describe "one field" do
    enum = Inquirex::LLM::Schema::Field.new(type: :enum, values: %w[hybrid on_prem])
    multi = Inquirex::LLM::Schema::Field.new(type: :multi_enum, values: %w[hipaa soc2 pci])
    int = Inquirex::LLM::Schema::Field.new(type: :integer, values: nil)
    bool = Inquirex::LLM::Schema::Field.new(type: :boolean, values: nil)
    str = Inquirex::LLM::Schema::Field.new(type: :string, values: nil)

    [
      # rule                                        spec   truth           got             outcome          value  note
      ["the right enum value",                      enum,  "hybrid",       "hybrid",       "correct",       1.0,   nil],
      ["a case variant the gem repairs",            enum,  "hybrid",       "Hybrid ",      "correct",       1.0,   /repaired/],
      ["the wrong enum value",                      enum,  "hybrid",       "on_prem",      "incorrect",     0.1,   /expected "hybrid"/],
      ["an enum value off the list",                enum,  "hybrid",       "colo",         "invalid",       0.0,   /not one of/],
      ["an unset enum where the text answers",      enum,  "hybrid",       nil,            "missed",        0.2,   nil],
      ["an empty string where the text answers",    enum,  "hybrid",       "",             "missed",        0.2,   nil],
      ["a key the reply left out",                  enum,  "hybrid",       nil,            "missed",        0.2,   /key absent/],
      ["null where the text is silent",             enum,  nil,            nil,            "correct",       1.0,   nil],
      ["an empty string where the text is silent",  enum,  nil,            "",             "correct",       1.0,   /form drift/],
      ["an empty list where the text is silent",    multi, nil,            [],             "correct",       1.0,   /form drift/],
      ["an answer where the text is silent",        enum,  nil,            "hybrid",       "hallucinated",  0.15,  /expected null/],
      ["zero where the text is silent",             int,   nil,            0,              "hallucinated",  0.15,  /expected null, got 0/],
      ["false where the text is silent",            bool,  nil,            false,          "hallucinated",  0.15,  /expected null, got false/],
      ["an off-list value where the text is silent", enum, nil,            "colo",         "invalid",       0.0,   /not one of/],
      ["an integer as an Integer",                  int,   3,              3,              "correct",       1.0,   nil],
      ["an integer as a whole Float",               int,   3,              3.0,            "correct",       1.0,   /repaired/],
      ["an integer as a base-10 String",            int,   3,              " 3 ",          "correct",       1.0,   /repaired/],
      ["a different integer",                       int,   3,              4,              "incorrect",     0.1,   /expected 3, got 4/],
      ["something that is not an integer",          int,   3,              "three",        "invalid",       0.0,   /not an integer/],
      ["a fractional float for an integer",         int,   3,              3.5,            "invalid",       0.0,   /not an integer/],
      ["the right boolean",                         bool,  true,           true,           "correct",       1.0,   nil],
      ["the wrong boolean",                         bool,  true,           false,          "incorrect",     0.1,   /expected true, got false/],
      ["a boolean as a string",                     bool,  true,           "true",         "invalid",       0.0,   /not a boolean/],
      ["a string compared after trimming",          str,   "Acme",         " Acme",        "correct",       1.0,   /repaired/],
      ["a string that differs",                     str,   "Acme",         "Apex",         "incorrect",     0.1,   /expected "Acme"/],
      ["the same multi_enum set",                   multi, %w[hipaa soc2], %w[soc2 hipaa], "correct",       1.0,   nil],
      ["two of three named",                        multi, %w[hipaa soc2 pci], %w[hipaa soc2], "2/3 correct, 1/3 missed", 0.7333, /missed pci/],
      ["one right, one invented",                   multi, %w[hipaa],      %w[hipaa pci],  "1/2 correct, 1/2 hallucinated", 0.575, /hallucinated pci/],
      ["one right, one missed, one invented",       multi, %w[hipaa soc2], %w[hipaa pci],  "1/3 correct, 1/3 missed, 1/3 hallucinated", 0.45, /missed soc2; hallucinated pci/],
      ["one right, one off the list",               multi, %w[hipaa],      %w[hipaa gdpr], "1/2 correct, 1/2 invalid", 0.5, /invalid "gdpr"/],
      ["a case variant inside the list",            multi, %w[hipaa],      %w[HIPAA],      "correct",       1.0,   /repaired "HIPAA"/],
      ["an empty list where the text lists two",    multi, %w[hipaa soc2], [],             "missed",        0.2,   /missed hipaa, soc2/],
      ["null where the text lists two",             multi, %w[hipaa soc2], nil,            "missed",        0.2,   /missed hipaa, soc2/],
      ["a list where the text is silent",           multi, nil,            %w[hipaa],      "hallucinated",  0.15,  /hallucinated hipaa/],
      ["a string where a list was due",             multi, %w[hipaa],      "hipaa",        "invalid",       0.0,   /not an array/]
    ].each do |rule, spec, truth, got, outcome, value, note|
      it "grades #{rule} as #{outcome}" do
        present = rule != "a key the reply left out"
        field = score(spec, truth, got, present: present)
        expect(field.outcome).to eq(outcome)
        expect(field.value).to be_within(0.0001).of(value)
        note ? expect(field.note).to(match(note)) : expect(field.note).to(be_nil)
      end
    end
  end

  describe "#call" do
    let(:expected) do
      { "seat_count" => 45, "work_model" => "hybrid", "infrastructure" => "hybrid", "server_count" => 2,
        "current_support" => "internal_person", "compliance" => %w[hipaa], "security_incident" => true,
        "growth_planned" => nil, "response_time" => "four_hours", "biggest_pain" => "security_worries" }
    end

    # The worked example from the decisions: 5 correct, compliance half right
    # and half invented, one key absent, one answer where the text is silent,
    # one wrong enum, one off-list value. 5 + 0.575 + 0.2 + 0.15 + 0.1 + 0 over 10.
    let(:raw) do
      { "seat_count" => 45, "work_model" => "hybrid", "infrastructure" => "hybrid", "server_count" => 2,
        "current_support" => "internal_person", "compliance" => %w[hipaa pci], "security_incident" => false,
        "growth_planned" => false, "response_time" => "same_day" }
    end
    let(:result) { scorer.call(kase(expected), reply(raw), context: context) }

    it "scores the worked example 0.60" do
      expect(result.value.round(2)).to eq(0.60)
      expect(result.value).to be_within(0.0001).of(0.6025)
    end

    it "reports every metric" do
      expect(result.metrics["score"]).to be_within(0.0001).of(0.6025)
      expect(result.metrics["exact"]).to eq(0.0)
      expect(result.metrics["hallucinated_rate"]).to eq(1.0)
      expect(result.metrics["invalid_rate"]).to be_within(0.0001).of(0.1)
    end

    it "names each field's outcome and diagnoses the ones that were not plainly correct" do
      expect(result.outcomes).to include("seat_count" => "correct",
        "compliance" => "1/2 correct, 1/2 hallucinated",
        "biggest_pain" => "missed",
        "growth_planned" => "hallucinated",
        "security_incident" => "incorrect",
        "response_time" => "invalid")
      expect(result.diagnostics.keys).to contain_exactly("compliance", "biggest_pain", "growth_planned", "security_incident", "response_time")
      expect(result.diagnostics["biggest_pain"]).to eq(outcome: "missed", want: "security_worries", note: "key absent")
    end

    it "is exact, with no hallucination rate, when a complete text is answered perfectly" do
      full = expected.merge("growth_planned" => true)
      perfect = scorer.call(kase(full), reply(full), context: context)
      expect(perfect.value).to eq(1.0)
      expect(perfect.metrics).to include("exact" => 1.0, "hallucinated_rate" => nil, "invalid_rate" => 0.0)
      expect(perfect.diagnostics).to be_empty
    end

    it "compares keys as strings" do
      symbols = scorer.call(kase(expected.merge("growth_planned" => true)), reply(expected.merge("growth_planned" => true).transform_keys(&:to_sym)), context: context)
      expect(symbols.value).to eq(1.0)
    end

    it "fails every field as invalid when the reply is not a JSON object" do
      junk = scorer.call(kase(expected), reply("not json"), context: context)
      expect(junk.value).to eq(0.0)
      expect(junk.metrics["invalid_rate"]).to eq(1.0)
      expect(junk.outcomes.values.uniq).to eq(["invalid"])
    end
  end

  describe "#verify" do
    let(:good) { { "seat_count" => 45, "work_model" => nil, "infrastructure" => "hybrid", "server_count" => nil, "current_support" => "none", "compliance" => ["hipaa"], "security_incident" => true, "growth_planned" => nil, "response_time" => nil, "biggest_pain" => "cost" } }

    it "passes an expected answer that fits the schema, nulls included" do
      expect(scorer.verify(kase(good), context: context)).to be_empty
    end

    it "names an unknown key, an off-list value and a wrong type" do
      bad = good.merge("extra" => 1, "work_model" => "office", "seat_count" => "45").except("biggest_pain")
      expect(scorer.verify(kase(bad), context: context)).to contain_exactly(
        "missing biggest_pain", "unknown fields extra", 'seat_count: "45" is not an integer', 'work_model: "office" is not one of mostly_office|mostly_remote|hybrid'
      )
    end
  end

  describe "#summary" do
    it { expect(scorer.summary(kase("a" => 1, "b" => nil, "c" => []))).to eq("answered 2/3") }
    it { expect(scorer.summary(kase([1]))).to be_nil }
  end

  describe "#metrics" do
    it "ranks by score" do
      expect(scorer.primary.name).to eq("score")
      expect(scorer.metrics.map(&:name)).to eq(%w[score exact hallucinated_rate invalid_rate])
    end
  end
end
