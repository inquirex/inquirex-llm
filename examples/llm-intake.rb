#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# Inquirex + LLM Demo Script
# =============================================================================
#
# The pitch:
#   "Deterministic DSL defines what data you need.
#    One LLM call extracts everything it can from one free-text answer.
#    The engine only asks the questions that are still unanswered."
#
# Usage:
#   ruby demo_llm_intake.rb               # scripted sample input
#   ruby demo_llm_intake.rb --interactive # type your own description
#
# Requires:
#   OPENAI_API_KEY (preferred) or ANTHROPIC_API_KEY in .env or environment
#
# Presentation tip: run in a 24pt+ terminal font so the audience can read along.
# =============================================================================

$LOAD_PATH.unshift File.expand_path("inquirex/lib",     __dir__)
$LOAD_PATH.unshift File.expand_path("inquirex-llm/lib", __dir__)

require "json"
require "inquirex"
require "inquirex/llm"

# -----------------------------------------------------------------------------
# .env loader — picks up OPENAI_API_KEY / ANTHROPIC_API_KEY from the repo root
# or any of the gem subdirectories. The first one found wins; real env vars
# already set in the shell take precedence.
# -----------------------------------------------------------------------------
def load_env_files!
  root = __dir__
  candidates = [
    File.join(root, ".env"),
    File.join(root, "inquirex-llm", ".env"),
    File.join(root, "inquirex-tty", ".env"),
    File.join(root, "inquirex",     ".env")
  ]
  candidates.each do |path|
    next unless File.file?(path)

    File.foreach(path) do |line|
      next if line.strip.empty? || line.start_with?("#")

      key, _, value = line.strip.partition("=")
      next if key.empty? || ENV.key?(key)

      ENV[key] = value.gsub(/\A["']|["']\z/, "")
    end
  end
end
load_env_files!

# -----------------------------------------------------------------------------
# 1. Define the flow — tax intake with an LLM "clarify" step up front
# -----------------------------------------------------------------------------
definition = Inquirex.define id: "tax-intake-llm-demo", version: "1.0.0" do
  meta title: "Tax Intake (LLM-assisted)"
  start :tell_me

  ask :tell_me do
    type :text
    question "Tell us about your tax situation in a few sentences."
    transition to: :extracted
  end

  clarify :extracted do
    from :tell_me
    prompt <<~PROMPT
      You are a tax-prep intake assistant. Extract structured data from the
      client's free-text description.

      STRICT VALUE RULES — you MUST use these exact string literals:

      filing_status: exactly ONE of:
        "single" | "married_filing_jointly" | "married_filing_separately"
        | "head_of_household" | "widowed"
      Use "" if the client did not indicate a filing status.

      dependents: integer count; null only when unmentioned.

      income_types: array. Each element MUST be ONE of these exact tokens:
        "W2"          — W-2 employment / wage job
        "1099"        — 1099 contracting / freelance
        "Business"    — self-employment / LLC / S-corp / C-corp / consulting business
        "Investment"  — stocks / bonds / crypto / mutual funds / dividends
        "Rental"      — rental property income
        "Retirement"  — 401(k) / IRA / pension / social security
      Do NOT emit "W-2", "self-employment", "investments", or any variant.
      Use [] if no income types are mentioned.

      state_filing: the primary US state as a capitalized English name,
      e.g. "California". Use "" if unmentioned.

      Only include a value when the client's text gives you concrete evidence.
    PROMPT
    schema filing_status: :string,
      dependents:    :integer,
      income_types:  :multi_enum,
      state_filing:  :string
    model :claude_sonnet
    temperature 0.0
    transition to: :filing_status
  end

  ask :filing_status do
    type :enum
    question "What is your filing status?"
    options({
      "single"                    => "Single",
      "married_filing_jointly"    => "Married Filing Jointly",
      "married_filing_separately" => "Married Filing Separately",
      "head_of_household"         => "Head of Household",
      "widowed"                   => "Widowed"
    })
    skip_if not_empty(:filing_status)
    transition to: :dependents
  end

  ask :dependents do
    type :integer
    question "How many dependents do you have?"
    skip_if not_empty(:dependents)
    transition to: :income_types
  end

  ask :income_types do
    type :multi_enum
    question "Select all income types that apply."
    options %w[W2 1099 Business Investment Rental Retirement]
    skip_if not_empty(:income_types)
    transition to: :state_filing
  end

  ask :state_filing do
    type :string
    question "Which state do you need to file in?"
    skip_if not_empty(:state_filing)
    transition to: :contact_info
  end

  ask :contact_info do
    type :string
    question "Your name and email?"
    transition to: :summary
  end

  summarize :summary do
    from_all
    prompt <<~PROMPT
      Based on all collected answers, return a JSON object:
        complexity:         "simple" | "moderate" | "complex"
        fee_estimate_low:   integer USD
        fee_estimate_high:  integer USD
        red_flags:          array of short strings (empty array if none)
        notes:              one-sentence summary for the preparer
    PROMPT
    transition to: :done
  end

  say :done do
    text "Thank you! A tax professional will review your intake and reach out."
  end
end

# -----------------------------------------------------------------------------
# 2. Pick an adapter. Preference: OpenAI → Anthropic → NullAdapter (offline)
# -----------------------------------------------------------------------------
def build_adapter
  return Inquirex::LLM::NullAdapter.new if ENV["INQUIREX_LLM_ADAPTER"] == "null"

  if ENV["OPENAI_API_KEY"] && !ENV["OPENAI_API_KEY"].empty?
    Inquirex::LLM::OpenAIAdapter.new
  elsif ENV["ANTHROPIC_API_KEY"] && !ENV["ANTHROPIC_API_KEY"].empty?
    Inquirex::LLM::AnthropicAdapter.new
  else
    warn "⚠️  No OPENAI_API_KEY or ANTHROPIC_API_KEY found — using NullAdapter."
    Inquirex::LLM::NullAdapter.new
  end
end

adapter = build_adapter
adapter_label =
  case adapter
  when Inquirex::LLM::OpenAIAdapter    then "OpenAI GPT"
  when Inquirex::LLM::AnthropicAdapter then "Anthropic Claude"
  else "the null adapter"
  end

# -----------------------------------------------------------------------------
# 3. Run the demo
# -----------------------------------------------------------------------------
engine = Inquirex::Engine.new(definition)
sep    = "=" * 72
line   = "-" * 72

puts
puts sep
puts "  INQUIREX + LLM DEMO — Tax Intake"
puts "  Powered by: #{adapter_label}"
puts sep
puts

# --- Step 1: free-text input ---
puts "Step 1 — #{engine.current_step.question}"
puts line

sample_input =
  if ARGV.include?("--interactive")
    print "\n> "
    $stdin.gets.to_s.chomp
  else
    input = "I'm married filing jointly, we have two kids. I work at Google on " \
            "a W-2 but my wife runs a consulting LLC and she also has a rental " \
            "property in Oakland. We have a Coinbase account with some crypto " \
            "trades. We live in California."
    puts "\n> #{input}"
    input
  end

engine.answer(sample_input)

# --- Step 2: LLM extraction ---
puts
puts line
puts "🧠  Asking #{adapter_label} to extract structured data…"
puts line

llm_step = engine.current_step
t0 = Time.now
result = adapter.call(llm_step, engine.answers)
elapsed = Time.now - t0

engine.answer(result)
engine.prefill!(result)

puts
puts "📋 Extracted in #{elapsed.round(2)}s:"
result.each do |key, value|
  if value.nil? || (value.respond_to?(:empty?) && value.empty?)
    puts "  ❓ #{key}: (unknown — will ask)"
  else
    puts "  ✅ #{key}: #{value.inspect}"
  end
end

# --- Step 3: what got skipped ---
ask_ids   = definition.steps.select { |_, n| n.verb == :ask }.keys
skippable = ask_ids.select do |id|
  node = definition.step(id)
  node.respond_to?(:skip_if) && node.skip_if && node.skip_if.evaluate(engine.answers)
end

puts
puts sep
puts "  RESULT — questions skipped vs. still to ask"
puts sep
puts "   Total ask steps in flow:       #{ask_ids.size}"
puts "   Auto-answered by LLM:          #{skippable.size}"
puts "   Remaining to ask the user:     #{ask_ids.size - skippable.size}"
puts
puts "   Skipped: #{skippable.join(", ")}"
puts "   Still needed: #{(ask_ids - skippable).join(", ")}"

# --- Step 4: JSON payload that the frontend would POST ---
puts
puts sep
puts "  COLLECTED DATA (what the frontend would POST back)"
puts sep
puts JSON.pretty_generate(engine.answers)

# --- Step 5: LLM summary ---
summary_node = definition.step(:summary)
if summary_node && !adapter.is_a?(Inquirex::LLM::NullAdapter)
  puts
  puts sep
  puts "🧠  Asking #{adapter_label} for an intake summary…"
  puts sep
  summary = adapter.call(summary_node, engine.answers)
  puts
  puts JSON.pretty_generate(summary)
end

puts
puts sep
puts "  ✅ Demo complete."
puts "  Deterministic DSL + Probabilistic LLM = Smart Intake"
puts sep
puts
