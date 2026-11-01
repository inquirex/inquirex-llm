# frozen_string_literal: true

# The extraction eval suite's Ruby: an llm-evals Adapter that runs one
# case through the gem's production prompts, and a Scorer that grades the
# reply field by field. Loaded by `require "inquirex/llm/evals"` from
# evals/.llm-evals.config.yml, never by `require "inquirex-llm"`, because
# llm-evals is the suite's dependency and not the gem's.
begin
  require "llm/evals"
rescue LoadError => e
  raise LoadError,
    "inquirex/llm/evals needs the llm-evals gem, which is not a dependency of inquirex-llm: " \
    "add it to the :evals group of your Gemfile (#{e.message})"
end

require "inquirex/llm"
require_relative "evals/dataset"
require_relative "evals/model_adapter"
require_relative "evals/adapter"
require_relative "evals/field_score"
require_relative "evals/scorer"

module Inquirex
  module LLM
    # The pieces llm-evals needs from this gem. {Adapter} owns everything
    # the model sees and everything done to its answer; {Scorer} owns what a
    # right answer is. Neither knows the other, and only the config file
    # names them both.
    module Evals
      # A dataset that cannot be evaluated: no dsl.rb, no single extract step, a schema that drifted.
      class Error < StandardError; end
    end
  end
end
