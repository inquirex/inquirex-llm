# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in inquirex-llm.gemspec
gemspec

group :development, :test do
  gem "rake"

  gem "rspec"
  gem "simplecov"
  gem "rspec-its"

  gem "bundle-audit"
  gem "rubocop"
  gem "rubocop-rspec"
  gem "coverage-badge"

  gem "yard"
end

group :evals do
  gem "braintrust", require: "braintrust/setup"
  gem "ruby_llm", "= 2.1.1"
end


