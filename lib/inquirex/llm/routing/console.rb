# frozen_string_literal: true

module Inquirex
  module LLM
    module Routing
      # Coloured notices on stderr: yellow for something removed, green for
      # what is left. Colour only when stderr is a terminal, so logs stay clean.
      class Console
        YELLOW = "\e[33m"
        GREEN = "\e[32m"
        RESET = "\e[0m"

        # @param io [IO] where notices go
        def initialize(io = $stderr)
          @io = io
        end

        # @param message [String]
        # @return [void]
        def warn(message) = say(YELLOW, "[inquirex-llm] WARNING: #{message}")

        # @param message [String]
        # @return [void]
        def info(message) = say(GREEN, "[inquirex-llm] #{message}")

        private

        def say(color, message)
          @io.puts(@io.respond_to?(:tty?) && @io.tty? ? "#{color}#{message}#{RESET}" : message)
        end
      end
    end
  end
end
