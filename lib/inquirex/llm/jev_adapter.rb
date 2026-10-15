# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "inquirex/llm/adapter"
require "inquirex/llm/configuration"
require "inquirex/llm/numbers"

module Inquirex
  module LLM
    # Jev, TypeSafe's System One model, through TypeSafe's own API.
    #
    # Jev does not write JSON. It answers typed questions with calibrated
    # probabilities, so each schema field becomes one or more questions, and
    # all of them go out in one request that TypeSafe answers in parallel:
    #
    # - enum: a Choice over the field's values plus {NOT_STATED}.
    # - boolean: a Choice of yes / no / {NOT_STATED}. A Noul gives only the
    #   probability of yes, and cannot say "the writer never said".
    # - multi_enum: a Choice on whether the source addresses the field at all,
    #   and a Noul per value; values at or above {THRESHOLD} are selected.
    # - integer: a Choice among the numbers the source states ({Numbers}),
    #   every count up to {SMALL_COUNTS} for what is implied rather than
    #   written ("the twins", "my wife and I"), and {NOT_STATED}.
    #
    # Jev chooses; it cannot write. A field of any other type (string, date,
    # email, ...) raises {Errors::AdapterError} before anything is sent, and so
    # does {#summarize}. Use {.unsupported_fields} to check a flow up front.
    #
    # Usage:
    #   adapter = Inquirex::LLM::JevAdapter.new  # key and model from Inquirex::LLM.configuration
    #   adapter = Inquirex::LLM::JevAdapter.new(min_confidence: 0.6)
    #   adapter.call(node, answers)              # => { filing_status: "single", dependents: nil, ... }
    #   adapter.extract(node, answers)           # => #<data Extraction values=..., confidence=..., usage=...>
    class JevAdapter < Adapter
      API_URL = "https://api.typesafe.ai/v1/systemone"

      # The option every Choice offers for "the source does not settle this".
      NOT_STATED = "not_stated_in_text"

      # The Noul probability at which a multi_enum value is selected.
      THRESHOLD = 0.5

      # Counts offered on every integer question, beyond the numbers found.
      SMALL_COUNTS = 12

      # The schema types Jev can answer.
      SUPPORTED_TYPES = %i[enum boolean multi_enum integer].freeze

      # Statuses retried, with backoff: rate limited, overloaded.
      RETRY_STATUSES = %w[429 529].freeze
      MAX_RETRIES = 2
      MAX_RETRY_DELAY = 8.0

      # What {#extract} returns: the values {#call} returns, how sure Jev was
      # of each field, and the tokens TypeSafe counted for the request.
      Extraction = Data.define(:values, :confidence, :usage)

      attr_reader :model, :min_confidence

      # @param schema [Schema]
      # @return [Array<Symbol>] the fields Jev cannot answer, empty when it can answer them all
      def self.unsupported_fields(schema)
        schema.field_specs.reject { |_, spec| SUPPORTED_TYPES.include?(spec.type) }.keys
      end

      # @param api_key [String, nil] defaults to the configuration's typesafe_api_key (TYPESAFE_API_KEY)
      # @param model [String, nil] defaults to the configuration's jev_model (INQUIREX_LLM_JEV_MODEL)
      # @param min_confidence [Float, nil] answers less confident than this come back nil;
      #   nil keeps every answer
      # @param wait [#call] waits the given seconds between retries; Kernel#sleep unless a spec says otherwise
      # @raise [ArgumentError] when no key is passed or configured
      def initialize(api_key: nil, model: nil, min_confidence: nil, wait: Kernel.method(:sleep))
        super()
        @wait = wait
        @api_key = api_key || LLM.configuration.typesafe_api_key
        raise ArgumentError, "TYPESAFE_API_KEY is required (pass api_key: or set the env var)" unless @api_key

        @model = model || LLM.configuration.jev_model
        @min_confidence = min_confidence
      end

      # @param node [Inquirex::LLM::Node] the current extract step
      # @param answers [Hash] all collected answers so far
      # @return [Hash{Symbol => Object}] one value per schema field; nil where the source is silent
      # @raise [Errors::AdapterError] on API failures, or a field Jev cannot answer
      def call(node, answers = {})
        extract(node, answers).values
      end

      # {#call}, plus how sure Jev was of each field and what the request cost.
      #
      # @return [Extraction] usage is { input_tokens:, output_tokens: }
      def extract(node, answers = {})
        raise Errors::AdapterError, "#{node.id.inspect} has no schema; Jev can only answer a schema" unless node.schema

        unsupported = self.class.unsupported_fields(node.schema)
        unless unsupported.empty?
          raise Errors::AdapterError,
            "Jev cannot answer #{unsupported.join(", ")} in #{node.id.inspect}: it answers only #{SUPPORTED_TYPES.join(", ")}"
        end

        source = source_answers(node, answers).transform_keys(&:to_s)
        questions = {}
        readers = node.schema.field_specs.to_h do |field, spec|
          [field, ask(questions, node, field, spec, source.values.join("\n"))]
        end
        result = post(state: { "answers" => source }, questions: questions)

        confidence = {}
        values = readers.to_h { |field, reader| [field, reader.call(result.fetch("answers"), confidence)] }
        values = values.to_h { |field, value| [field, confident?(confidence[field]) ? value : nil] }
        validate_output!(node, values)
        usage = result.fetch("usage", {})
        Extraction.new(values: values,
          confidence: confidence,
          usage: { input_tokens: usage["input_tokens"].to_i, output_tokens: usage["output_tokens"].to_i })
      end

      # Jev cannot write prose.
      #
      # @raise [Errors::AdapterError] always
      def summarize(node, _transcript, _answers = {})
        raise Errors::AdapterError, "Jev cannot summarize (#{node.id.inspect}): route summarize to a text model"
      end

      private

      def config = LLM.configuration

      def confident?(confidence) = min_confidence.nil? || confidence.nil? || confidence >= min_confidence

      # Adds the field's questions, and returns a lambda that reads its value
      # back out of the answers.
      def ask(questions, node, field, spec, text)
        case spec.type
        when :enum then ask_enum(questions, node, field, spec.values)
        when :boolean then ask_boolean(questions, node, field)
        when :multi_enum then ask_multi(questions, node, field, spec.values)
        when :integer then ask_integer(questions, node, field, text)
        end
      end

      def ask_enum(questions, node, field, values)
        questions[field.to_s] = choice(
          node,
          "Which `#{field}` do the `answers` support?",
          values.to_h { [it, nil] }.merge(NOT_STATED => not_stated(field))
        )
        choice_reader(field) { it }
      end

      def ask_boolean(questions, node, field)
        questions[field.to_s] = choice(
          node,
          "Is `#{field}` true, according to the `answers`?",
          { "yes"      => "The answers say or clearly imply it is true.",
            "no"       => "The answers say or clearly imply it is false.",
            NOT_STATED => not_stated(field) }
        )
        choice_reader(field) { it == "yes" }
      end

      def ask_multi(questions, node, field, values)
        addressed = "#{field}__addressed"
        questions[addressed] = choice(
          node,
          "Do the `answers` say anything that bears on `#{field}` (#{values.join(", ")})?",
          { "yes"      => "At least one of these comes up, or the writer rules them out.",
            NOT_STATED => not_stated(field) }
        )
        values.each do |value|
          questions["#{field}__#{value}"] = {
            "type" => "noul", "instructions" => instructions(node, "For `#{field}`, do the `answers` call for `#{value}`?")
          }
        end
        lambda do |answers, confidence|
          confidence[field] = answers.dig(addressed, "confidence")
          next nil if answers.dig(addressed, "choice") == NOT_STATED

          values.select { answers.dig("#{field}__#{it}", "noul").to_f >= THRESHOLD }
        end
      end

      def ask_integer(questions, node, field, text)
        options = (Numbers.find(text) + (0..SMALL_COUNTS).to_a).uniq.to_h { [it.to_s, nil] }
        questions[field.to_s] = choice(
          node,
          "What number is `#{field}`, according to the `answers`? " \
          "Count what the writer implies as well as what they write out.",
          options.merge(NOT_STATED => not_stated(field))
        )
        choice_reader(field) { Integer(it, 10) }
      end

      def choice(node, question, criteria)
        { "type" => "choice", "instructions" => instructions(node, question), "criteria" => criteria }
      end

      # @yieldparam choice [String] the chosen option, never {NOT_STATED}
      def choice_reader(field)
        lambda do |answers, confidence|
          answer = answers.fetch(field.to_s)
          confidence[field] = answer["confidence"]
          answer["choice"] == NOT_STATED ? nil : yield(answer["choice"])
        end
      end

      # The flow author's prompt travels with every question as context.
      def instructions(node, question)
        { "context" => node.prompt.to_s, "question" => question }
      end

      def not_stated(field)
        "Nothing in the answers settles `#{field}`; leave it unset rather than guess."
      end

      # @return [Hash] the parsed response
      # @raise [Errors::AdapterError] on a non-2xx after retries, or a body that is not JSON
      def post(state:, questions:)
        attempt = 0
        loop do
          response = request(JSON.generate("state" => state, "questions" => questions, "model" => model))
          return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

          if RETRY_STATUSES.include?(response.code) && attempt < MAX_RETRIES
            attempt += 1
            @wait.call(retry_delay(response, attempt))
            next
          end
          raise Errors::AdapterError, "TypeSafe API error #{response.code}: #{response.body}"
        end
      rescue JSON::ParserError => e
        raise Errors::AdapterError, "TypeSafe returned a body that is not JSON: #{e.message}"
      end

      def request(body)
        uri = URI(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 30
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request.body = body
        warn "[inquirex-llm] Calling TypeSafe #{model}..." if config.debug?
        http.request(request)
      end

      # Retry-After (seconds) when the server sends one, otherwise doubling
      # from half a second; capped at {MAX_RETRY_DELAY} either way.
      def retry_delay(response, attempt)
        header = response["retry-after"].to_s
        delay = header.match?(/\A\d+(\.\d+)?\z/) ? Float(header) : 0.5 * (2**(attempt - 1))
        [delay, MAX_RETRY_DELAY].min
      end
    end
  end
end
