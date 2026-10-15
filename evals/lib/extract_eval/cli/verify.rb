# frozen_string_literal: true

module ExtractEval
  module CLI
    # Offline checks that every fixture agrees with its own flow.
    class Verify < Command
      desc "Check schemas against the DSLs and ground truth against the schemas (no API calls)"

      def call(**)
        all = Fixture.datasets.flat_map { Fixture.all(dataset: it) }
        failures = all.to_h { ["#{it.dataset}/#{it.name}", Verifier.new(it).problems] }.reject { |_, problems| problems.empty? }
        if failures.empty?
          status_box :success, "#{all.size} cases verified across #{Fixture.datasets.join(", ")}"
          return
        end

        failures.each { |name, problems| problems.each { status_box :error, "#{name}: #{it}", stream: err } }
        raise Error, "#{failures.size} case(s) failed verification"
      end
    end
  end
end
