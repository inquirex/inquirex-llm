# frozen_string_literal: true

require "rspec"
require "rspec/its"
require "net/http"

RSpec.describe Inquirex::LLM::OpenAIAdapter do
  let(:api_key) { "test-openai-key" }
  let(:schema)  { Inquirex::LLM::Schema.new(filing_status: :string, dependents: :integer) }

  let(:clarify_node) do
    Inquirex::LLM::Node.new(
      id:          :extracted,
      verb:        :clarify,
      prompt:      "Extract tax intake fields from the client's description.",
      schema:      schema,
      from_steps:  [:tell_me],
      model:       :claude_sonnet,
      temperature: 0.1,
      max_tokens:  1024
    )
  end

  let(:summarize_node) do
    Inquirex::LLM::Node.new(
      id:       :summary,
      verb:     :summarize,
      prompt:   "Summarize intake.",
      from_all: true
    )
  end

  let(:answers) { { tell_me: "MFJ two kids CA LLC rental coinbase" } }

  describe "#initialize" do
    context "with an explicit api_key" do
      subject(:adapter) { described_class.new(api_key: api_key) }

      it { is_expected.to be_a(Inquirex::LLM::Adapter) }
    end

    context "with neither api_key nor env var" do
      around do |ex|
        prior = ENV.delete("OPENAI_API_KEY")
        ex.run
        ENV["OPENAI_API_KEY"] = prior if prior
      end

      it "raises ArgumentError" do
        expect { described_class.new }.to raise_error(ArgumentError, /OPENAI_API_KEY/)
      end
    end
  end

  describe "#resolve_model" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    it "maps Claude symbols to GPT equivalents for cross-provider flow files" do
      expect(adapter.send(:resolve_model, clarify_node)).to eq("gpt-4o")
    end

    it "maps gpt_4o_mini symbol to the concrete id" do
      node = Inquirex::LLM::Node.new(id: :x, verb: :clarify, prompt: "p", schema: schema, from_steps: [:a], model: :gpt_4o_mini)
      expect(adapter.send(:resolve_model, node)).to eq("gpt-4o-mini")
    end

    it "falls back to the default when the node has no model" do
      node = Inquirex::LLM::Node.new(id: :x, verb: :clarify, prompt: "p", schema: schema, from_steps: [:a])
      expect(adapter.send(:resolve_model, node)).to eq(described_class::DEFAULT_MODEL)
    end
  end

  describe "#build_system_prompt" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    it "includes the schema JSON for clarify" do
      text = adapter.send(:build_system_prompt, clarify_node)
      expect(text).to include('"filing_status": "string"')
      expect(text).to include("JSON object")
    end

    it "does not include a schema block for summarize" do
      text = adapter.send(:build_system_prompt, summarize_node)
      expect(text).not_to include("MUST match this schema")
      expect(text).to include("JSON object")
    end
  end

  describe "#build_user_prompt" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    it "includes task, source, schema fields, and the return instruction" do
      text = adapter.send(:build_user_prompt, clarify_node, { tell_me: "hi" }, answers)
      expect(text).to include("Task: Extract tax intake fields")
      expect(text).to include("tell_me: \"hi\"")
      expect(text).to include("filing_status (string)")
      expect(text).to include("Return ONLY the JSON object.")
    end

    it "includes all answers for summarize with from_all" do
      text = adapter.send(:build_user_prompt, summarize_node, {}, answers)
      expect(text).to include("All collected answers:")
      expect(text).to include("tell_me:")
    end
  end

  describe "#parse_response" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    it "parses a plain JSON assistant message" do
      api = { "choices" => [{ "message" => { "content" => '{"filing_status":"single","dependents":2}' } }] }
      expect(adapter.send(:parse_response, api)).to eq(filing_status: "single", dependents: 2)
    end

    it "strips ```json fences" do
      api = { "choices" => [{ "message" => { "content" => "```json\n{\"a\":1}\n```" } }] }
      expect(adapter.send(:parse_response, api)).to eq(a: 1)
    end

    it "raises AdapterError when there is no choice/message" do
      api = { "choices" => [] }
      expect { adapter.send(:parse_response, api) }
        .to raise_error(Inquirex::LLM::Errors::AdapterError, /No message content/)
    end

    it "raises AdapterError on malformed JSON" do
      api = { "choices" => [{ "message" => { "content" => "not json" } }] }
      expect { adapter.send(:parse_response, api) }
        .to raise_error(Inquirex::LLM::Errors::AdapterError, /Failed to parse/)
    end

    it "raises AdapterError when JSON is not an object" do
      api = { "choices" => [{ "message" => { "content" => "[1,2,3]" } }] }
      expect { adapter.send(:parse_response, api) }
        .to raise_error(Inquirex::LLM::Errors::AdapterError, /Expected JSON object/)
    end
  end

  describe "#call (http stubbed)" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, :read_timeout= => nil, :open_timeout= => nil) }

    before { allow(Net::HTTP).to receive(:new).and_return(http) }

    def ok(message_text)
      resp = instance_double(Net::HTTPOK, body: JSON.generate("choices" => [{ "message" => { "content" => message_text } }]))
      allow(resp).to receive(:is_a?).and_return(true)
      resp
    end

    def err(code, body)
      resp = instance_double(Net::HTTPBadRequest, body: body, code: code.to_s)
      allow(resp).to receive(:is_a?).and_return(false)
      resp
    end

    it "sends auth header, json_object response format, and returns parsed hash" do
      captured = nil
      allow(http).to receive(:request) do |req|
        captured = req
        ok('{"filing_status":"single","dependents":2}')
      end

      result = adapter.call(clarify_node, answers)

      expect(result).to eq(filing_status: "single", dependents: 2)
      expect(captured["Authorization"]).to eq("Bearer #{api_key}")
      body = JSON.parse(captured.body)
      expect(body["model"]).to eq("gpt-4o")
      expect(body["response_format"]).to eq("type" => "json_object")
      expect(body["messages"].map { |m| m["role"] }).to eq(%w[system user])
    end

    it "raises AdapterError on non-2xx" do
      allow(http).to receive(:request).and_return(err(429, '{"error":"rate limit"}'))
      expect { adapter.call(clarify_node, answers) }
        .to raise_error(Inquirex::LLM::Errors::AdapterError, /429/)
    end

    it "raises SchemaViolationError when a schema field is missing" do
      allow(http).to receive(:request).and_return(ok('{"filing_status":"single"}'))
      expect { adapter.call(clarify_node, answers) }
        .to raise_error(Inquirex::LLM::Errors::SchemaViolationError, /dependents/)
    end
  end
end
