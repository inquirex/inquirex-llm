# frozen_string_literal: true

module ExtractEval
  module CLI
    class Version < Command
      desc "Print the version"

      def call(**)
        out.puts ExtractEval::VERSION
      end
    end
  end
end
