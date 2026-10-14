# frozen_string_literal: true

module Inquirex
  module LLM
    # The model catalogue: every concrete model id this gem knows, and the
    # short DSL symbols that resolve to them. It is the only place a model id
    # is written in lib/. The defaults and every alias are looked up here, so
    # a model generation is retired in one edit instead of three that drift
    # apart (0.10.0 still defaulted to a 4.x id after 5.x shipped).
    module Models
      # The current Claude model ids.
      ANTHROPIC = %w[
        claude-fable-5-1
        claude-opus-5-5
        claude-sonnet-5-5
        claude-haiku-5-5
      ].freeze

      # Short DSL symbols for {ANTHROPIC}, one per family:
      # :claude_opus => "claude-opus-5-5", and so on.
      ANTHROPIC_ALIASES = ANTHROPIC.to_h { |id| [:"claude_#{id.split("-")[1]}", id] }.freeze

      # The Claude model used when nothing else names one.
      ANTHROPIC_DEFAULT = ANTHROPIC_ALIASES.fetch(:claude_sonnet)

      # Short DSL symbols for OpenAI model ids. The Claude symbols map to
      # OpenAI equivalents so a flow written against Anthropic still runs
      # against the OpenAI adapter. :claude_fable has no equivalent.
      OPENAI_ALIASES = {
        gpt_4o:        "gpt-4o",
        gpt_4o_mini:   "gpt-4o-mini",
        gpt_4_1:       "gpt-4.1",
        gpt_4_1_mini:  "gpt-4.1-mini",
        claude_sonnet: "gpt-4o",
        claude_haiku:  "gpt-4o-mini",
        claude_opus:   "gpt-4o"
      }.freeze

      # The OpenAI model used when nothing else names one.
      OPENAI_DEFAULT = OPENAI_ALIASES.fetch(:gpt_4o_mini)

      # TypeSafe's Jev model, reserved for a Jev adapter that does not exist
      # yet. This is the version the docs last recorded; it is UNVERIFIED
      # against TypeSafe's live model list and must be confirmed before any
      # adapter sends it.
      JEV_DEFAULT = "jev-1.13.0"
    end
  end
end
