# frozen_string_literal: true

require "inquirex/llm/evals"
require "tmpdir"

RSpec.describe Inquirex::LLM::Evals::Dataset do
  subject(:dataset) { described_class.new("05-managed-it-services", root: File.expand_path("../../../../evals", __dir__)) }

  it "loads the flow's one extract step" do
    expect(dataset.node.id).to eq(:understanding)
    expect(dataset.source_step).to eq(:situation)
  end

  it "reads schema.rb as the schema the DSL declares" do
    expect(dataset.schema).to eq(dataset.node.schema)
    expect(dataset.schema.field_names).to include(:seat_count, :compliance)
  end

  its(:problems) { is_expected.to be_empty }

  describe "problems" do
    let(:root) { Dir.mktmpdir }
    let(:dir) { File.join(root, "datasets", "x").tap { FileUtils.mkdir_p(it) } }
    let(:dsl) do
      <<~RUBY
        Inquirex.define do
          start :tell_me
          ask(:tell_me) { type :text; question "Tell me."; transition to: :understanding }
          extract(:understanding) { from :tell_me; prompt "Extract."; schema dependents: :integer; transition to: :done }
          say(:done) { text "Done." }
        end
      RUBY
    end

    after { FileUtils.rm_rf(root) }

    def write(name, text) = File.write(File.join(dir, name), text)

    it "is empty when schema.rb matches the DSL" do
      write("dsl.rb", dsl)
      write("schema.rb", "{ dependents: :integer }")
      expect(described_class.new("x", root: root).problems).to be_empty
    end

    it "names a schema.rb that drifted from the DSL" do
      write("dsl.rb", dsl)
      write("schema.rb", "{ dependents: :string }")
      expect(described_class.new("x", root: root).problems).to eq(["x/schema.rb differs from the DSL's extract schema"])
    end

    it "names a missing dsl.rb instead of raising" do
      write("schema.rb", "{ dependents: :integer }")
      expect(described_class.new("x", root: root).problems.first).to match(/x: Errno::ENOENT: .*dsl\.rb/)
    end

    it "names a flow with two extract steps" do
      second = 'extract(:done) { from :tell_me; prompt "Again."; schema a: :string; transition to: :end }; say(:end) { text "." }'
      write("dsl.rb", dsl.sub('say(:done) { text "Done." }', second))
      write("schema.rb", "{ dependents: :integer }")
      expect(described_class.new("x", root: root).problems.first).to include("expected one extract step with a schema, found 2")
    end
  end
end
