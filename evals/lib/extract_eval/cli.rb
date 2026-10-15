# frozen_string_literal: true

module ExtractEval
  # Every command the executable answers to.
  module CLI
    extend Dry::CLI::Registry

    Dry::CLI::Help.configure do
      title "extract-eval"
      description "Score LLMs on turning free-form text into an Inquirex extract step's structured answers, " \
                  "via OpenRouter, recorded as Braintrust experiments."

      columns = IO.console&.winsize&.last || 80
      width [columns - 6, 120].min
      exit_code_without_arguments 0

      styles do
        heading :bold, :cyan, case: :UPPERCASE
        usage :yellow
        example :yellow
        option :green
        example_comment :bright_black
      end
    end

    register "run", Run
    register "compare", Compare
    register "cases", Cases
    register "verify", Verify
    register "version", Version, aliases: ["-V", "--version"]
    register "completion", Dry::CLI::Autocomplete::Command[self, program_name: "extract-eval"]
  end
end
