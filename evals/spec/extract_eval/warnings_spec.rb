# frozen_string_literal: true

RSpec.describe ExtractEval::Warnings do
  subject(:warnings) { described_class.new }

  it "skips blank lines" do
    warnings.puts("one", "", "  ")
    expect(warnings.to_a).to eq(["one"])
  end

  describe "#capture" do
    let(:stderr) { $stderr }

    before do
      warnings.capture do
        warn "from Kernel#warn"
        Braintrust::Log.warn("from Braintrust")
        RubyLLM.logger.warn("from RubyLLM")
      end
    end

    it { expect(warnings.to_a.join("\n")).to include("from Kernel#warn", "from Braintrust", "from RubyLLM") }
    it { expect($stderr).to be(stderr) }
  end

  it "saves the warnings, one paragraph each" do
    path = File.join(Dir.mktmpdir, "w.log")
    warnings.record("a").record("b").save(path)
    expect(File.read(path)).to eq("a\n\nb\n")
  end
end
