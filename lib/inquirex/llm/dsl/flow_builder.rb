# frozen_string_literal: true

module Inquirex
  module LLM
    module DSL
      # Mixin that adds LLM verb methods to Inquirex::DSL::FlowBuilder.
      # Prepended automatically when `require "inquirex-llm"` is called,
      # so that `Inquirex.define` gains `extract` (and its `clarify` alias)
      # without needing a separate entry point.
      #
      # All core verbs (ask, say, header, btw, warning, confirm) remain
      # unchanged — LLM verbs are purely additive. The mixin must be
      # prepended (not included) because it overrides #build: LLM steps are
      # built lazily at #build time, once every step in the flow is known,
      # so that schema question references can resolve forward to questions
      # defined after the LLM step.
      module FlowBuilderExtension
        # Defines an LLM extraction step: takes free-text input and produces
        # structured data matching the declared schema.
        #
        # @param id [Symbol] step id
        def extract(id, &)
          add_llm_step(id, :extract, &)
        end

        alias clarify extract

        # # Defines an LLM description step: takes structured data and produces
        # # natural-language text.
        # #
        # # @param id [Symbol] step id
        # def describe(id, &)
        #   add_llm_step(id, :describe, &)
        # end

        # # Defines an LLM summarization step: takes all or selected answers and
        # # produces a textual summary.
        # #
        # # @param id [Symbol] step id
        # def summarize(id, &)
        #   add_llm_step(id, :summarize, &)
        # end

        # # Defines an LLM detour step: based on an answer, dynamically generates
        # # follow-up questions. The server adapter handles presenting the generated
        # # questions and collecting responses.
        # #
        # # @param id [Symbol] step id
        # def detour(id, &)
        #   add_llm_step(id, :detour, &)
        # end

        # Builds any deferred LLM steps (now that the full node map exists),
        # then produces the frozen Definition via the core builder.
        def build
          resolve_llm_steps!
          super
        end

        private

        # Evaluates the step block immediately (same as core FlowBuilder#add_step)
        # but parks the builder in the node map instead of building the node.
        # The builder placeholder holds this step's position; #build replaces it.
        def add_llm_step(id, verb, &block)
          builder = LlmStepBuilder.new(verb)
          builder.instance_eval(&block) if block
          @nodes[id.to_sym] = builder
        end

        def resolve_llm_steps!
          @nodes.each do |id, entry|
            @nodes[id] = entry.build(id, nodes: @nodes) if entry.is_a?(LlmStepBuilder)
          end
        end
      end
    end
  end
end
