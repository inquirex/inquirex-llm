# frozen_string_literal: true

module Inquirex
  module LLM
    module Routing
      # Where one LLM step's call goes: the chosen "vendor/model", the
      # provider serving it, the id that provider knows it by, and the
      # adapter to call.
      #
      # @!attribute [r] model
      #   @return [String, nil] "vendor/model"; nil on the legacy path, where the adapter picks
      # @!attribute [r] provider
      #   @return [Symbol, nil] :openrouter, :openai, :anthropic or :typesafe
      # @!attribute [r] native_id
      #   @return [String, nil] the model id sent to the provider
      # @!attribute [r] adapter
      #   @return [Adapter]
      Route = Data.define(:model, :provider, :native_id, :adapter)
    end
  end
end
