# frozen_string_literal: true

require "json"
require "net/http"

module ExtractEval
  # The models each provider actually serves, read from its model list, so a
  # misspelled id aborts the run before any experiment starts, instead of
  # failing every case and showing up as a row of errors.
  module ModelCatalog
    OPENROUTER_URL = "https://openrouter.ai/api/v1/models"
    TYPESAFE_URL = "https://api.typesafe.ai/v1/models"

    module_function

    # @param contenders [Array<Config::Contender>]
    # @return [void]
    # @raise [Error] naming every model its provider does not list, or a list that could not be read
    def verify!(contenders)
      models = contenders.map(&:model).uniq
      jev, router = models.partition { JevAdapter.serves?(it) }
      unknown = (router - available(router, :openrouter)) +
                jev.reject { available(jev, :typesafe).include?(it.delete_prefix(JevAdapter::PREFIX)) }
      return if unknown.empty?

      raise Error,
        "unknown model#{"s" if unknown.size > 1} #{unknown.join(", ")}: not listed by " \
        "#{OPENROUTER_URL} or #{TYPESAFE_URL}; check the id in config.yml or -m"
    end

    # @return [Array<String>] the provider's model ids; none fetched when nothing needs them
    def available(needed, provider)
      return [] if needed.empty?

      provider == :openrouter ? fetch(OPENROUTER_URL).fetch("data").map { it.fetch("id") } : typesafe_models
    end

    def typesafe_models
      fetch(TYPESAFE_URL, "Authorization" => "Bearer #{ENV.fetch("TYPESAFE_API_KEY", nil)}")
        .fetch("models").map { it.fetch("name") }
    end

    # @return [Hash]
    # @raise [Error] when the list cannot be read
    def fetch(url, headers = {})
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) do |http|
        http.request(Net::HTTP::Get.new(uri, headers))
      end
      raise Error, "could not list models at #{url}: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, JSON::ParserError, KeyError => e
      raise Error, "could not list models at #{url}: #{e.message}"
    end
  end
end
