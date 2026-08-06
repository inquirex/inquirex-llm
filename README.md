[![Gem Version](https://badge.fury.io/rb/inquirex-llm.svg)](https://badge.fury.io/rb/inquirex-llm) [![Ruby](https://github.com/inquirex/inquirex-llm/actions/workflows/main.yml/badge.svg)](https://github.com/inquirex/inquirex-llm/actions/workflows/main.yml) ![Coverage](docs/badges/coverage_badge.svg)

# inquirex-llm

LLM integration verbs for the [Inquirex](https://github.com/inquirex/inquirex) questionnaire engine.

Extends the core DSL with two server-side verbs: `extract` (alias: `clarify`), which turns free-text answers into structured data, and `summarize`, which closes a flow with a prose summary of the whole session. Ships with a pluggable adapter interface and a `NullAdapter` for testing. (`describe` and `detour` are temporarily parked.)

`inquirex` is a pure Ruby, declarative, rules-driven questionnaire engine for building conditional intake forms, qualification wizards, and branching surveys.

> [!IMPORTANT]
>
> Note that `inquirex-llm` is part of an entire ecosystem that contains:
>
> - [`inquirex`](https://github.com/inquirex/inquirex)
> - [`inquirex-llm`](https://github.com/inquirex/inquirex-llm)
> - [`inquirex-tty`](https://github.com/inquirex/inquirex-tty)
> - [`inquirex-widget`](https://github.com/inquirex/inquirex-widget) (`npmjs` module [`inquirex-widget`](https://www.npmjs.com/package/inquirex-widget), formerly `@kigster/inquirex-js`)
>
> For a presentation about these gems and what they do please watch the [RubySF presentation](https://www.youtube.com/watch?v=iaoKW7Ap3_M&t=1s) and you can also [view the slides from the presentation](https://reinvent.one/images/talks/pdfs/2026.inquirex.pdf).
>
> Finally, the SaaS application [qualified.at](https://qualified.at) allows users to leverage the ecosystem by creating their own custom lead intake flows and integrating them on their own sites.

## Usage

`require "inquirex-llm"` injects the LLM verbs into the core `Inquirex.define` DSL.

No separate entry point needed.

```ruby
require "inquirex"
require "inquirex-llm"

definition = Inquirex.define id: "tax-intake-2026", version: "1.0.0" do
  start :description

  ask :description do
    type :text
    question "Describe your business in a few sentences."
    transition to: :extracted
  end

  extract :extracted do
    from :description
    prompt "Extract structured business information from the description."
    schema industry:          :string,
           entity_type:       :string,
           employee_count:    :integer,
           estimated_revenue: :currency
    model :claude_sonnet
    temperature 0.2
    transition to: :done
  end
  
  say :done do
    text "Thank you! We'll be in touch."
  end
end
```

All core verbs (`ask`, `say`, `header`, `btw`, `warning`, `confirm`) and widget hints work alongside LLM verbs in the same `Inquirex.define` block.

### Loading stored flows

Since inquirex 0.7.0, `Inquirex.load_dsl` validates source against a **default-deny** allowlist before evaluating it — a word nobody declared is a violation, not an oversight. Requiring this gem registers its own vocabulary (`extract`, `clarify`, `summarize`, and the methods legal inside their blocks), so a flow stored in a database or authored in a visual builder loads normally:

```ruby
Inquirex.load_dsl(customer.flow_dsl)   # validates, then evaluates
```

`fallback` is the one deliberate exception: it takes a Ruby block, which is exactly what static validation cannot vet, so it is excluded from the allowlist rather than permitted. Flows that need it must be loaded from your own source with `unsafe: true`.

Registration is skipped on inquirex versions predating the allowlist, so the gem still works against them.

## Currently Supported LLM Verbs

### `extract` (alias: `clarify`)

Extract structured data from a free-text answer. Requires `from` (or `from_all`), `prompt`, and `schema`. The stored/serialized verb is always `"extract"`; `clarify` is a DSL-only alias.

```ruby
extract :business_extracted do
  from :business_description
  prompt "Extract structured business information."
  schema industry: :string, employee_count: :integer, revenue: :currency
  model :claude_sonnet
  temperature 0.2
  max_tokens 1024
  transition to: :next_step
end
```

### `summarize`

Closes a flow with a multi-paragraph prose summary of the whole session, written for the user to read and keep.

```ruby
Inquirex.define id: "depreciation-help" do
  start :intro

  say(:intro) { text "Depreciation spreads an asset's cost over its useful life."; transition to: :asset }
  ask(:asset) { type :enum; question "What kind of asset?"; options vehicle: "A vehicle", building: "A building" }

  summarize :wrap_up do
    temperature 0.4
  end
end
```

Two things make it different from every other verb.

**It reads the transcript, not the answers.** The core gem's [text accumulators](https://github.com/inquirex/inquirex#text-accumulators-the-session-transcript) record everything the user was shown and every answer they gave. That is what `summarize` is given. It matters because a flow that mostly *explains* things — a help widget, an explainer — collects almost no answers, so a summary built from the answers hash would have nothing to say. Declaring `summarize` adds a `:transcript` accumulator automatically if the flow declares no text accumulator of its own.

**The gem owns the prompt.** `Inquirex::LLM::Prompts::SUMMARIZE` is a constant, and adapters read it from there rather than from `node.prompt`. A flow author who could replace it could make the summary assert things the session never established, over a signature that still reads as the application's own words — so `prompt` is rejected at definition time rather than ignored at runtime, and a hand-forged or tampered node cannot substitute its own instructions either.

The prompt constrains the model to what the transcript establishes, and to the markdown subset a renderer can lay out and print: headings, lists, blockquotes, emphasis, inline code, and fenced code blocks.

#### What it refuses, and why

| Rejected                                    | Because                                      |
| ------------------------------------------- | -------------------------------------------- |
| `prompt`                                    | its prompt is owned by the gem               |
| `schema`                                    | it returns prose, not fields                 |
| `from` / `from_all`                         | it always reads the whole session transcript |
| a transition, or any step declared after it | it must be the last step in the flow         |
| a second `summarize` step                   | a flow may close with only one               |

Each raises `Errors::DefinitionError` naming the reason.

`temperature`, `model`, and `max_tokens` remain available: they change how the summary is generated, not what it is allowed to say.

#### Calling it

`summarize` uses its own adapter method, because nothing about the call resembles an extraction — the prompt is the gem's, the input is the transcript, and the result is a markdown `String` rather than a schema-shaped `Hash`:

```ruby
adapter = Inquirex::LLM::AnthropicAdapter.new(api_key: ENV["ANTHROPIC_API_KEY"])
markdown = adapter.summarize(engine.current_step, engine.text(:transcript))
```

An adapter that implements only `#call` keeps working for `extract` and raises `NotImplementedError` the first time a flow asks it to summarize — loudly, rather than returning something that looks like a summary and is not. An empty transcript raises `Errors::AdapterError` rather than asking a model to invent one.

The [inquirex-widget](https://github.com/inquirex/inquirex-widget) renders the result with **Close** and **Print** buttons; markdown is sanitized against a strict element allowlist before it reaches the page.

## Schema: Question References (preferred)

Most extract schemas exist to pre-fill questions asked later in the same flow. Declaring those fields twice — once in the schema, once in the question — invites drift, and worse: a hand-typed `income_types: :multi_enum` gives the LLM no idea which values are legal, so its answers won't match the question's options.

Instead, pass the schema as a list of question ids:

```ruby
extract :extracted do
  from :description
  prompt "Extract the client's filing status, dependents, and income types."
  schema :filing_status, :dependents, :income_types
  transition to: :filing_status
end

ask :filing_status do
  type :enum
  question "Filing status?"
  options({ "single" => "Single", "mfj" => "Married Filing Jointly" })
  transition to: :dependents
end
# ...
```

Each symbol is resolved against the flow at definition time — references may point **forward** to questions defined after the extract step. The gem looks up the question's declared type, and for `:enum` / `:multi_enum` questions folds the exhaustive list of allowed option values into the JSON schema sent to the LLM. The adapters then instruct the model to answer using only those values, so extracted answers always match the downstream question's options (and `Engine#prefill!` can skip the question).

A symbol that matches no `ask`/`confirm` step in the flow fails validation with `Inquirex::LLM::Errors::DefinitionError` — as do references to display-only steps and other LLM steps.

Both forms compose. Use keywords for output fields that have no corresponding question:

```ruby
schema :filing_status, :income_types, confidence: :decimal
```

### `prompt :auto`

When the schema is built from question references, the schema already tells the LLM the field names, types, and allowed values — the main thing a hand-written prompt still adds is the questions' own wording. `prompt :auto` generates exactly that at definition time:

```ruby
extract :extracted do
  from :description
  prompt :auto
  schema :filing_status, :dependents, :income_types
  transition to: :filing_status
end
```

The generated prompt enumerates each referenced question's text ("- filing_status: What is your filing status for 2025?" …), lists explicit keyword fields by name and type, and instructs the model to leave unsupported fields empty. Generation happens at build time, so the wire format and adapters always see a concrete prompt string — `:auto` never leaves the DSL. It requires at least one question reference; with only explicit `key: :type` fields there is no question wording to generate from, and validation fails.

Write the prompt by hand when you need domain framing the questions don't carry ("for tax filing purposes", "map S-Corp to s_corp") — an explicit prompt always wins.

## DSL Methods (inside LLM verb blocks)

| Method                          | Purpose                                              | Required                                                   |
| ------------------------------- | ---------------------------------------------------- | ---------------------------------------------------------- |
| `prompt "..."` / `prompt :auto` | LLM prompt template, or generated from question refs | `extract`; **rejected** on `summarize`                     |
| `schema :question_id, ...`      | Fields resolved from questions (types + options)     | `extract` (this or keywords); **rejected** on `summarize`  |
| `schema key: :type, ...`        | Explicit field => type pairs                         | `extract` (this or refs); **rejected** on `summarize`      |
| `from :step_id`                 | Source step(s) whose answers feed the LLM            | `extract` (or use `from_all`); **rejected** on `summarize` |
| `from_all`                      | Pass all collected answers to the LLM                | Alternative to `from`; **rejected** on `summarize`         |
| `model :claude_sonnet`          | Optional model hint for the adapter                  | No                                                         |
| `temperature 0.3`               | Optional sampling temperature                        | No                                                         |
| `max_tokens 1024`               | Optional max output tokens                           | No                                                         |
| `fallback { \|answers\| ... }`  | Server-side fallback (stripped from JSON)            | No                                                         |
| `transition to: :step`          | Conditional transition (same as core)                | No; **rejected** on `summarize`                            |
| `skip_if rule`                  | Skip step when condition is true                     | No                                                         |

`summarize` rejects the content-shaping methods rather than ignoring them — see [`summarize`](#summarize) for each refusal and its reason.

## Engine Integration

The engine treats LLM steps as collecting steps. The server adapter processes the LLM call and feeds the result back:

```ruby
engine = Inquirex::Engine.new(definition)

engine.answer("I run an LLC with 15 employees, ~$2M revenue.")
# engine.current_step_id => :extracted

# Server-side: adapter calls the LLM
adapter = MyLlmAdapter.new
result = adapter.call(engine.current_step, engine.answers)
# => { industry: "Technology", employee_count: 15, revenue: 2_000_000.0 }

engine.answer(result)
# engine.current_step_id => :summary
```

For testing, use `NullAdapter` which returns schema-conformant placeholder values without any API calls:

```ruby
adapter = Inquirex::LLM::NullAdapter.new
result = adapter.call(engine.current_step)
# => { industry: "", employee_count: 0, revenue: 0.0 }
```

## Built-in Adapters

| Class                                   | Provider  | API                                | Auth                      | Key env var         |
| --------------------------------------- | --------- | ---------------------------------- | ------------------------- | ------------------- |
| `Inquirex::LLM::NullAdapter`            | —         | none (placeholders)                | none                      | —                   |
| `Inquirex::LLM::AnthropicAdapter`       | Anthropic | `/v1/messages`                     | `x-api-key` header        | `ANTHROPIC_API_KEY` |
| `Inquirex::LLM::OpenAIAdapter`          | OpenAI    | `/v1/chat/completions` (JSON mode) | `Authorization: Bearer …` | `OPENAI_API_KEY`    |
| `Inquirex::LLM::LittleLLMAdapter` (TBD) | Any       | OpenAI Compatible API              | OpenAI Compatible Auth    | Provider Specific   |

The Anthropic and OpenAI adapters use `net/http` (stdlib, no extra dependency), inject the declared `schema` into the system prompt as a strict JSON contract, and raise `Inquirex::LLM::Errors::AdapterError` on HTTP / parse failures and `SchemaViolationError` when the model's output is missing declared fields.

### AnthropicAdapter

```ruby
adapter = Inquirex::LLM::AnthropicAdapter.new(
  api_key: ENV["ANTHROPIC_API_KEY"],
  model:   "claude-sonnet-4-20250514"   # or pass the short symbol in the DSL
)
```

Recognized `model :symbol` values in the DSL: `:claude_sonnet`, `:claude_haiku`, `:claude_opus` (mapped to the current concrete model ids).

### OpenAIAdapter

```ruby
adapter = Inquirex::LLM::OpenAIAdapter.new(
  api_key: ENV["OPENAI_API_KEY"],
  model:   "gpt-4o-mini"
)
```

Uses Chat Completions with `response_format: { type: "json_object" }` so the model is constrained to return valid JSON. Recognized DSL symbols: `:gpt_4o`, `:gpt_4o_mini`, `:gpt_4_1`, `:gpt_4_1_mini`. For cross-provider portability, the adapter also accepts the Claude symbols (`:claude_sonnet` → `gpt-4o` etc.) so a flow file that says `model :claude_sonnet` runs unchanged against either provider.

## LLM-assisted Pre-fill Pattern

A common use case: ask *one* open-ended question, let the LLM extract answers for *many* downstream questions, and only prompt the user for what the LLM couldn't determine. This is what the core engine's `Engine#prefill!` is for:

```ruby
definition = Inquirex.define id: "tax-intake" do
  start :describe

  ask :describe do
    type :text
    question "Describe your 2025 tax situation."
    transition to: :extracted
  end

  extract :extracted do
    from :describe
    prompt "Extract: filing_status, dependents, income_types, state_filing."
    schema filing_status: :string,
           dependents:    :integer,
           income_types:  :multi_enum,
           state_filing:  :string
    model :claude_sonnet
    transition to: :filing_status
  end

  ask :filing_status do
    type :enum
    question "Filing status?"
    options %w[single married_filing_jointly head_of_household]
    skip_if not_empty(:filing_status)     # ← the whole trick
    transition to: :dependents
  end

  ask :dependents do
    type :integer
    question "How many dependents?"
    skip_if not_empty(:dependents)
    transition to: :income_types
  end
  # …and so on for every field in the extract schema
end

engine  = Inquirex::Engine.new(definition)
adapter = Inquirex::LLM::OpenAIAdapter.new  # or AnthropicAdapter

engine.answer("I'm MFJ with two kids in California, W-2 plus some crypto.")
result = adapter.call(engine.current_step, engine.answers)
engine.answer(result)         # stored under :extracted
engine.prefill!(result)       # splats into top-level answers

# Every downstream step whose skip_if rule now evaluates true gets
# auto-skipped by the engine. engine.current_step_id jumps straight to
# whichever field the LLM couldn't fill in.
```

`Engine#prefill!` is non-destructive (won't clobber an answer the user already gave), ignores `nil`/empty values so they don't spuriously trigger `not_empty`, and auto-advances past any step whose `skip_if` now evaluates true. See [examples/09_tax_preparer_llm.rb](../inquirex-tty/examples/09_tax_preparer_llm.rb) for a complete runnable flow, or the repo-level `demo_llm_intake.rb` for a scripted end-to-end walkthrough.

## JSON Serialization

LLM steps serialize with `"requires_server": true` so the JS widget knows to round-trip to the server. LLM metadata lives under an `"llm"` key:

```json
{
  "verb": "extract",
  "requires_server": true,
  "transitions": [{ "to": "next_step", "requires_server": true }],
  "llm": {
    "prompt": "Extract structured business information.",
    "schema": {
      "industry": "string",
      "employee_count": "integer",
      "revenue": "currency",
      "income_types": {
        "type": "multi_enum",
        "values": ["W2", "business", "crypto"]
      }
    },
    "from_steps": ["business_description"],
    "model": "claude_sonnet",
    "temperature": 0.2,
    "max_tokens": 1024
  }
}
```

Unconstrained fields serialize as a plain type string; fields resolved from `:enum` / `:multi_enum` questions serialize as `{ "type": ..., "values": [...] }` so any consumer (the JS widget, a server adapter) sees the full contract. Fallback procs are stripped from JSON (server-side only).

## Custom Adapter

Subclass `Inquirex::LLM::Adapter` and implement `#call(node, answers)`:

```ruby
class MyLlmAdapter < Inquirex::LLM::Adapter
  def call(node, answers)
    source = source_answers(node, answers)
    response = my_llm_client.complete(
      node.prompt,
      context: source,
      model: node.model,
      temperature: node.temperature
    )
    result = parse_response(response)
    validate_output!(node, result)
    result
  end
end
```

The base class provides `#source_answers` (gathers relevant answers) and `#validate_output!` (checks schema conformance).

## Future Possible LLM Verbs

### `describe`

Generate natural-language text from structured data. Requires `from` and `prompt`. No schema needed.

```ruby
describe :business_narrative do
  from :business_extracted
  prompt "Write a brief narrative of this business for the intake report."
  transition to: :next_step
end
```

### `detour` (parked)

Dynamically generate follow-up questions based on an answer. The server adapter handles presenting the generated questions and collecting responses. Requires `from`, `prompt`, and `schema`.

```ruby
detour :followup do
  from :description
  prompt "Generate 2-3 follow-up questions to clarify the tax situation."
  schema questions: :array, answers: :hash
  transition to: :next_step
end
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

© 2026 Konstantin Gredeskoul.

Distributed under the MIT License.

See [LICENSE.txt](LICENSE.txt) for details.
