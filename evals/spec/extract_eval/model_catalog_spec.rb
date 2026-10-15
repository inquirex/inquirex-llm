# frozen_string_literal: true

RSpec.describe ExtractEval::ModelCatalog do
  def contender(model) = ExtractEval::Config::Contender.new(model: model, effort: nil, temperature: nil, max_tokens: 1)

  before do
    allow(described_class).to receive(:fetch).with(described_class::OPENROUTER_URL)
                                             .and_return("data" => [{ "id" => "anthropic/claude-haiku-5.5" }, { "id" => "typesafe/jev-router" }])
    allow(described_class).to receive(:fetch).with(described_class::TYPESAFE_URL, anything)
                                             .and_return("models" => [{ "name" => "jev-latest" }])
  end

  it "passes models both providers list" do
    expect { described_class.verify!([contender("anthropic/claude-haiku-5.5"), contender("typesafe-api/jev-latest")]) }
      .not_to raise_error
  end

  it "names every model its provider does not list" do
    expect { described_class.verify!([contender("anthropic/opus-5.5"), contender("typesafe-api/jev-9")]) }
      .to raise_error(ExtractEval::Error, %r{unknown models anthropic/opus-5\.5, typesafe-api/jev-9})
  end

  it "does not ask TypeSafe when no Jev model runs" do
    described_class.verify!([contender("typesafe/jev-router")])
    expect(described_class).not_to have_received(:fetch).with(described_class::TYPESAFE_URL, anything)
  end

  describe ".fetch" do
    before { allow(described_class).to receive(:fetch).and_call_original }

    it "turns a failed request into an Error" do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, "offline")
      expect { described_class.fetch("https://example.com/models") }
        .to raise_error(ExtractEval::Error, %r{could not list models at https://example.com/models: offline})
    end

    it "turns a non-2xx into an Error" do
      allow(Net::HTTP).to receive(:start).and_return(Net::HTTPUnauthorized.new("1.1", "401", "no"))
      expect { described_class.fetch("https://example.com/models") }.to raise_error(ExtractEval::Error, /HTTP 401/)
    end

    it "parses the list" do
      ok = Net::HTTPOK.new("1.1", "200", "ok")
      allow(ok).to receive(:body).and_return('{"data":[]}')
      allow(Net::HTTP).to receive(:start).and_return(ok)
      expect(described_class.fetch("https://example.com/models")).to eq("data" => [])
    end
  end
end
