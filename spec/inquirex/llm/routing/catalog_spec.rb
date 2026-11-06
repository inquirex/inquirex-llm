# frozen_string_literal: true

RSpec.describe Inquirex::LLM::Routing::Catalog do
  subject(:catalog) { described_class.new(timeout: 1) }

  let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, :open_timeout= => nil, :read_timeout= => nil) }
  let(:requests) { [] }
  let(:response) { ok(JSON.generate("data" => [{ "id" => "gpt-4o" }, { "id" => "gpt-4.1-mini" }, { "name" => "no id" }])) }

  def ok(body) = instance_double(Net::HTTPOK, is_a?: true, body: body, code: "200")

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:request) { |request| (requests << request) && response }
  end

  it "returns the ids the provider lists" do
    expect(catalog.fetch(:openai, "oa-key")).to eq(Set["gpt-4o", "gpt-4.1-mini"])
  end

  it "sends a bearer token to OpenAI-style providers" do
    catalog.fetch(:openrouter, "or-key")
    expect(requests.first).to have_attributes(path: "/api/v1/models")
    expect(requests.first["Authorization"]).to eq("Bearer or-key")
  end

  it "sends Anthropic's key and version headers, asking for every model" do
    catalog.fetch(:anthropic, "an-key")
    expect(requests.first.path).to eq("/v1/models?limit=1000")
    expect([requests.first["x-api-key"], requests.first["anthropic-version"]]).to eq(%w[an-key 2023-06-01])
  end

  context "when the provider answers an error" do
    let(:response) { instance_double(Net::HTTPServiceUnavailable, is_a?: false, code: "503") }

    it "raises AdapterError naming the provider and status" do
      expect { catalog.fetch(:openai, "k") }.to raise_error(Inquirex::LLM::Errors::AdapterError, /openai catalog: HTTP 503/)
    end
  end

  context "when the body is not JSON" do
    let(:response) { ok("<html>") }

    it "raises AdapterError" do
      expect { catalog.fetch(:openai, "k") }.to raise_error(Inquirex::LLM::Errors::AdapterError, /JSON::ParserError/)
    end
  end

  context "when the body has no data list" do
    let(:response) { ok(JSON.generate("models" => [])) }

    it "raises AdapterError" do
      expect { catalog.fetch(:openai, "k") }.to raise_error(Inquirex::LLM::Errors::AdapterError, /no "data" list/)
    end
  end

  context "when the request times out" do
    before { allow(http).to receive(:request).and_raise(Net::OpenTimeout, "execution expired") }

    it "raises AdapterError" do
      expect { catalog.fetch(:openai, "k") }.to raise_error(Inquirex::LLM::Errors::AdapterError, /Net::OpenTimeout/)
    end
  end
end
