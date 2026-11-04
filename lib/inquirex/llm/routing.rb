# frozen_string_literal: true

require_relative "routing/model_id"
require_relative "routing/route"
require_relative "routing/console"
require_relative "routing/catalog"
require_relative "routing/registry"
require_relative "routing/router"

module Inquirex
  module LLM
    # Per-step model selection across vendors. A host lists the vendors and
    # models it prefers ({Configuration#llm_vendors_priority},
    # {Configuration#llm_models_priority}); each LLM step may name its own
    # ordered models (`use_first_available_model`); the first one this
    # process can reach is used. See docs/decisions/prioritized-model-selection.md.
    #
    # The public surface is on {LLM}: {LLM.route}, {LLM.extract},
    # {LLM.summarize} and {LLM.ensure_provider_models!}. The classes in here
    # are its parts.
    module Routing
      # The vendors llm_vendors_priority may name.
      VENDORS = %i[openrouter openai anthropic typesafe].freeze
    end
  end
end
