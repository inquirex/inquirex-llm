# frozen_string_literal: true

require "simplecov"
require "coverage/badge"

SimpleCov.skip /spec/
SimpleCov.start do
  self.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    Coverage::Badge::Formatter
  ]
end

SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "Coverage: #{SimpleCov.result.covered_percent.round(2)}%" # rubocop:disable RSpec/Output
  FileUtils.mv("coverage/badge.svg", "docs/badges/coverage_badge.svg")
end

require "inquirex"
require "inquirex/llm"
require "rspec/its"

# Sets ENV variables for the duration of a block (nil deletes one), and
# rebuilds Inquirex::LLM.configuration on the way in and out, since it reads
# ENV only once. Restores every variable it touched, even on failure.
module EnvHelper
  # @param vars [Hash{String => String, nil}]
  # @yield with ENV changed
  def with_env(vars)
    prior = vars.keys.to_h { |name| [name, ENV.fetch(name, nil)] }
    vars.each { |name, value| value.nil? ? ENV.delete(name) : ENV.store(name, value) }
    Inquirex::LLM.reset_configuration!
    yield
  ensure
    prior&.each { |name, value| value.nil? ? ENV.delete(name) : ENV.store(name, value) }
    Inquirex::LLM.reset_configuration!
  end
end

RSpec.configure do |config|
  config.include EnvHelper
  # A configure block in one example must not leak into the next.
  config.after { Inquirex::LLM.reset_configuration! }
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.order = :random
  Kernel.srand config.seed
end
