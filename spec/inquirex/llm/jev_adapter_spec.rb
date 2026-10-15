# frozen_string_literal: true

require "net/http"

RSpec.describe Inquirex::LLM::JevAdapter do
  subject(:adapter) { described_class.new(api_key: "ts-test", wait: ->(seconds) { calls[:waits] << seconds }) }

  let(:calls) { { requests: [], waits: [] } }
  let(:schema) do
    Inquirex::LLM::Schema.new(
      filing_status: { type: :enum, values: %w[single married_jointly] },
      self_employed: :boolean,
      dependents:    :integer,
      income_types:  { type: :multi_enum, values: %w[w2 crypto rental] }
    )
  end
  let(:node) do
    Inquirex::LLM::Node.new(
      id:         :understanding,
      verb:       :extract,
      prompt:     "Extract the tax situation.",
      schema:     schema,
      from_steps: [:tell_me]
    )
  end
  let(:answers) { { tell_me: "Married, three kids, I freelance and hold some bitcoin." } }
  let(:jev) do
    {
      "filing_status"           => { "type" => "choice", "choice" => "married_jointly", "confidence" => 0.9 },
      "self_employed"           => { "type" => "choice", "choice" => "yes", "confidence" => 0.95 },
      "dependents"              => { "type" => "choice", "choice" => "3", "confidence" => 0.4 },
      "income_types__addressed" => { "type" => "choice", "choice" => "yes", "confidence" => 0.8 },
      "income_types__w2"        => { "type" => "noul", "noul" => 0.1 },
      "income_types__crypto"    => { "type" => "noul", "noul" => 0.9 },
      "income_types__rental"    => { "type" => "noul", "noul" => 0.5 }
    }
  end
  let(:responses) { [ok] }

  def ok = response(Net::HTTPOK, "200", JSON.generate("model" => "jev-1.13.0", "answers" => jev, "usage" => { "input_tokens" => 812, "output_tokens" => 40 }))

  def response(klass, code, body, headers = {})
    instance_double(klass, code: code, body: body).tap do |r|
      allow(r).to receive(:is_a?) { |k| k == Net::HTTPSuccess && code.start_with?("2") }
      allow(r).to receive(:[]) { |name| headers[name] }
    end
  end

  before do
    http = instance_double(Net::HTTP, :use_ssl= => nil, :read_timeout= => nil, :open_timeout= => nil)
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) do |request|
      calls[:requests] << request
      responses.shift || ok
    end
  end

  describe "#call" do
    subject(:result) { adapter.call(node, answers) }

    it "reads every field back in the schema's shape" do
      expect(result).to eq(
        filing_status: "married_jointly", self_employed: true, dependents: 3, income_types: %w[crypto rental]
      )
    end

    describe "the request" do
      subject(:body) { result && JSON.parse(calls[:requests].first.body) }

      it "goes to TypeSafe with the key and the default model" do
        result
        expect(calls[:requests].first["Authorization"]).to eq("Bearer ts-test")
        expect(body["model"]).to eq("jev-latest")
      end

      it "sends the source answers as state" do
        expect(body["state"]).to eq("answers" => { "tell_me" => answers[:tell_me] })
      end

      it "asks a Choice per enum, with the escape hatch" do
        expect(body.dig("questions", "filing_status", "criteria").keys)
          .to eq(%w[single married_jointly not_stated_in_text])
      end

      it "carries the author's prompt as context" do
        expect(body.dig("questions", "self_employed", "instructions", "context")).to eq("Extract the tax situation.")
      end

      it "offers the numbers the text states, in words, among the integer options" do
        expect(body.dig("questions", "dependents", "criteria").keys).to include("3", "12", "not_stated_in_text")
      end

      it "asks a Noul per multi_enum value" do
        expect(body.dig("questions", "income_types__crypto", "type")).to eq("noul")
      end
    end

    context "when Jev says the text is silent" do
      before do
        jev["filing_status"]["choice"] = "not_stated_in_text"
        jev["income_types__addressed"]["choice"] = "not_stated_in_text"
        jev["self_employed"]["choice"] = "no"
      end

      it "leaves those fields nil, and keeps a real no" do
        expect(result).to include(filing_status: nil, income_types: nil, self_employed: false)
      end
    end

    context "with min_confidence" do
      subject(:result) { described_class.new(api_key: "ts-test", min_confidence: 0.5).call(node, answers) }

      it "drops answers Jev was less sure of" do
        expect(result).to include(dependents: nil, filing_status: "married_jointly")
      end
    end

    context "when TypeSafe is rate limited, then answers" do
      let(:responses) { [response(Net::HTTPTooManyRequests, "429", "slow down", "retry-after" => "2"), ok] }

      it "waits as asked, and retries" do
        expect(result[:dependents]).to eq(3)
        expect(calls[:waits]).to eq([2.0])
      end
    end

    context "when TypeSafe stays overloaded" do
      let(:responses) { Array.new(3) { response(Net::HTTPServiceUnavailable, "529", "overloaded") } }

      it "gives up after the retries, with backoff" do
        expect { result }.to raise_error(Inquirex::LLM::Errors::AdapterError, /TypeSafe API error 529/)
        expect(calls[:waits]).to eq([0.5, 1.0])
      end
    end

    context "when TypeSafe rejects the request" do
      let(:responses) { [response(Net::HTTPUnprocessableEntity, "422", '{"detail":"bad"}')] }

      it "raises without retrying" do
        expect { result }.to raise_error(Inquirex::LLM::Errors::AdapterError, /422/)
        expect(calls[:requests].size).to eq(1)
      end
    end

    context "when the body is not JSON" do
      let(:responses) { [response(Net::HTTPOK, "200", "<html>")] }

      it { expect { result }.to raise_error(Inquirex::LLM::Errors::AdapterError, /not JSON/) }
    end

    context "with a field Jev cannot answer" do
      let(:schema) { Inquirex::LLM::Schema.new(name: :string, dependents: :integer) }

      it "raises before sending anything" do
        expect { result }.to raise_error(Inquirex::LLM::Errors::AdapterError, /cannot answer name/)
        expect(calls[:requests]).to be_empty
      end
    end

    context "without a schema" do
      let(:node) { Inquirex::LLM::Node.new(id: :free, verb: :extract, prompt: "p", from_steps: [:tell_me]) }

      it { expect { result }.to raise_error(Inquirex::LLM::Errors::AdapterError, /no schema/) }
    end
  end

  describe "the Extraction" do
    subject(:extraction) { adapter.call(node, answers) }

    it { is_expected.to be_a(Inquirex::LLM::Extraction) }

    it "keeps TypeSafe's answers, confidences included, as raw" do
      expect(extraction.raw.dig("filing_status", "confidence")).to eq(0.9)
      expect(extraction.raw.dig("income_types__addressed", "confidence")).to eq(0.8)
    end

    its(:usage) { is_expected.to eq(input_tokens: 812, output_tokens: 40) }
  end

  describe "#summarize" do
    it { expect { adapter.summarize(node, "transcript") }.to raise_error(Inquirex::LLM::Errors::AdapterError, /cannot summarize/) }
  end

  describe ".unsupported_fields" do
    it "names the fields of types Jev cannot choose" do
      expect(described_class.unsupported_fields(Inquirex::LLM::Schema.new(a: :string, b: :enum, c: :date)))
        .to eq(%i[a c])
    end
  end

  describe "#initialize" do
    it "reads the key and model from the configuration" do
      with_env("TYPESAFE_API_KEY" => "ts-cfg", "INQUIREX_LLM_JEV_MODEL" => "jev-preview") do
        expect(described_class.new.model).to eq("jev-preview")
      end
    end

    it "raises without a key" do
      with_env("TYPESAFE_API_KEY" => nil) do
        expect { described_class.new }.to raise_error(ArgumentError, /TYPESAFE_API_KEY/)
      end
    end
  end
end
