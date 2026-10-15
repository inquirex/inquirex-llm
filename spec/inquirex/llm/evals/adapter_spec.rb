# frozen_string_literal: true

require "inquirex/llm/evals"

RSpec.describe Inquirex::LLM::Evals::Adapter do
  subject(:adapter) { described_class.new(root: root) }

  let(:root) { File.expand_path("../../../../evals", __dir__) }
  let(:discovery) { Agent::Evals::Discovery.new(root: root) }
  let(:kase) { discovery.cases(dataset: "05-managed-it-services", only: ["complete"]).first }
  let(:answer) { JSON.generate(kase.expected.merge("compliance" => ["HIPAA"], "work_model" => "office")) }
  let(:model) { Agent::Evals::Testing::FakeModel.new(answers: ->(_user) { answer }) }

  describe "#call" do
    subject(:reply) { adapter.call(kase, model: model) }

    it "asks the model once, with the gem's production prompts" do
      reply
      calls = model.provider.calls
      expect(calls.size).to eq(1)
      expect(calls.first[:system]).to include("data extraction assistant", "seat_count", "use null")
      expect(calls.first[:user]).to include("Task: Extract the company's IT profile", kase.input.inspect)
      expect(calls.first[:json]).to be(true)
    end

    it "returns the canonicalized output and the model's raw values, with String keys" do
      expect(reply.output).to include("compliance" => ["hipaa"], "work_model" => nil, "seat_count" => 45)
      expect(reply.raw).to include("compliance" => ["HIPAA"], "work_model" => "office")
      expect(reply.error?).to be(false)
    end

    it "carries the usage the model reported and the prompts it was sent" do
      expect(reply.usage).to eq(Agent::Evals::Testing::FakeProvider::USAGE)
      expect(reply.metadata[:prompt]).to include(:system, :user)
    end

    context "when the model leaves fields out" do
      let(:answer) { JSON.generate(kase.expected.slice("seat_count")) }

      it "returns the partial answer rather than raising, for the scorer to count" do
        expect(reply.output).to eq("seat_count" => 45)
      end
    end

    context "when the model does not answer with JSON" do
      let(:answer) { "Sure! Here is what I found, in prose." }

      it "is the model's failure: an error reply that keeps the text" do
        expect(reply.error).to include("Failed to parse LLM response as JSON")
        expect(reply.raw).to eq(answer)
        expect(reply.usage).to eq(Agent::Evals::Testing::FakeProvider::USAGE)
      end
    end

    context "when the model answers with a JSON array" do
      let(:answer) { "[1, 2]" }

      it { expect(reply.error).to include("Expected JSON object") }
    end

    context "when the transport fails" do
      let(:model) { Agent::Evals::Testing::FakeModel.new(answers: ->(_) { raise IOError, "connection reset" }) }

      it "raises, so the run counts an error rather than a wrong answer" do
        expect { reply }.to raise_error(IOError, /connection reset/)
      end
    end
  end

  describe "#context" do
    it "hands the scorer the dataset's schema" do
      expect(adapter.context(kase)[:schema]).to eq(described_class.new(root: root).send(:dataset, kase.dataset).node.schema)
    end
  end

  describe "#verify" do
    it "finds nothing wrong with any shipped dataset" do
      expect(discovery.datasets.size).to eq(10)
      expect(discovery.datasets.to_h { [it, adapter.verify(it)] }.reject { |_, v| v.empty? }).to be_empty
    end
  end

  describe "#prepare" do
    it "loads the dataset once, outside the threads" do
      adapter.prepare(kase.dataset)
      prepared = adapter.send(:dataset, kase.dataset)
      expect(adapter.context(kase)[:schema]).to be(prepared.schema)
    end
  end

  describe "#root" do
    it "is the configured suite's root when none is given" do
      allow(Agent::Evals.configuration).to receive(:root).and_return("/elsewhere")
      expect(described_class.new.root).to eq("/elsewhere")
    end
  end

  its(:metadata) { is_expected.to eq(prompt: "Inquirex::LLM::OpenAIAdapter", 'inquirex-llm': Inquirex::LLM::VERSION) }
end
