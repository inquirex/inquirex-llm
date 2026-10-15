# frozen_string_literal: true

require "inquirex/llm/errors"
require "inquirex/llm/models"

module Inquirex
  module LLM
    # Gem-wide settings: which provider to use, its credentials, its default
    # model, and the generation limits the adapters fall back on when a node
    # does not set its own.
    #
    # Each setting is read from its environment variable when that variable
    # is set and not blank, and otherwise takes the default below. ENV is read
    # once, when the configuration is built; {LLM.reset_configuration!} builds
    # it again. Writers override either, and a nil written restores the
    # default.
    #
    # Invalid values raise {Errors::ConfigurationError} naming the variable
    # (or the writer) that carried them, at the moment they are read, so a
    # typo in INQUIREX_LLM_ADAPTER fails loudly instead of silently falling
    # through to auto-detection.
    #
    # @example
    #   Inquirex::LLM.configure do |c|
    #     c.provider        = :anthropic
    #     c.anthropic_model = "claude-opus-5-5"
    #     c.max_tokens      = 4096
    #   end
    class Configuration
      # The providers {LLM.adapter} can build. nil means auto-detect.
      PROVIDERS = %i[anthropic openai openrouter null].freeze

      DEFAULT_MAX_TOKENS = 2048
      DEFAULT_TEMPERATURE = 0.2

      # Summaries want more room than an extraction (prose, not a handful of
      # fields) and more warmth than one (0.2 produces summaries that read
      # like a database dump).
      DEFAULT_SUMMARY_MAX_TOKENS = 4096
      DEFAULT_SUMMARY_TEMPERATURE = 0.4

      # The range both providers accept; OpenAI's is the wider of the two.
      TEMPERATURES = (0.0..2.0)

      # What {#to_h} and {#inspect} show instead of a credential.
      REDACTED = "[REDACTED]"

      # One setting: the variable it is read from, its default, and the
      # coercion its value goes through.
      Setting = Data.define(:env, :default, :type)

      # Every setting, in the order {#to_h} lists them. Readers, writers,
      # the ENV table in the README and the specs all follow this table.
      SETTINGS = {
        provider:            Setting.new("INQUIREX_LLM_ADAPTER", nil, :provider),
        anthropic_api_key:   Setting.new("ANTHROPIC_API_KEY", nil, :string),
        openai_api_key:      Setting.new("OPENAI_API_KEY", nil, :string),
        openrouter_api_key:  Setting.new("OPENROUTER_API_KEY", nil, :string),
        # Reserved for the upcoming Jev adapter; nothing reads it yet, and
        # auto-detection ignores it.
        typesafe_api_key:    Setting.new("TYPESAFE_API_KEY", nil, :string),
        anthropic_model:     Setting.new("INQUIREX_LLM_ANTHROPIC_MODEL", Models::ANTHROPIC_DEFAULT, :string),
        openai_model:        Setting.new("INQUIREX_LLM_OPENAI_MODEL", Models::OPENAI_DEFAULT, :string),
        openrouter_model:    Setting.new("INQUIREX_LLM_OPENROUTER_MODEL", Models::OPENROUTER_DEFAULT, :string),
        # Reserved for the upcoming Jev adapter; see Models::JEV_DEFAULT.
        jev_model:           Setting.new("INQUIREX_LLM_JEV_MODEL", Models::JEV_DEFAULT, :string),
        max_tokens:          Setting.new("INQUIREX_LLM_MAX_TOKENS", DEFAULT_MAX_TOKENS, :positive_integer),
        temperature:         Setting.new("INQUIREX_LLM_TEMPERATURE", DEFAULT_TEMPERATURE, :temperature),
        summary_max_tokens:  Setting.new("INQUIREX_LLM_SUMMARY_MAX_TOKENS", DEFAULT_SUMMARY_MAX_TOKENS, :positive_integer),
        summary_temperature: Setting.new("INQUIREX_LLM_SUMMARY_TEMPERATURE", DEFAULT_SUMMARY_TEMPERATURE, :temperature),
        debug:               Setting.new("INQUIREX_DEBUG", false, :flag)
      }.freeze

      SETTINGS.each_key do |name|
        attr_reader name

        # @param value [Object, nil] nil restores the default
        # @raise [Errors::ConfigurationError] when the value is invalid
        define_method(:"#{name}=") do |value|
          instance_variable_set(:"@#{name}", resolve(name, value, "Inquirex::LLM.configuration.#{name}"))
        end
      end

      # @param env [#[]] the environment to read; ENV unless a spec says otherwise
      # @raise [Errors::ConfigurationError] when a variable holds an invalid value
      def initialize(env = ENV)
        SETTINGS.each do |name, setting|
          instance_variable_set(:"@#{name}", resolve(name, env[setting.env], setting.env))
        end
      end

      # @return [Boolean] whether debug logging is on
      def debug? = debug

      # Every setting, with credentials replaced by {REDACTED} when set.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        SETTINGS.keys.to_h do |name|
          value = public_send(name)
          [name, secret?(name) && value ? REDACTED : value]
        end
      end

      # Never shows a credential: an exception report or a console session
      # that prints the configuration must not leak a key.
      #
      # @return [String]
      def inspect
        "#<#{self.class.name} #{to_h.map { |name, value| "#{name}=#{value.inspect}" }.join(", ")}>"
      end
      alias to_s inspect

      private

      def secret?(name) = name.end_with?("_api_key")

      # @param name [Symbol] the setting
      # @param value [Object, nil] raw value from ENV or a writer
      # @param source [String] what to name in an error
      # @return [Object] the coerced value, or the default when blank
      def resolve(name, value, source)
        setting = SETTINGS.fetch(name)
        return setting.default if value.nil? || (value.is_a?(String) && value.strip.empty?)

        send(:"coerce_#{setting.type}", value, source)
      end

      def coerce_string(value, _source) = value.to_s.strip

      def coerce_provider(value, source)
        provider = value.to_s.strip.downcase.to_sym
        return provider if PROVIDERS.include?(provider)

        invalid!(source, value, "one of #{PROVIDERS.join(", ")}")
      end

      def coerce_positive_integer(value, source)
        integer = Integer(value.to_s.strip, 10)
        integer.positive? ? integer : invalid!(source, value, "a positive integer")
      rescue ArgumentError, TypeError
        invalid!(source, value, "a positive integer")
      end

      def coerce_temperature(value, source)
        float = Float(value.to_s.strip)
        TEMPERATURES.cover?(float) ? float : invalid!(source, value, "a number from #{TEMPERATURES.min} to #{TEMPERATURES.max}")
      rescue ArgumentError, TypeError
        invalid!(source, value, "a number from #{TEMPERATURES.min} to #{TEMPERATURES.max}")
      end

      # Any non-blank value turns debugging on, as INQUIREX_DEBUG always has.
      def coerce_flag(value, _source) = value.is_a?(String) || value == true

      def invalid!(source, value, expected)
        raise Errors::ConfigurationError, "#{source} must be #{expected} (got #{value.inspect})"
      end
    end

    class << self
      # The gem-wide configuration, built from ENV on first use.
      #
      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # @yieldparam config [Configuration]
      # @return [Configuration]
      def configure
        yield configuration
        configuration
      end

      # Discards every write and reads ENV again. Call it after changing ENV
      # (a .env file loaded late, or a spec), since ENV is read only once.
      #
      # @return [Configuration]
      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end
