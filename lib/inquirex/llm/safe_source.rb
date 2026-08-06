# frozen_string_literal: true

module Inquirex
  module LLM
    # Teaches {Inquirex::SafeSource}'s allowlist about this gem's verbs.
    #
    # Since inquirex 0.7.0, `Inquirex.load_dsl` validates source against
    # {Inquirex::SafeSource::Vocabulary} before evaluating it, and the
    # vocabulary is default-deny: a word nobody declared is a violation. Every
    # word this gem adds to the DSL therefore has to be registered, or a
    # stored flow using `extract` is rejected as unsafe — not because it is
    # dangerous, but because the allowlist has never heard of it.
    #
    # Registration is guarded because the gem supports inquirex versions
    # predating SafeSource. On those, there is no allowlist to teach and
    # nothing to do.
    module SafeSource
      # Whether the core gem is new enough to have an allowlist.
      #
      # @return [Boolean]
      def self.available?
        defined?(Inquirex::SafeSource::Vocabulary) ? true : false
      end

      # Registers the LLM scope and verbs. Idempotent — `register_scope` and
      # `allow` both overwrite rather than append, so loading the gem twice is
      # harmless.
      #
      # @return [Boolean] false when the core gem has no allowlist
      def self.install!
        return false unless available?

        vocabulary = Inquirex::SafeSource::Vocabulary
        vocabulary.register_scope(
          :llm_step,
          label:      "an LLM step",
          vocabulary: -> { Inquirex::LLM::DSL::LlmStepBuilder.public_instance_methods(false) }
        )

        install_verbs!(vocabulary)
        install_step_words!(vocabulary)
        true
      end

      # The flow-level verbs: `extract`, its `clarify` alias, and `summarize`.
      #
      # @param vocabulary [Module]
      # @return [void]
      def self.install_verbs!(vocabulary)
        %i[extract clarify summarize].each do |verb|
          vocabulary.allow(:flow, verb, positional: %i[symbol], block: :llm_step)
        end
      end

      # The words legal inside an LLM step block.
      #
      # `schema` takes a mix of positional question ids and keyword field
      # types, so both are declared. `fallback` is excluded outright: it takes
      # a Ruby block, and a block is exactly the thing static validation
      # cannot vet.
      #
      # @param vocabulary [Module]
      # @return [void]
      def self.install_step_words!(vocabulary)
        v = vocabulary
        v.allow(:llm_step, :prompt, positional: %i[literal])
        v.allow(:llm_step,
          :schema,
          positional: { repeat: :symbol },
          keywords:   { Inquirex::SafeSource::Vocabulary::ANY_OTHER => :symbol })
        v.allow(:llm_step, :from, positional: { repeat: :symbol })
        v.allow(:llm_step, :from_all, positional: { optional: :literal })
        v.allow(:llm_step, :model, positional: %i[symbol])
        v.allow(:llm_step, :temperature, positional: %i[literal])
        v.allow(:llm_step, :max_tokens, positional: %i[literal])
        v.allow(:llm_step, :question, positional: %i[string])
        v.allow(:llm_step, :text, positional: %i[string])
        v.allow(:llm_step, :skip_if, positional: %i[rule])
        v.allow(:llm_step,
          :transition,
          keywords: Inquirex::SafeSource::Vocabulary::TRANSITION_KEYWORDS)
        v.exclude(:llm_step, :fallback, "a Ruby block cannot be validated")
      end
    end
  end
end
