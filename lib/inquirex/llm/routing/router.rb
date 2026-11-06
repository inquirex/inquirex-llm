# frozen_string_literal: true

module Inquirex
  module LLM
    module Routing
      # Picks the model for one LLM step: the first model in the step's own
      # list that a usable vendor serves, else the first in the global
      # llm_models_priority. The choice is cached per step for the life of
      # the process.
      class Router
        # @return [Registry] the vendors and models this router chooses from
        attr_reader :registry

        # @param config [Configuration]
        # @param registry [Registry] already ensured
        # @param console [Console]
        def initialize(config, registry, console: Console.new)
          @config = config
          @registry = registry
          @console = console
          @routes = {}.compare_by_identity
          @lock = Mutex.new
        end

        # @param node [Node] the LLM step
        # @param verb [Symbol] :extract or :summarize
        # @return [Route]
        # @raise [Errors::NoAvailableModelsError] when no model can serve the step
        def route(node, verb: node.verb)
          @lock.synchronize do
            (@routes[node] ||= {})[verb.to_sym] ||= choose(node, verb.to_sym)
          end
        end

        private

        def choose(node, verb)
          wanted = candidates(node)
          wanted.each do |model|
            route = @registry.route_for(model, verb:, node:)
            return route if route
          end
          unless wanted.empty?
            @console.warn("step #{node.id.inspect}: no usable vendor serves #{wanted.join(", ")}; " \
                          "falling back to llm_models_priority")
          end
          fallback(node, verb)
        end

        def fallback(node, verb)
          @registry.models.each do |model|
            route = @registry.route_for(model, verb:, node:)
            return route if route
          end
          raise Errors::NoAvailableModelsError,
            "no available model can serve #{verb} step #{node.id.inspect} (tried #{@registry.models.join(", ")})"
        end

        # The step's own models, after the two dsl_* policies.
        def candidates(node)
          models = step_models(node)
          models &= @config.llm_models_priority unless @config.dsl_can_use_unlisted_models
          models = @config.llm_models_priority & models unless @config.dsl_can_reprioritize
          models
        end

        # `use_first_available_model` wins; an old `model :symbol` hint is a
        # one-entry list; neither means the global list alone.
        def step_models(node)
          listed = node.respond_to?(:models) ? node.models : []
          return listed unless listed.empty?

          hint = node.respond_to?(:model) ? ModelId.from_hint(node.model) : nil
          hint ? [hint] : []
        end
      end
    end
  end
end
