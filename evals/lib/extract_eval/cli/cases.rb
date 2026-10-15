# frozen_string_literal: true

module ExtractEval
  module CLI
    # The fixtures, without calling anything.
    class Cases < Command
      desc "List the eval cases in every dataset"

      def call(**)
        rows = Fixture.datasets.flat_map { Fixture.all(dataset: it) }.map do |fixture|
          answered = fixture.truth.values.count { !it.nil? }
          [fixture.dataset, fixture.name, fixture.difficulty, "#{answered}/#{fixture.schema.size}", fixture.text.split.size]
        end
        table(rows, header: %w[dataset case difficulty answered words])
      end
    end
  end
end
