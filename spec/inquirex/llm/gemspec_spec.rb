# frozen_string_literal: true

# A library the gem requires at load time must ship with Ruby or be a declared
# runtime dependency. Ruby 4.1 stopped shipping prism as a default gem, and
# inquirex 0.11.0 reached it only through rubocop's development dependency:
# its suite stayed green while every consumer's `require "inquirex"` raised
# LoadError. This spec reads lib/ for what it requires instead of trusting a
# hand-kept list, so a new require cannot slip past it.
RSpec.describe "inquirex-llm.gemspec" do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:gemspec) { Gem::Specification.load(File.join(root, "inquirex-llm.gemspec")) }
  let(:runtime) { gemspec.runtime_dependencies.map(&:name) }

  # Every feature lib/ requires, other than this gem family's own files.
  # lib/inquirex/llm/evals is the eval suite's code: loaded only by
  # `require "inquirex/llm/evals"` from evals/.agent-eval.config.yml, it may
  # require agent-evals, which the gem does not depend on. The example below
  # proves the gem's own require never reaches it.
  let(:features) do
    Dir[File.join(root, "lib/**/*.rb")]
      .reject { |file| file.include?("/lib/inquirex/llm/evals") }
      .flat_map { |file| File.read(file).scan(/^\s*require\s+["']([^"']+)["']/).flatten }
      .uniq
      .reject { |feature| feature.start_with?("inquirex") }
  end

  # Ships with the running Ruby: default gems and extensions install their
  # files into rubylibdir/rubyarchdir; bundled gems (ostruct, and prism on
  # Ruby 4.1) do not.
  def shipped_with_ruby?(feature)
    [RbConfig::CONFIG["rubylibdir"], RbConfig::CONFIG["rubyarchdir"]].any? do |dir|
      Dir.glob(File.join(dir, "#{feature}{.rb,.bundle,.so}")).any?
    end
  end

  it "declares a runtime dependency for every library lib/ requires that Ruby does not ship" do
    undeclared = features.reject { |feature| shipped_with_ruby?(feature) }.reject do |feature|
      runtime.include?(Gem::Specification.find_by_path(feature)&.name)
    end

    expect(undeclared).to be_empty
  end

  it "does not load the eval suite, or agent-evals, with the gem" do
    # Bundler itself evaluates agent-evals' gemspec, which loads its version.rb; anything more is a leak.
    script = 'require "inquirex-llm"; ' \
             "exit(defined?(Inquirex::LLM::Evals) || $LOADED_FEATURES.grep(%r{inquirex/llm/evals|agent/evals\\.rb}).any? ? 1 : 0)"
    expect(system(RbConfig.ruby, "-rbundler/setup", "-e", script)).to be(true)
  end

  it "depends on the core gem at the version it is released with" do
    expect(gemspec.runtime_dependencies.find { |dep| dep.name == "inquirex" }.requirement.to_s).to eq("~> 0.12.1")
  end
end
