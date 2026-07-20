# frozen_string_literal: true

require_relative "lib/inquirex/llm/version"

Gem::Specification.new do |spec|
  spec.name = "inquirex-llm"
  spec.version = Inquirex::LLM::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "LLM integration verbs for the Inquirex questionnaire engine"
  spec.description =
    "Extends the Inquirex DSL with an LLM-powered `extract` verb (alias: `clarify`) " \
    "that runs server-side to turn free-text answers into structured data. " \
    "Pluggable adapter interface keeps the gem LLM-agnostic; a NullAdapter ships for testing."

  spec.homepage = "https://github.com/inquirex/inquirex-llm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/inquirex/inquirex-llm"
  spec.metadata["changelog_uri"] = "https://github.com/inquirex/inquirex-llm/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Dir-based (not `git ls-files`) so the gemspec evaluates in contexts
  # without git — e.g. vendored as a path gem inside a slim Docker image.
  spec.files = Dir.chdir(__dir__) do
    Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) } +
      %w[README.md CHANGELOG.md LICENSE.txt].select { |f| File.exist?(f) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "inquirex", "~> 0.6"
end
