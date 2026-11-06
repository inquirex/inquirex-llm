# frozen_string_literal: true

module Inquirex
  module LLM
    module Routing
      # An OpenRouter-style model name, "vendor/model", and the id each
      # vendor's own API knows it by.
      #
      # @example
      #   id = ModelId.parse("anthropic/claude-haiku-5.5")
      #   id.vendor               # => :anthropic
      #   id.native_id            # => "claude-haiku-5-5"
      #   id.native_provider      # => :anthropic
      class ModelId < Data.define(:vendor, :name)
        # "vendor/model": a lowercase vendor, then any model name without spaces.
        FORMAT = %r{\A[a-z0-9][a-z0-9_.-]*/[^\s/][^\s]*\z}

        # Vendors with an adapter of their own. Every other vendor is reached
        # only through OpenRouter.
        NATIVE = %i[anthropic openai typesafe].freeze

        class << self
          # @param value [String, Symbol]
          # @return [Boolean] whether the value is a "vendor/model" name
          def valid?(value) = FORMAT.match?(value.to_s)

          # @param value [String, Symbol] "vendor/model"
          # @return [ModelId]
          # @raise [ArgumentError] when the value is not "vendor/model"
          def parse(value)
            raise ArgumentError, "#{value.inspect} is not a \"vendor/model\" name" unless valid?(value)

            vendor, name = value.to_s.split("/", 2)
            new(vendor: vendor.to_sym, name: name)
          end

          # The "vendor/model" name an old-style DSL model hint stands for:
          # `:claude_sonnet` => "anthropic/claude-sonnet-5.5". A hint that is
          # already "vendor/model" passes through.
          #
          # @param hint [Symbol, String, nil]
          # @return [String, nil] nil when the hint names nothing routable
          def from_hint(hint)
            return nil if hint.nil?
            return hint.to_s if valid?(hint)

            Models::OPENROUTER_ALIASES[hint.to_sym]
          end
        end

        # @return [String] "vendor/model", as OpenRouter names it
        def to_s = "#{vendor}/#{name}"

        # @return [Symbol, nil] the vendor's own provider, nil when only OpenRouter serves it
        def native_provider = NATIVE.include?(vendor) ? vendor : nil

        # The id the vendor's own API uses. Anthropic writes versions with
        # dashes ("claude-haiku-5-5") where OpenRouter uses dots ("5.5").
        #
        # @return [String]
        def native_id = vendor == :anthropic ? name.tr(".", "-") : name
      end
    end
  end
end
