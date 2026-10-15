# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  root File.expand_path("..", __dir__)
  skip "/spec/"
  minimum_coverage 95
end

require "rspec/its"
require "stringio"
require "tmpdir"
require "extract_eval"
require "braintrust"

Dir[File.join(__dir__, "support", "*.rb")].each { require it }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { it.syntax = :expect }
  config.order = :random
end
