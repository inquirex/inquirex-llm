# frozen_string_literal: true

module Inquirex
  module LLM
    module DSL
      # Builds an LLM::Node from a step DSL block. Handles the LLM-specific
      # methods (from, prompt, schema, model, temperature, max_tokens, fallback)
      # while inheriting transition and skip_if from the core StepBuilder.
      #
      # @example Referencing downstream questions (preferred)
      #   extract :business_extracted do
      #     from :business_description
      #     prompt "Extract structured business info."
      #     schema :entity_type, :employee_band     # resolved from the ask steps
      #     model :claude_sonnet
      #     temperature 0.2
      #     transition to: :next_step
      #   end
      #
      # @example Explicit field types (for fields with no matching question)
      #   extract :business_extracted do
      #     from :business_description
      #     prompt "Extract structured business info."
      #     schema industry: :string, employee_count: :integer
      #     transition to: :next_step
      #   end
      class LlmStepBuilder
        include Inquirex::DSL::RuleHelpers

        def initialize(verb)
          @verb = verb.to_sym
          @prompt = nil
          @schema_refs = []
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
        # Pass `:auto` to generate the prompt from the schema's question
        # references at build time: each referenced question's own wording is
        # enumerated, so the LLM sees what was actually asked. Requires at
        # least one question reference in the schema.
        #
        # @param text [String, :auto]
        def prompt(text)
          @prompt = text
        end

        # Declares the expected output schema.
        #
        # Positional symbols name questions defined elsewhere in the flow;
        # each is resolved against that step's declared type, and for
        # :enum / :multi_enum questions the allowed option values are folded
        # into the schema sent to the LLM. A symbol that matches no ask/confirm
        # step in the flow fails validation as invalid DSL.
        #
        # Keyword pairs declare explicit field => type mappings, for output
        # fields that have no corresponding question. Both forms compose:
        #
        #   schema :filing_status, :income_types, confidence: :decimal
        #
        # @param question_ids [Array<Symbol>] ids of questions to fill
        # @param fields [Hash{Symbol => Symbol}] explicit field => type pairs
        def schema(*question_ids, **fields)
          @schema_refs.concat(question_ids.flatten.map(&:to_sym))
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

        # Optional display text (user-visible label for the step).
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

        # Builds the LLM::Node. Question references in the schema are resolved
        # against the full node map, so the flow builder defers this call until
        # every step — including ones defined after this one — is known.
        #
        # @param id [Symbol]
        # @param nodes [Hash{Symbol => Inquirex::Node}, nil] all flow nodes,
        #   required when the schema references question ids
        # @return [LLM::Node]
        # @raise [Errors::DefinitionError] if prompt is missing or a schema
        #   reference does not resolve to an ask/confirm question
        def build(id, nodes: nil)
          validate!(id)

          field_map = resolve_schema_refs(id, nodes).merge(@schema_fields)
          schema_obj = field_map.empty? ? nil : Schema.new(**field_map)
          prompt_text = @prompt == :auto ? auto_prompt(nodes) : @prompt

          LLM::Node.new(
            id:,
            verb:        @verb,
            prompt:      prompt_text,
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

        # Turns question references into full field specs by looking up each
        # referenced step in the flow: its declared type, and for enum-like
        # types the exhaustive list of allowed option values.
        #
        # @param id [Symbol] this LLM step's id (for error messages)
        # @param nodes [Hash{Symbol => Inquirex::Node}, nil]
        # @return [Hash{Symbol => Hash}] field => { type:, values: } specs
        def resolve_schema_refs(id, nodes)
          return {} if @schema_refs.empty?

          overlap = @schema_refs & @schema_fields.keys
          unless overlap.empty?
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} schema declares #{overlap.map(&:inspect).join(", ")} " \
              "both as a question reference and an explicit field"
          end

          @schema_refs.uniq.to_h do |ref|
            [ref, field_spec_for(id, ref, resolve_question!(id, ref, nodes))]
          end
        end

        # Generates a prompt from the referenced questions' own wording.
        # Runs at build time, after resolution, so the serialized node (and
        # every adapter) sees a concrete prompt string — `:auto` never
        # reaches the wire format.
        #
        # @param nodes [Hash{Symbol => Inquirex::Node}]
        # @return [String]
        def auto_prompt(nodes)
          lines = @schema_refs.uniq.map do |ref|
            question = nodes[ref].question
            question ? "- #{ref}: #{question}" : "- #{ref}"
          end
          lines += @schema_fields.map { |name, type| "- #{name} (#{type})" }

          "Extract structured answers from the user's text for the following questions:\n" \
            "#{lines.join("\n")}\n" \
            "Only extract what the text supports; leave a field empty or null when unsure."
        end

        # @return [Inquirex::Node] the ask/confirm step the reference names
        def resolve_question!(id, ref, nodes)
          node = nodes&.fetch(ref, nil)

          case node
          when nil
            known = (nodes || {}).filter_map { |sid, n| sid if question_node?(n) }
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} schema references unknown question #{ref.inspect}. " \
              "Known questions: #{known.empty? ? "(none)" : known.map(&:inspect).join(", ")}"
          when LLM::Node, LlmStepBuilder
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} schema references #{ref.inspect}, which is an LLM step — " \
              "schema references must name ask/confirm questions"
          else
            unless node.collecting?
              raise Errors::DefinitionError,
                "LLM step #{id.inspect} schema references #{ref.inspect}, which is a display-only " \
                "#{node.verb} step — schema references must name ask/confirm questions"
            end
            node
          end
        end

        def question_node?(node)
          node.is_a?(Inquirex::Node) && !node.is_a?(LLM::Node) && node.collecting?
        end

        # @return [Hash] a Schema field spec derived from the question's definition
        def field_spec_for(id, ref, node)
          if node.type.nil?
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} schema references #{ref.inspect}, which declares no type"
          end

          spec = { type: node.type }
          spec[:values] = node.options if %i[enum multi_enum].include?(node.type) && node.options
          spec
        end

        def validate!(id)
          raise Errors::DefinitionError, "LLM step #{id.inspect} requires a prompt" if @prompt.nil?

          if @prompt == :auto && @schema_refs.empty?
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} declares `prompt :auto`, which requires schema question " \
              "references to generate from — declare the schema as question ids (e.g. schema :filing_status)"
          end

          # Schema required for extract (and formerly detour).
          if %i[extract].include?(@verb) && @schema_fields.empty? && @schema_refs.empty?
            # if %i[extract detour].include?(@verb) && @schema_fields.empty?
            raise Errors::DefinitionError,
              "LLM step #{id.inspect} (#{@verb}) requires a schema"
          end

          return unless @from_steps.empty? && !@from_all
          # return unless @from_steps.empty? && !@from_all && @verb != :summarize

          # extract (and formerly describe/detour) should reference source steps or from_all
          return unless %i[extract].include?(@verb)

          # return unless %i[extract describe detour].include?(@verb)

          raise Errors::DefinitionError,
            "LLM step #{id.inspect} (#{@verb}) requires `from` or `from_all`"
        end
      end
    end
  end
end
