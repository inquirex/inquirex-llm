# frozen_string_literal: true

module Inquirex
  module LLM
    module DSL
      # Builds an LLM::Node from a step DSL block. Handles the LLM-specific
      # methods (from, prompt, schema, model, temperature, max_tokens, fallback)
      # while inheriting transition and skip_if from the core StepBuilder.
      #
      # @example
      #   clarify :business_extracted do
      #     from :business_description
      #     prompt "Extract structured business info."
      #     schema industry: :string, employee_count: :integer
      #     model :claude_sonnet
      #     temperature 0.2
      #     transition to: :next_step
      #   end
      class LlmStepBuilder
        include Inquirex::DSL::RuleHelpers

        def initialize(verb)
          @verb = verb.to_sym
          @prompt = nil
          @schema_fields = {}
          @from_steps = []
          @from_all = false
          @model = nil
          @temperature = nil
          @max_tokens = nil
          @fallback = nil
          @transitions = []
          @skip_if = nil
          @question = nil
          @text = nil
        end

        # Sets the LLM prompt template. Use {{field_name}} for interpolation
        # placeholders that the adapter resolves at runtime.
        #
        # @param text [String]
        def prompt(text)
          @prompt = text
        end

        # Declares the expected output schema. Each key is a field name,
        # each value is an Inquirex data type symbol.
        #
        # @param fields [Hash{Symbol => Symbol}]
        def schema(**fields)
          @schema_fields.merge!(fields)
        end

        # Adds source step id(s) whose answers feed the LLM prompt.
        #
        # @param step_ids [Symbol, Array<Symbol>] one or more step ids
        def from(*step_ids)
          @from_steps.concat(step_ids.flatten)
        end

        # Passes all collected answers to the LLM prompt.
        #
        # @param value [Boolean]
        def from_all(value = true)
          @from_all = !!value
        end

        # Optional model hint for the adapter.
        #
        # @param name [Symbol] e.g. :claude_sonnet, :claude_haiku
        def model(name)
          @model = name.to_sym
        end

        # Optional sampling temperature.
        #
        # @param value [Float]
        def temperature(value)
          @temperature = value.to_f
        end

        # Optional maximum output tokens.
        #
        # @param value [Integer]
        def max_tokens(value)
          @max_tokens = value.to_i
        end

        # Server-side fallback block, invoked when the LLM call fails.
        # Stripped from JSON serialization.
        #
        # @yield [Hash] answers collected so far
        # @return [Object] fallback value to store as the answer
        def fallback(&block)
          @fallback = block
        end

        # Adds a conditional transition. Inherited concept from core DSL.
        # All LLM transitions are implicitly requires_server: true.
        #
        # @param to [Symbol] target step id
        # @param if_rule [Rules::Base, nil]
        # @param requires_server [Boolean]
        def transition(to:, if_rule: nil, requires_server: true)
          @transitions << Inquirex::Transition.new(target: to, rule: if_rule, requires_server:)
        end

        # Sets a rule that skips this step entirely when true.
        #
        # @param rule [Rules::Base]
        def skip_if(rule)
          @skip_if = rule
        end

        # Optional display text (used by describe/summarize for user-visible labels).
        #
        # @param content [String]
        def question(content)
          @question = content
        end

        # Optional display text for context.
        #
        # @param content [String]
        def text(content)
          @text = content
        end

        # Builds the LLM::Node.
        #
        # @param id [Symbol]
        # @return [LLM::Node]
        # @raise [Errors::DefinitionError] if prompt is missing
        def build(id)
          validate!(id)

          schema_obj = @schema_fields.empty? ? nil : Schema.new(**@schema_fields)

          LLM::Node.new(
            id:,
            verb:        @verb,
            prompt:      @prompt,
            schema:      schema_obj,
            from_steps:  @from_steps,
            from_all:    @from_all,
            model:       @model,
            temperature: @temperature,
            max_tokens:  @max_tokens,
            fallback:    @fallback,
            question:    @question,
            text:        @text,
            transitions: @transitions,
            skip_if:     @skip_if
          )
        end

        private

        def validate!(id)
          raise Errors::DefinitionError, "LLM step #{id.inspect} requires a prompt" if @prompt.nil?

          if %i[clarify detour].include?(@verb) && @schema_fields.empty?
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} (#{@verb}) requires a schema"
          end

          return unless @from_steps.empty? && !@from_all && @verb != :summarize

          # clarify/describe/detour should reference source steps or from_all
          return unless %i[clarify describe detour].include?(@verb)

          raise Errors::DefinitionError,
            "LLM step #{id.inspect} (#{@verb}) requires `from` or `from_all`"
        end
      end
    end
  end
end
