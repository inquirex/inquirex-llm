# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in inquirex-llm.gemspec
gemspec

group :development, :test do
  gem "rake"

  gem "rspec"
  gem "rspec-its"
  gem "simplecov"

  gem "bundle-audit"
  gem "coverage-badge"
  gem "rubocop"
  gem "rubocop-rspec"

  gem "yard"
end

group :evals do
  gem "braintrust", require: "braintrust/setup"
  gem "llm-evals", "~> 0.5.0"
  gem "ruby_llm", "= 2.1.1"
end
