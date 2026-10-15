# frozen_string_literal: true

module Inquirex
  module LLM
    # What an adapter returns for an `extract` step: the schema-shaped values,
    # plus what the model actually said and what the call cost.
    #
    # It IS the Hash of values it replaced, not a wrapper around one. The
    # engine's `prefill!` and inquirex-tty both test `result.is_a?(Hash)` and
    # would silently skip a struct, and a session serializes the result as
    # JSON; so the values are the entries, and {#raw} and {#usage} ride along
    # as attributes. Frozen, like the Data objects elsewhere in this gem.
    #
    # @example
    #   extraction = adapter.call(node, answers)
    #   extraction[:filing_status]                  # => "single"   (canonicalized)
    #   extraction.raw[:filing_status]              # => "Single"   (as the model wrote it)
    #   extraction.usage                            # => { input_tokens: 812, output_tokens: 40 }
    #   extraction == { filing_status: "single" }   # => true
    #   engine.prefill!(extraction)                 # works: it is a Hash
    class Extraction < Hash
      # @return [Hash, nil] the parsed JSON exactly as the model sent it, before
      #   {Adapter#normalize_output} repaired enum values; nil for an adapter
      #   that has no such thing (a placeholder, a typed-question model)
      attr_reader :raw

      # @return [Hash{Symbol => Numeric}] input_tokens and output_tokens as the
      #   provider counted them, cost_usd when it reported one; empty when unknown
      attr_reader :usage

      # @param output [Hash] the normalized, schema-shaped values
      # @param raw [Hash, nil] what the model sent
      # @param usage [Hash] tokens and cost, when known
      def initialize(output:, raw: nil, usage: {})
        super()
        replace(output)
        @raw = raw.nil? ? nil : raw.dup.freeze
        @usage = usage.to_h.freeze
        freeze
      end

      # @return [Hash] the values alone, as a plain Hash
      def output = to_h

      # Shows raw and usage beside the values, so a debugger does not mistake
      # it for the Hash it also is.
      #
      # @return [String]
      def inspect
        "#<#{self.class.name} #{to_h.inspect} raw=#{raw.inspect} usage=#{usage.inspect}>"
      end
    end
  end
end
