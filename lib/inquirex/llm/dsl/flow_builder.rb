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
        # Accumulator added when a flow declares `summarize` without declaring
        # anywhere for the narrative to accumulate.
        TRANSCRIPT_ACCUMULATOR = :transcript

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

        # Closes the flow with a prose summary of the whole session.
        #
        # Takes no prompt (the gem owns it — see {Prompts::SUMMARIZE}), no
        # schema, and no `from`: its input is always the session transcript,
        # and its output is markdown for the user to read, keep, and print.
        # It must be the last step declared in the flow, and a flow may
        # declare only one.
        #
        # Declaring it also guarantees the flow has somewhere to summarise
        # *from*: if no `:text` accumulator was declared, a `:transcript` one
        # is added automatically.
        #
        # @example
        #   summarize :wrap_up do
        #     temperature 0.4
        #   end
        #
        # @param id [Symbol] step id
        def summarize(id, &)
          add_llm_step(id, :summarize, &)
        end

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
          validate_summarize_placement!
          ensure_transcript_accumulator!
          resolve_llm_steps!
          super
        end

        private

        # @return [Array<Symbol>] ids of the flow's summarize steps, in
        #   declaration order
        def summarize_step_ids
          @nodes.filter_map { |id, entry| id if summarize_entry?(entry) }
        end

        # True for a parked LlmStepBuilder or an already-built node whose verb
        # is :summarize.
        def summarize_entry?(entry)
          entry.respond_to?(:verb) ? entry.verb.to_sym == :summarize : entry.instance_variable_get(:@verb) == :summarize
        end

        # `summarize` closes the flow, so it has to be the last step declared
        # and there can only be one. Checked here rather than in the step
        # builder because only the flow builder knows the declaration order —
        # the step builder sees one step at a time.
        #
        # @raise [Errors::DefinitionError]
        def validate_summarize_placement!
          ids = summarize_step_ids
          return if ids.empty?

          if ids.length > 1
            raise Errors::DefinitionError,
              "flow declares #{ids.length} summarize steps (#{ids.map(&:inspect).join(", ")}) — " \
              "a flow may close with only one"
          end

          last_id = @nodes.keys.last
          return if ids.first == last_id

          raise Errors::DefinitionError,
            "summarize step #{ids.first.inspect} is followed by #{last_id.inspect} — " \
            "summarize must be the last step declared in the flow"
        end

        # Guarantees a `summarize` flow has a narrative to summarise. A flow
        # that mostly explains things collects almost no answers, so without a
        # text accumulator there would be nothing to send the model but an
        # empty hash.
        def ensure_transcript_accumulator!
          return if summarize_step_ids.empty?
          return if @accumulators.any? { |_, acc| text_accumulator?(acc) }

          accumulator(TRANSCRIPT_ACCUMULATOR, type: :text)
        end

        # `Accumulator#text?` arrived with text accumulators; fall back to the
        # type for the older core versions this gem still supports.
        def text_accumulator?(acc)
          acc.respond_to?(:text?) ? acc.text? : acc.type.to_sym == :text
        end

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
