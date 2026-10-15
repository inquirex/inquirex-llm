# frozen_string_literal: true

require "inquirex"
require "json"

require_relative "llm/version"
require_relative "llm/errors"
require_relative "llm/models"
require_relative "llm/configuration"
require_relative "llm/prompts"
require_relative "llm/schema"
require_relative "llm/node"
require_relative "llm/adapter"
require_relative "llm/null_adapter"
require_relative "llm/anthropic_adapter"
require_relative "llm/openai_adapter"
require_relative "llm/numbers"
require_relative "llm/dsl/llm_step_builder"
require_relative "llm/dsl/flow_builder"
require_relative "llm/safe_source"

module Inquirex
  # LLM integration layer for Inquirex flows.
  #
  # Extends the core DSL with LLM-powered verbs that run server-side:
  #   - extract   — extract structured data from free-text answers (`clarify` is an alias)
  #   - summarize — close the flow with a prose summary of the whole session
  #   # - describe  — generate natural-language text from structured data
  #   # - detour    — dynamically generate follow-up questions
  #
  # LLM calls never happen on the frontend. Steps are marked `requires_server: true`
  # in the JSON wire format so the JS widget knows to round-trip to the server.
  #
  # Usage:
  #   require "inquirex"
  #   require "inquirex-llm"
  #
  #   Inquirex.define id: "intake" do
  #     start :description
  #     ask(:description) { type :text; question "Describe your business."; transition to: :extracted }
  #     extract(:extracted) { from :description; prompt "Extract info."; schema name: :string; transition to: :done }
  #     say(:done) { text "Done!" }
  #   end
  module LLM
    # Builds the adapter the configuration asks for. First match wins:
    #
    #   provider :null             → NullAdapter (forced offline)
    #   provider :anthropic        → AnthropicAdapter (raises if no key)
    #   provider :openai           → OpenAIAdapter (raises if no key)
    #   anthropic_api_key is set   → AnthropicAdapter
    #   openai_api_key is set      → OpenAIAdapter
    #   otherwise                  → NullAdapter
    #
    # provider comes from INQUIREX_LLM_ADAPTER, the keys from
    # ANTHROPIC_API_KEY and OPENAI_API_KEY, unless set through {configure}.
    # TYPESAFE_API_KEY is never consulted: there is no Jev adapter yet.
    #
    # @return [Adapter]
    # @raise [ArgumentError] when a forced provider has no key
    def self.adapter
      config = configuration
      case config.provider
      when :null      then NullAdapter.new
      when :anthropic then AnthropicAdapter.new
      when :openai    then OpenAIAdapter.new
      else
        if config.anthropic_api_key
          AnthropicAdapter.new
        elsif config.openai_api_key
          OpenAIAdapter.new
        else
          NullAdapter.new
        end
      end
    end
  end
end

# Inject LLM verbs into the core FlowBuilder so that Inquirex.define
# gains extract (and clarify as an alias) when this gem is loaded.
# Prepend (not include): the extension overrides #build to defer LLM node
# construction until the whole flow is known, so schema question references
# can resolve forward to questions defined after the LLM step.
Inquirex::DSL::FlowBuilder.prepend(Inquirex::LLM::DSL::FlowBuilderExtension)

# Teach SafeSource's default-deny allowlist about the verbs just added, so
# that `Inquirex.load_dsl` accepts a stored flow using them. A no-op on
# inquirex versions predating SafeSource.
Inquirex::LLM::SafeSource.install!
