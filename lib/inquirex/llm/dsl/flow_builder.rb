# frozen_string_literal: true

module Inquirex
  module LLM
    module DSL
      # Mixin that adds LLM verb methods to Inquirex::DSL::FlowBuilder.
      # Included automatically when `require "inquirex-llm"` is called,
      # so that `Inquirex.define` gains clarify/describe/summarize/detour
      # without needing a separate entry point.
      #
      # All core verbs (ask, say, header, btw, warning, confirm) remain
      # unchanged — LLM verbs are purely additive.
      module FlowBuilderExtension
        # Defines an LLM extraction step: takes free-text input and produces
        # structured data matching the declared schema.
        #
        # @param id [Symbol] step id
        def clarify(id, &)
          add_llm_step(id, :clarify, &)
        end

        # Defines an LLM description step: takes structured data and produces
        # natural-language text.
        #
        # @param id [Symbol] step id
        def describe(id, &)
          add_llm_step(id, :describe, &)
        end

        # Defines an LLM summarization step: takes all or selected answers and
        # produces a textual summary.
        #
        # @param id [Symbol] step id
        def summarize(id, &)
          add_llm_step(id, :summarize, &)
        end

        # Defines an LLM detour step: based on an answer, dynamically generates
        # follow-up questions. The server adapter handles presenting the generated
        # questions and collecting responses.
        #
        # @param id [Symbol] step id
        def detour(id, &)
          add_llm_step(id, :detour, &)
        end

        private

        # Uses the standard Ruby builder pattern (same as core FlowBuilder#add_step).
        def add_llm_step(id, verb, &block)
          builder = LlmStepBuilder.new(verb)
          builder.instance_eval(&block) if block
          @nodes[id.to_sym] = builder.build(id)
        end
      end
    end
  end
end
