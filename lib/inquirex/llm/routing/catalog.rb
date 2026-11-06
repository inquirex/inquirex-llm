# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Inquirex
  module LLM
    module Routing
      # Downloads the model ids each provider serves, so a model is accepted
      # only when its provider really lists it. One GET per provider; every
      # failure (no answer in time, non-2xx, unreadable body) raises
      # {Errors::AdapterError}, and the caller drops that provider.
      class Catalog
        # Seconds to wait for a catalog, connecting and reading.
        TIMEOUT = 5

        # Each provider's model list.
        ENDPOINTS = {
          openrouter: "https://openrouter.ai/api/v1/models",
          openai:     "https://api.openai.com/v1/models",
          anthropic:  "https://api.anthropic.com/v1/models?limit=1000",
          typesafe:   "https://api.typesafe.ai/v1/models"
        }.freeze

        # @param timeout [Numeric] seconds per request
        def initialize(timeout: TIMEOUT)
          @timeout = timeout
        end

        # @param provider [Symbol] a key of {ENDPOINTS}
        # @param api_key [String]
        # @return [Set<String>] the model ids the provider lists
        # @raise [Errors::AdapterError] when the catalog cannot be read
        def fetch(provider, api_key)
          uri = URI(ENDPOINTS.fetch(provider))
          response = get(uri, headers(provider, api_key))
          raise Errors::AdapterError, "#{provider} catalog: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

          ids(JSON.parse(response.body))
        rescue JSON::ParserError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError => e
          raise Errors::AdapterError, "#{provider} catalog: #{e.class}: #{e.message}"
        end

        private

        def get(uri, headers)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.open_timeout = @timeout
          http.read_timeout = @timeout
          request = Net::HTTP::Get.new(uri)
          headers.each { |name, value| request[name] = value }
          http.request(request)
        end

        def headers(provider, api_key)
          case provider
          when :anthropic then { "x-api-key" => api_key, "anthropic-version" => "2023-06-01" }
          else { "Authorization" => "Bearer #{api_key}" }
          end
        end

        # Every provider here answers `{ "data": [{ "id": ... }, ...] }`.
        def ids(body)
          data = body.is_a?(Hash) ? body["data"] : nil
          raise Errors::AdapterError, "catalog has no \"data\" list" unless data.is_a?(Array)

          data.filter_map { |entry| entry["id"].to_s if entry.is_a?(Hash) && entry["id"] }.to_set
        end
      end
    end
  end
end
