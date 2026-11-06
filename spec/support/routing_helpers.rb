# frozen_string_literal: true

require "stringio"

# Stand-ins for the network and the terminal in routing specs.
module RoutingHelpers
  # Answers {Inquirex::LLM::Routing::Catalog#fetch} from a Hash: a provider
  # mapped to model ids lists them; one mapped to an exception raises it.
  class FakeCatalog
    attr_reader :fetched

    # @param catalogs [Hash{Symbol => Array<String>, Exception}]
    def initialize(catalogs)
      @catalogs = catalogs
      @fetched = []
    end

    def fetch(provider, _api_key)
      @fetched << provider
      entry = @catalogs.fetch(provider) { raise Inquirex::LLM::Errors::AdapterError, "#{provider}: no catalog" }
      raise entry if entry.is_a?(Exception)

      entry.to_set
    end
  end

  # Every key set; tests narrow it with `keys:`.
  ALL_KEYS = {
    "OPENROUTER_API_KEY" => "or-key",
    "OPENAI_API_KEY"     => "oa-key",
    "ANTHROPIC_API_KEY"  => "an-key",
    "TYPESAFE_API_KEY"   => "ts-key"
  }.freeze

  # Catalogs that list a little of everything.
  CATALOGS = {
    openrouter: %w[deepseek/deepseek-v4.1-flash anthropic/claude-haiku-5.5 openai/gpt-4.1-mini typesafe/jev-router],
    openai:     %w[gpt-4.1-mini gpt-4o],
    anthropic:  %w[claude-haiku-5-5 claude-sonnet-5-5-20261001],
    typesafe:   %w[jev-latest]
  }.freeze

  # A Configuration read from a fake environment, with routing settings applied.
  def routing_config(keys: ALL_KEYS, vendors: %i[openrouter openai anthropic typesafe], models: [], **settings)
    Inquirex::LLM::Configuration.new(keys).tap do |config|
      config.llm_vendors_priority = vendors
      config.llm_models_priority = models
      settings.each { |name, value| config.public_send(:"#{name}=", value) }
    end
  end

  def console_io = @console_io ||= StringIO.new
  def console = Inquirex::LLM::Routing::Console.new(console_io)
end

RSpec.configure { |config| config.include RoutingHelpers }
