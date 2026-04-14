# frozen_string_literal: true

module Inquirex
  module LLM
    module Errors
      # Base exception for all LLM-related errors.
      class Error < Inquirex::Errors::Error; end

      # Raised when an LLM step definition is invalid (e.g. missing prompt, bad schema).
      class DefinitionError < Error; end

      # Raised when the LLM adapter returns output that doesn't match the declared schema.
      class SchemaViolationError < Error; end

      # Raised when the LLM adapter call fails after exhausting retries.
      class AdapterError < Error; end
    end
  end
end
