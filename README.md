[![Gem Version](https://badge.fury.io/rb/inquirex-llm.svg)](https://badge.fury.io/rb/inquirex-llm) [![Ruby](https://github.com/inquirex/inquirex-llm/actions/workflows/main.yml/badge.svg)](https://github.com/inquirex/inquirex-llm/actions/workflows/main.yml) ![Coverage](docs/badges/coverage_badge.svg)

> [!CAUTION]
> 
> If you have not read the README for the [inquirex](https://github.com/inquirex/inquirex) Ruby gem, which constitutes the basis for this gem and a few others, please stop reading here, and head over there and read the README, or have Claude or your favorite model summarize it for you, but beware that **this README** assumes **full understanding of what `inquirex` does**, how it works, and what it's for.

---

# `inquirex-llm` — "Making Forms... Less Clueless Since 2026 😂"

This Ruby gem is meant to be used with its parent `inquirex` gem. It enriches `inquirex` 's DSL with additional keywords you can use in your form descriptions. 

> [!NOTE]
> 
> If you use inquirex to show the forms inside a web copilot, similar to how they are done on the site [Qualified.At](https://qualified.at) and especially on their [ten separate demos](https://qualified.at/demos) — which is, they generate a floating Copilot with form questions as widgets inside entirely via JavaScript package [inquirex-widget](https://www.npmjs.com/package/inquirex-widget) and run the user through the questions without any round-trips to the server, as the entire DSL is passed at once in the beginning as JSON; and so until the user (a lead) finishes the form, there are no server trips necessary.  
> 
> However, for the keywords added by this gem to work, they must be sent to some sort of backend API server, because pure client-side calling of LLM APIs would expose the API key. 
> 
> When used within the context of a Terminal GUI (ie., [`inquirex-tty`](https://github.com/inquirex/inquirex-tty), the form is rendered and run through by the same Ruby VM process, and therefore you just need your API keys set in your environment. 
> 
> And if you ever want to encrypt your development keys and commit them with your repo, there is no tool like [**sopsy**](https://sopsy-cli.dev), GitHub: <https://github.com/kigster/sopsy>. Sopsy is a Rust-based encryption tool that stores private keys inside your MacBook's secure enclave chip, or on a YubiKey. 

---

## The New Keywords

This gem extends the core DSL with two server-side verbs: 

* `extract` (alias: `clarify`), which turns free-text answers into structured data, and 

* `summarize`, which closes a flow with a prose summary of the whole session. 

Ships with a pluggable adapter interface and a `NullAdapter` for testing.

> [!IMPORTANT]
>
> As we mentioned above, `inquirex-llm` is part of an entire ecosystem that comprises:
>
> - [`inquirex`](https://github.com/inquirex/inquirex) — the base gem that defines the core DSL and validation rules.
> - [`inquirex-llm`](https://github.com/inquirex/inquirex-llm) — this gem extends it with AI-enabled features
> - [`inquirex-tty`](https://github.com/inquirex/inquirex-tty) — a TUI user interface gem that converts the form DSLs into a proper terminal screen wizard/questionaire, and could be combined with the LLM gem to offer AI-enabled form features.
>
> In addition to the Ruby Gems, there is an NPM JavaScript module that also converts DSLs into a Copilot-style questionnaire for use in a web application.  
>
> - [`inquirex-widget`](https://github.com/inquirex/inquirex-widget), and it's npmjs module [`inquirex-widget`](https://www.npmjs.com/package/inquirex-widget)
>
> For a presentation about these gems and what they collectively do, please check out the [Slides from the RubySF presentation](https://kig.re/speaking/2026.inquirex) (or the [video](https://www.youtube.com/watch?v=iaoKW7Ap3_M&t=1s) if you prefer.
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
    use_first_available_model "deepseek/deepseek-v4.1-flash", "anthropic/claude-haiku-5.5"
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

Since Inquirex 0.7.0, `Inquirex.load_dsl` validates source against a **default-deny** allowlist before evaluating it — a word nobody declared is a violation, not an oversight. Requiring this gem registers its own vocabulary (`extract`, `clarify`, `summarize`, and the methods legal inside their blocks), so a flow stored in a database or authored in a visual builder loads normally:

```ruby
Inquirex.load_dsl(customer.flow_dsl)   # validates, then evaluates
```

`fallback` is the one deliberate exception: it takes a Ruby block, which is exactly what static validation cannot vet, so it is excluded from the allowlist rather than permitted. Flows that need it must be loaded from your own source with `unsafe: true`.

Registration is skipped on Inquirex versions predating the allowlist, so the gem still works against them.

## Currently Supported LLM Verbs

### `extract` (alias: `clarify`)

Extract structured data from a free-text answer. Requires `from` (or `from_all`), `prompt`, and `schema`. The stored/serialized verb is always `"extract"`; `clarify` is a DSL-only alias.

```ruby
extract :business_extracted do
  from :business_description
  prompt "Extract structured business information."
  schema industry: :string, employee_count: :integer, revenue: :currency
  use_first_available_model "deepseek/deepseek-v4.1-flash", "anthropic/claude-haiku-5.5"
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
    use_first_available_model "anthropic/claude-sonnet-5.5", "anthropic/claude-haiku-5.5"
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

- `temperature(float between 0..1)`
- `model(symbol)` (deprecated, but still works until 1.0.0)
- `use_first_available_model(array of strings)` is the replacement for `model` allowing the choice of a model best suited for a specific question or a task.
- `max_tokens(integer)` 

These parameters change how the summary is generated, not what it can say.

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

| Method                                          | Purpose                                                                                                                 | Required                                                   |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `prompt "..."` / `prompt :auto`                 | LLM prompt template, or generated from question refs                                                                    | `extract`; **rejected** on `summarize`                     |
| `schema :question_id, ...`                      | Fields resolved from questions (types + options)                                                                        | `extract` (this or keywords); **rejected** on `summarize`  |
| `schema key: :type, ...`                        | Explicit field => type pairs                                                                                            | `extract` (this or refs); **rejected** on `summarize`      |
| `from :step_id`                                 | Source step(s) whose answers feed the LLM                                                                               | `extract` (or use `from_all`); **rejected** on `summarize` |
| `from_all`                                      | Pass all collected answers to the LLM                                                                                   | Alternative to `from`; **rejected** on `summarize`         |
| `model :claude_sonnet`                          | Optional model hint for the adapter                                                                                     | No                                                         |
| `use_first_available_model "vendor/model", ...` | Models this step prefers, best first; the first one a usable vendor serves is used. Overrides `model`. Server-side only | No                                                         |
| `temperature 0.3`                               | Optional sampling temperature                                                                                           | No                                                         |
| `max_tokens 1024`                               | Optional max output tokens                                                                                              | No                                                         |
| `fallback { \|answers\| ... }`                  | Server-side fallback (stripped from JSON)                                                                               | No                                                         |
| `transition to: :step`                          | Conditional transition (same as core)                                                                                   | No; **rejected** on `summarize`                            |
| `skip_if rule`                                  | Skip step when condition is true                                                                                        | No                                                         |

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

The built-in adapters return an `Inquirex::LLM::Extraction` for an `extract` step. It is the Hash above (a `Hash` subclass, so `prefill!`, `==` and JSON serialization see only the values) carrying two more things from the one LLM call that produced it: `raw`, the JSON exactly as the model sent it before enum values were canonicalized (`raw[:entity_type] # => "LLC"` where `result[:entity_type] # => "llc"`), and `usage`, the tokens and, when the provider reports it, the cost.

For testing, use `NullAdapter` which returns schema-conformant placeholder values without any API calls:

```ruby
adapter = Inquirex::LLM::NullAdapter.new
result = adapter.call(engine.current_step)
# => { industry: "", employee_count: 0, revenue: 0.0 }
```

## Model routing (0.13.0+)

> [!NOTE]
>
> For a fun read on how this feature came to be, please read the blog post [Home-made Evals Taste Better](https://kig.re/2026/11/02/llm-evals-is-a-ruby-gem-for-testing-probabilistic-assumptions-in-your-AI-datasets.html)

Different steps want different models: an eval run (see [Evals](#evals)) may show that DeepSeek wins one dataset and Claude Haiku another. Routing lets the host list the vendors and models it prefers once, and lets each LLM step name its own ordered list. The full reasoning is in [docs/decisions/prioritized-model-selection.md](docs/decisions/prioritized-model-selection.md).

Models are always named the OpenRouter way, `"vendor/model"`: `"openai/gpt-4.1-mini"`, `"anthropic/claude-haiku-5.5"`, `"deepseek/deepseek-v4.1-flash"`.

```ruby
Inquirex::LLM.configure do |c|
  c.llm_vendors_priority        = %i[openrouter openai anthropic typesafe]
  c.llm_models_priority         = %w[deepseek/deepseek-v4.1-flash anthropic/claude-haiku-5.5]
  c.dsl_can_reprioritize        = true # default: a step's own order wins
  c.dsl_can_use_unlisted_models = true # default: a step may name models not listed above
end.ensure_provider_models!
```

`ensure_provider_models!` runs once per process (it also runs lazily on the first routed call):

1. Drops every vendor whose API key is not set, warning in yellow on stderr.
1. Downloads each remaining vendor's model catalog, all at once. A vendor whose catalog fails is dropped for the life of the process.
1. If anything was dropped, prints the surviving vendors in green. If none survive, raises `Errors::MissingProviderAPIKeysError`.
1. Drops every model in `llm_models_priority` that no surviving vendor serves. If none is left, raises `Errors::NoAvailableModelsError`.

Who serves a model: OpenRouter serves anything its catalog lists; OpenAI and Anthropic serve their own models natively (`anthropic/claude-haiku-5.5` is sent to Anthropic as `claude-haiku-5-5`); TypeSafe serves `typesafe/jev-*` for `extract` steps whose every field Jev can answer. When several vendors could serve a model, `llm_vendors_priority` decides.

A step names its own models with `use_first_available_model`:

```ruby
extract :facts do
  from :situation
  prompt "Extract the filing details."
  schema filing_status: :string, dependents: :integer
  use_first_available_model "deepseek/deepseek-v4.1-flash", "anthropic/claude-haiku-5.5"
end
```

At call time the first model a usable vendor serves is used; if none is, the step falls back to `llm_models_priority` with one warning. A step with no list uses `llm_models_priority`; an old `model :claude_sonnet` hint counts as a one-entry list. The list never appears in the JSON wire format: the server reads it from the definition it loaded.

Call the step through the routing facade:

```ruby
Inquirex::LLM.route(node)                         # => Routing::Route(model:, provider:, native_id:, adapter:)
Inquirex::LLM.extract(node, engine.answers)       # => Extraction
Inquirex::LLM.summarize(node, transcript, answers) # => markdown String
```

Without `llm_vendors_priority`, routing is off and these three use `Inquirex::LLM.adapter`, exactly as before.

## Configuration

Model ids, the provider and its credentials are set in one place, `Inquirex::LLM.configuration`. Each setting is read from its environment variable when that variable is set and not blank, and otherwise takes the default below. The adapters fall back on it whenever no `api_key:` or `model:` is passed and a node sets no `max_tokens` or `temperature` of its own.

| Variable                           | Setting               | Default                                                                |
| ---------------------------------- | --------------------- | ---------------------------------------------------------------------- |
| `INQUIREX_LLM_ADAPTER`             | `provider`            | auto-detect; else `anthropic`, `openai`, `openrouter`, `jev` or `null` |
| `ANTHROPIC_API_KEY`                | `anthropic_api_key`   | none                                                                   |
| `OPENAI_API_KEY`                   | `openai_api_key`      | none                                                                   |
| `OPENROUTER_API_KEY`               | `openrouter_api_key`  | none                                                                   |
| `TYPESAFE_API_KEY`                 | `typesafe_api_key`    | none                                                                   |
| `INQUIREX_LLM_ANTHROPIC_MODEL`     | `anthropic_model`     | `Models::ANTHROPIC_DEFAULT` (`claude-sonnet-5-5`)                      |
| `INQUIREX_LLM_OPENAI_MODEL`        | `openai_model`        | `Models::OPENAI_DEFAULT` (`gpt-4o-mini`)                               |
| `INQUIREX_LLM_OPENROUTER_MODEL`    | `openrouter_model`    | `Models::OPENROUTER_DEFAULT` (`anthropic/claude-sonnet-5.5`)           |
| `INQUIREX_LLM_JEV_MODEL`           | `jev_model`           | `Models::JEV_DEFAULT` (`jev-latest`)                                   |
| `INQUIREX_LLM_MAX_TOKENS`          | `max_tokens`          | `2048`                                                                 |
| `INQUIREX_LLM_TEMPERATURE`         | `temperature`         | `0.2`                                                                  |
| `INQUIREX_LLM_SUMMARY_MAX_TOKENS`  | `summary_max_tokens`  | `4096`                                                                 |
| `INQUIREX_LLM_SUMMARY_TEMPERATURE` | `summary_temperature` | `0.4`                                                                  |
| `INQUIREX_DEBUG`                   | `debug`               | off; any non-blank value turns it on                                   |

An invalid value (an unknown provider, a token count that is not a positive integer, a temperature outside 0 to 2) raises `Inquirex::LLM::Errors::ConfigurationError` naming the variable. `to_h` and `inspect` print every `*_api_key` as `[REDACTED]`.

The single-provider settings (`provider`, the `*_model` settings and `Inquirex::LLM.adapter`) are **deprecated** since 0.13.0 in favour of [Model routing](#model-routing-0130); they keep working unchanged.

ENV is read once, on first use. Code can override any setting afterwards; `nil` restores the default:

```ruby
Inquirex::LLM.configure do |c|
  c.provider        = :anthropic
  c.anthropic_model = "claude-opus-5-5"
  c.max_tokens      = 4096
end

adapter = Inquirex::LLM.adapter            # built from the configuration
Inquirex::LLM.reset_configuration!         # discard overrides and read ENV again
```

`Inquirex::LLM.adapter` picks the adapter, first match wins:

| Condition                   | Adapter                                  |
| --------------------------- | ---------------------------------------- |
| `provider` is `:null`       | `NullAdapter`                            |
| `provider` is `:anthropic`  | `AnthropicAdapter` (needs key)           |
| `provider` is `:openai`     | `OpenAIAdapter` (needs key)              |
| `provider` is `:openrouter` | `OpenRouterAdapter` (needs key)          |
| `provider` is `:jev`        | `JevAdapter` (needs key; `extract` only) |
| `anthropic_api_key` is set  | `AnthropicAdapter`                       |
| `openai_api_key` is set     | `OpenAIAdapter`                          |
| otherwise                   | `NullAdapter`                            |

`OPENROUTER_API_KEY` and `TYPESAFE_API_KEY` never select an adapter on their own: a host that has one of those keys for something else keeps the adapter it had, and Jev cannot summarize, so both must be asked for by name.

## Built-in Adapters

| Class                              | Provider   | API                                    | Auth                      | Key env var          |
| ---------------------------------- | ---------- | -------------------------------------- | ------------------------- | -------------------- |
| `Inquirex::LLM::NullAdapter`       | —          | none (placeholders)                    | none                      | —                    |
| `Inquirex::LLM::AnthropicAdapter`  | Anthropic  | `/v1/messages`                         | `x-api-key` header        | `ANTHROPIC_API_KEY`  |
| `Inquirex::LLM::OpenAIAdapter`     | OpenAI     | `/v1/chat/completions` (JSON mode)     | `Authorization: Bearer …` | `OPENAI_API_KEY`     |
| `Inquirex::LLM::OpenRouterAdapter` | OpenRouter | `/api/v1/chat/completions` (JSON mode) | `Authorization: Bearer …` | `OPENROUTER_API_KEY` |
| `Inquirex::LLM::JevAdapter`        | TypeSafe   | `/v1/systemone` (typed questions)      | `Authorization: Bearer …` | `TYPESAFE_API_KEY`   |

OpenRouter and Jev are never auto-detected; select them with `INQUIREX_LLM_ADAPTER` or build them directly.

All adapters use `net/http` (stdlib, no extra dependency), inject the declared `schema` into the system prompt as a strict JSON contract, and raise `Inquirex::LLM::Errors::AdapterError` on HTTP / parse failures and `SchemaViolationError` when the model's output is missing declared fields.

### AnthropicAdapter

```ruby
adapter = Inquirex::LLM::AnthropicAdapter.new   # key and model from the configuration
adapter = Inquirex::LLM::AnthropicAdapter.new(  # or name them; arguments win
  api_key: "sk-ant-...",
  model:   "claude-opus-5-5"                    # or pass the short symbol in the DSL
)
```

The current model ids live in one constant, `Inquirex::LLM::Models::ANTHROPIC` (also reachable as `AnthropicAdapter::MODELS`): `claude-fable-5-1`, `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5`. The default is `Models::ANTHROPIC_DEFAULT`, `claude-sonnet-5-5`, unless `INQUIREX_LLM_ANTHROPIC_MODEL` names another. Recognized `model :symbol` values in the DSL: `:claude_sonnet`, `:claude_haiku`, `:claude_opus` and `:claude_fable`, each mapped to its family's id in `MODELS`. `:claude_fable` is Anthropic-only; the OpenAI adapter does not map it.

These models reject sampling parameters, so the adapter does not send `temperature` to them. A `temperature` in the DSL still reaches a model you name by an older id, such as `model: "claude-sonnet-4-6"`.

### OpenAIAdapter

```ruby
adapter = Inquirex::LLM::OpenAIAdapter.new     # key and model from the configuration
adapter = Inquirex::LLM::OpenAIAdapter.new(api_key: "sk-...", model: "gpt-4.1")
```

Uses Chat Completions with `response_format: { type: "json_object" }` so the model is constrained to return valid JSON. Recognized DSL symbols: `:gpt_4o`, `:gpt_4o_mini`, `:gpt_4_1`, `:gpt_4_1_mini`. For cross-provider portability, the adapter also accepts the Claude symbols (`:claude_sonnet` → `gpt-4o` etc.) so a flow file that says `model :claude_sonnet` runs unchanged against either provider.

### OpenRouterAdapter

```ruby
adapter = Inquirex::LLM::OpenRouterAdapter.new   # key and model from the configuration
adapter = Inquirex::LLM::OpenRouterAdapter.new(model: "google/gemini-2.5-flash", effort: "low")
```

Any model OpenRouter hosts, with the OpenAI adapter's prompts and parsing. The Claude and GPT symbols map to OpenRouter ids (`:claude_haiku` → `anthropic/claude-haiku-5.5`); any other model is sent as written. `effort:` (`none` … `max`) becomes OpenRouter's `reasoning.effort`; without it the model decides.

### JevAdapter

```ruby
adapter = Inquirex::LLM::JevAdapter.new                       # key and model from the configuration
adapter = Inquirex::LLM::JevAdapter.new(min_confidence: 0.6)  # less sure than 0.6 → nil
extraction = adapter.call(node, answers)                      # the values, as every adapter returns them
extraction.raw.dig("filing_status", "confidence")             # how sure Jev was, from TypeSafe's answer
```

Jev, TypeSafe's System One model, answers typed questions with calibrated probabilities instead of writing JSON. The adapter turns each schema field into questions and sends them all in one request: a Choice per `enum` (plus "not stated"), a yes / no / not-stated Choice per `boolean`, a presence Choice plus a Noul per value for `multi_enum`, and for `integer` a Choice among the numbers the text states (digits or words, `Inquirex::LLM::Numbers`) and the counts 0 to 12. It retries 429 and 529 twice with backoff.

Jev chooses; it cannot write. A schema with a `string`, `text`, `date`, `email`, `phone` or other free-form field raises `AdapterError` before anything is sent (`JevAdapter.unsupported_fields(schema)` checks a flow up front), and `summarize` always raises. Route those to a text model.

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

## Evals

Which model extracts best, measured with this gem's own prompts: ten flows, a complete and a vague text each, run on [llm-evals](https://github.com/kigster/llm-evals). The lineup and the data live in [`evals/`](evals/README.md); the adapter and the scorer are `Inquirex::LLM::Evals`, loaded only by `require "inquirex/llm/evals"`.

How a run works:

1. **Verify** (offline): each dataset's `schema.rb` must match the `extract` step in its `dsl.rb`, and every `expected.json` must fit that schema.
1. **Expand the lineup**: every model under `vendors:` in `evals/.llm-evals.config.yml`, times each `effort`/`temperature` it lists, becomes one contender. Each contender runs every case.
1. **Call the model**: one OpenRouter chat completion per case, built from this gem's production prompt and the step's schema.
1. **Score the raw reply** field by field: `correct` 1.0, `missed` 0.2, `hallucinated` 0.15, `incorrect` 0.1, `invalid` 0. A case's score is the mean over its fields. The rules are in [`evals/README.md`](evals/README.md#scoring).
1. **Report**: a leaderboard on screen and a JSON log under `log/llm-evals/`. If `BRAINTRUST_API_KEY` or `LOGFIRE_TOKEN` is set, each case is also sent to that one tracker; `--local` turns that off.

```bash
just evals -n                       # the whole matrix, calling nothing
just evals                          # every configured model on every dataset
just evals --local -d 05-managed-it-services   # one dataset, no remote tracker
just evals-verify                   # step 1 only

bundle exec evals cases       # the 20 cases
bundle exec evals run -m openai/gpt-4o-mini   # one model, per-case breakdown
```

`just evals` needs `OPENROUTER_API_KEY` and the `:evals` bundle group. It is a paid run: 14 contenders × 20 cases = 280 calls.

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
