# frozen_string_literal: true

require "inquirex"
require "json"

require_relative "llm/version"
require_relative "llm/errors"
require_relative "llm/schema"
require_relative "llm/node"
require_relative "llm/adapter"
require_relative "llm/null_adapter"
require_relative "llm/dsl/llm_step_builder"
require_relative "llm/dsl/flow_builder"

module Inquirex
  # LLM integration layer for Inquirex flows.
  #
  # Extends the core DSL with four LLM-powered verbs that run server-side:
  #   - clarify   — extract structured data from free-text answers
  #   - describe  — generate natural-language text from structured data
  #   - summarize — produce a summary of all or selected answers
  #   - detour    — dynamically generate follow-up questions
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
  #     clarify(:extracted) { from :description; prompt "Extract info."; schema name: :string; transition to: :done }
  #     say(:done) { text "Done!" }
  #   end
  module LLM
  end
end

# Inject LLM verbs into the core FlowBuilder so that Inquirex.define
# gains clarify/describe/summarize/detour when this gem is loaded.
Inquirex::DSL::FlowBuilder.include(Inquirex::LLM::DSL::FlowBuilderExtension)
