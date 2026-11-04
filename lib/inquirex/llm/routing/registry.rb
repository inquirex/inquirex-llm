# frozen_string_literal: true

module Inquirex
  module LLM
    module Routing
      # The vendors and models this Ruby process can actually use, settled
      # once by {#ensure!}: a vendor needs its API key and a catalog that
      # downloads; a model needs a surviving vendor that lists it. What is
      # removed stays removed for the life of the process.
      class Registry
        # The environment variable each vendor's key comes from, for messages.
        KEY_VARIABLES = {
          openrouter: "OPENROUTER_API_KEY",
          openai:     "OPENAI_API_KEY",
          anthropic:  "ANTHROPIC_API_KEY",
          typesafe:   "TYPESAFE_API_KEY"
        }.freeze

        # @return [Array<Symbol>] usable vendors, in priority order
        attr_reader :vendors
        # @return [Array<String>] usable "vendor/model" names, in priority order
        attr_reader :models

        # @param config [Configuration]
        # @param catalog [#fetch] downloads one provider's model ids
        # @param console [Console]
        def initialize(config, catalog: Catalog.new, console: Console.new)
          @config = config
          @catalog = catalog
          @console = console
          @catalogs = {}
          @adapters = {}
        end

        # @return [self]
        # @raise [Errors::MissingProviderAPIKeysError] when no vendor is usable
        # @raise [Errors::NoAvailableModelsError] when no model is servable
        def ensure!
          @vendors = usable_vendors
          @adapters = @vendors.to_h { |vendor| [vendor, build_adapter(vendor)] }
          @models = servable_models
          self
        end

        # The route for one model, or nil when no usable vendor serves it.
        #
        # @param model [String] "vendor/model"
        # @param verb [Symbol] :extract or :summarize
        # @param node [Node, nil] the step, which decides whether Jev can answer it
        # @return [Route, nil]
        def route_for(model, verb: :extract, node: nil)
          id = ModelId.parse(model)
          @vendors.each do |vendor|
            route = route_via(vendor, id, verb, node)
            return route if route
          end
          nil
        end

        private

        def route_via(vendor, id, verb, node)
          if vendor == :openrouter
            return unless @catalogs[:openrouter].include?(id.to_s)

            Route.new(model: id.to_s, provider: :openrouter, native_id: id.to_s, adapter: @adapters[:openrouter])
          elsif vendor == id.native_provider
            return unless listed?(vendor, id.native_id)
            return if vendor == :typesafe && !jev_can_answer?(verb, node)

            Route.new(model: id.to_s, provider: vendor, native_id: id.native_id, adapter: @adapters[vendor])
          end
        end

        # Anthropic also lists dated snapshots ("claude-haiku-5-5-20261001").
        def listed?(vendor, native_id)
          ids = @catalogs[vendor]
          ids.include?(native_id) || ids.any? { |id| id.start_with?("#{native_id}-") }
        end

        # Jev chooses and cannot write: only an extract whose every field it can answer.
        def jev_can_answer?(verb, node)
          return false unless verb == :extract
          return true if node.nil? # checking availability, not a specific step

          node.respond_to?(:schema) && node.schema && JevAdapter.unsupported_fields(node.schema).empty?
        end

        def usable_vendors
          listed = @config.llm_vendors_priority
          keyed = listed.select { |vendor| key?(vendor) }
          fetched = download_catalogs(keyed)
          usable = keyed.select { |vendor| fetched.include?(vendor) }
          raise Errors::MissingProviderAPIKeysError, no_vendors_message(listed) if usable.empty?

          @console.info("LLM vendors in use, by priority: #{usable.join(", ")}") if usable != listed
          usable
        end

        def key?(vendor)
          return true if api_key(vendor)

          @console.warn("#{vendor} is in llm_vendors_priority, but #{KEY_VARIABLES.fetch(vendor)} is not set; skipping it")
          false
        end

        # All catalogs at once, so boot waits for the slowest, not the sum.
        def download_catalogs(vendors)
          threads = vendors.to_h do |vendor|
            thread = Thread.new do
              Thread.current.report_on_exception = false # the error is reported below, as a warning
              @catalog.fetch(vendor, api_key(vendor))
            end
            [vendor, thread]
          end
          threads.each_with_object([]) do |(vendor, thread), ok|
            @catalogs[vendor] = thread.value
            ok << vendor
          rescue StandardError => e
            @console.warn("#{vendor}'s model catalog could not be downloaded (#{e.message}); " \
                          "skipping #{vendor} until this process restarts")
          end
        end

        def servable_models
          servable = @config.llm_models_priority.select do |model|
            next true if route_for(model)

            @console.warn("#{model} is in llm_models_priority, but no usable vendor serves it; skipping it")
            false
          end
          raise Errors::NoAvailableModelsError, no_models_message if servable.empty?

          servable
        end

        def api_key(vendor) = @config.public_send(:"#{vendor}_api_key")

        def build_adapter(vendor)
          key = api_key(vendor)
          case vendor
          when :openrouter then OpenRouterAdapter.new(api_key: key)
          when :openai     then OpenAIAdapter.new(api_key: key)
          when :anthropic  then AnthropicAdapter.new(api_key: key)
          when :typesafe   then JevAdapter.new(api_key: key)
          end
        end

        def no_vendors_message(listed)
          "None of llm_vendors_priority (#{listed.join(", ")}) is usable: set at least one of " \
            "#{listed.map { |vendor| KEY_VARIABLES.fetch(vendor) }.join(", ")}, and make sure its model catalog is reachable"
        end

        def no_models_message
          models = @config.llm_models_priority
          listed = models.empty? ? "llm_models_priority is empty" : "none of #{models.join(", ")}"
          "No model is available: #{listed} is served by the usable vendors (#{@vendors.join(", ")})"
        end
      end
    end
  end
end
