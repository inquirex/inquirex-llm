# frozen_string_literal: true

require "rspec"
require "rspec/its"
require "net/http"

RSpec.describe Inquirex::LLM::AnthropicAdapter do
  let(:api_key) { "test-key-xyz" }
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

  let(:answers) { { tell_me: "I'm MFJ with two kids in CA and an LLC." } }

  describe "#initialize" do
    context "with an explicit api_key" do
      subject(:adapter) { described_class.new(api_key: api_key) }

      it { is_expected.to be_a(Inquirex::LLM::Adapter) }
    end

    context "with neither api_key nor env var" do
      around do |ex|
        prior = ENV.delete("ANTHROPIC_API_KEY")
        ex.run
        ENV["ANTHROPIC_API_KEY"] = prior if prior
      end

      it "raises ArgumentError" do
        expect { described_class.new }.to raise_error(ArgumentError, /ANTHROPIC_API_KEY/)
      end
    end

    context "with the env var set" do
      around do |ex|
        prior = ENV.fetch("ANTHROPIC_API_KEY", nil)
        ENV["ANTHROPIC_API_KEY"] = "env-key"
        ex.run
        prior ? ENV["ANTHROPIC_API_KEY"] = prior : ENV.delete("ANTHROPIC_API_KEY")
      end

      it "does not raise" do
        expect { described_class.new }.not_to raise_error
      end
    end
  end

  describe "private helpers" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    describe "#resolve_model" do
      it "maps :claude_sonnet to the concrete model id" do
        expect(adapter.send(:resolve_model, clarify_node))
          .to eq("claude-sonnet-4-20250514")
      end

      it "falls back to the default when the node has no model" do
        node = Inquirex::LLM::Node.new(
          id: :x, verb: :clarify, prompt: "p", schema: schema, from_steps: [:a]
        )
        expect(adapter.send(:resolve_model, node)).to eq(described_class::DEFAULT_MODEL)
      end

      it "honours the instance default_model override" do
        custom = described_class.new(api_key: api_key, model: "claude-opus-4-20250514")
        node = Inquirex::LLM::Node.new(
          id: :x, verb: :clarify, prompt: "p", schema: schema, from_steps: [:a]
        )
        expect(custom.send(:resolve_model, node)).to eq("claude-opus-4-20250514")
      end
    end

    describe "#build_system_prompt" do
      it "includes the schema JSON when the node has a schema" do
        text = adapter.send(:build_system_prompt, clarify_node)
        expect(text).to include('"filing_status": "string"')
        expect(text).to include('"dependents": "integer"')
        expect(text).to include("No markdown fences")
      end

      it "emits the no-schema instruction for summarize" do
        text = adapter.send(:build_system_prompt, summarize_node)
        expect(text).to include("valid JSON object containing your analysis")
      end
    end

    describe "#build_user_prompt" do
      subject(:text) { adapter.send(:build_user_prompt, clarify_node, { tell_me: "MFJ two kids" }, answers) }

      it { is_expected.to include("Task: Extract tax intake fields") }
      it { is_expected.to include("tell_me: \"MFJ two kids\"") }
      it { is_expected.to include("filing_status (string)") }
      it { is_expected.to include("dependents (integer)") }

      it "includes all answers for summarize when from_all is set" do
        all_answers = { tell_me: "x", filing_status: "single" }
        out = adapter.send(:build_user_prompt, summarize_node, {}, all_answers)
        expect(out).to include("All collected answers:")
        expect(out).to include("filing_status: \"single\"")
      end
    end

    describe "#parse_response" do
      it "parses a plain JSON text block" do
        api = { "content" => [{ "type" => "text", "text" => '{"filing_status":"single","dependents":2}' }] }
        expect(adapter.send(:parse_response, api))
          .to eq(filing_status: "single", dependents: 2)
      end

      it "strips ```json fences" do
        fenced = "```json\n{\"a\":1}\n```"
        api = { "content" => [{ "type" => "text", "text" => fenced }] }
        expect(adapter.send(:parse_response, api)).to eq(a: 1)
      end

      it "raises AdapterError when content has no text block" do
        api = { "content" => [{ "type" => "image" }] }
        expect { adapter.send(:parse_response, api) }
          .to raise_error(Inquirex::LLM::Errors::AdapterError, /No text content/)
      end

      it "raises AdapterError on malformed JSON" do
        api = { "content" => [{ "type" => "text", "text" => "not json" }] }
        expect { adapter.send(:parse_response, api) }
          .to raise_error(Inquirex::LLM::Errors::AdapterError, /Failed to parse/)
      end

      it "raises AdapterError when JSON root is not an object" do
        api = { "content" => [{ "type" => "text", "text" => "[1,2,3]" }] }
        expect { adapter.send(:parse_response, api) }
          .to raise_error(Inquirex::LLM::Errors::AdapterError, /Expected JSON object/)
      end
    end
  end

  describe "#call (http stubbed)" do
    subject(:adapter) { described_class.new(api_key: api_key) }

    let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, :read_timeout= => nil, :open_timeout= => nil) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(http)
    end

    def ok(body)
      instance_double(Net::HTTPOK, is_a?: true, body: JSON.generate(body), code: "200")
    end

    def err(code, body)
      double = instance_double(Net::HTTPBadRequest, body: body, code: code.to_s)
      allow(double).to receive(:is_a?).and_return(false)
      double
    end

    it "sends a well-formed request and returns the parsed schema-conformant hash" do
      captured = nil
      allow(http).to receive(:request) do |req|
        captured = req
        ok("content" => [{ "type" => "text", "text" => '{"filing_status":"single","dependents":2}' }])
      end

      result = adapter.call(clarify_node, answers)

      expect(result).to eq(filing_status: "single", dependents: 2)
      expect(captured["x-api-key"]).to eq(api_key)
      expect(captured["anthropic-version"]).to eq(described_class::API_VERSION)
      body = JSON.parse(captured.body)
      expect(body["model"]).to eq("claude-sonnet-4-20250514")
      expect(body["temperature"]).to eq(0.1)
      expect(body["max_tokens"]).to eq(1024)
      expect(body["messages"].first["role"]).to eq("user")
      expect(body["system"]).to include("filing_status")
    end

    it "raises AdapterError on non-2xx responses" do
      allow(http).to receive(:request).and_return(err(429, '{"error":"rate limit"}'))

      expect { adapter.call(clarify_node, answers) }
        .to raise_error(Inquirex::LLM::Errors::AdapterError, /429/)
    end

    it "raises SchemaViolationError when the LLM omits required fields" do
      allow(http).to receive(:request).and_return(
        ok("content" => [{ "type" => "text", "text" => '{"filing_status":"single"}' }])
      )

      expect { adapter.call(clarify_node, answers) }
        .to raise_error(Inquirex::LLM::Errors::SchemaViolationError, /dependents/)
    end

    it "uses default max_tokens when the node does not specify one" do
      node = Inquirex::LLM::Node.new(
        id: :x, verb: :clarify, prompt: "p", schema: schema, from_steps: [:tell_me]
      )
      captured = nil
      allow(http).to receive(:request) do |req|
        captured = req
        ok("content" => [{ "type" => "text", "text" => '{"filing_status":"x","dependents":0}' }])
      end

      adapter.call(node, answers)

      expect(JSON.parse(captured.body)["max_tokens"]).to eq(described_class::DEFAULT_MAX_TOKENS)
    end
  end
end
