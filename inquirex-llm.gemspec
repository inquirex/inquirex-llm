# frozen_string_literal: true

require_relative "lib/inquirex/llm/version"

Gem::Specification.new do |spec|
  spec.name = "inquirex-llm"
  spec.version = Inquirex::LLM::VERSION
  spec.authors = ["Konstantin Gredeskoul"]
  spec.email = ["kigster@gmail.com"]

  spec.summary = "LLM integration verbs for the Inquirex questionnaire engine"
  spec.description = "Extends the Inquirex DSL with four LLM-powered verbs — clarify, describe, " \
                     "summarize, and detour — that run server-side to extract structured data, " \
                     "generate text, and dynamically branch flows. Pluggable adapter interface " \
                     "keeps the gem LLM-agnostic; a NullAdapter ships for testing."
  spec.homepage = "https://github.com/inquirex/inquirex-llm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/inquirex/inquirex-llm"
  spec.metadata["changelog_uri"] = "https://github.com/inquirex/inquirex-llm/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "inquirex", "~> 0.2"
end
