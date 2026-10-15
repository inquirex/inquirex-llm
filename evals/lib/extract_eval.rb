# frozen_string_literal: true

require "json"
require "inquirex"
require "inquirex/llm"
require "dry/cli"
require "dry/cli/help"
require "dry/cli/ui"
require "dry/cli/autocomplete/command"
require "zeitwerk"

# Measures how well an LLM turns free-form text into the structured answers an
# Inquirex `extract` step declares, across models, through Braintrust.
module ExtractEval
  class Error < StandardError; end

  # The evals/ directory: dsls/, schema/, extracted-answers/, ground-truth/.
  ROOT = File.expand_path("..", __dir__)
end

require_relative "extract_eval/version"

loader = Zeitwerk::Loader.new
loader.push_dir(File.expand_path(__dir__))
loader.inflector.inflect("cli" => "CLI")
loader.ignore(File.expand_path("extract_eval/version.rb", __dir__))
loader.setup
