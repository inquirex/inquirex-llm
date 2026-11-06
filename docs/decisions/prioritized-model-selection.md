# Prioritized model selection

Status: accepted, 2026-11-03. Ships in inquirex-llm 0.13.0.

## Why

With [llm-evals](https://rubygems.org/gems/llm-evals) we can measure how well each model turns what a user said into the schema of a specific `extract` step, per dataset (DSL) and per case. The best model differs from step to step and from vendor to vendor. A single global `provider` and `*_model` cannot express "use the model that won the evals for *this* step", and one Ruby process often serves many flows.

The first user is qualified-at. Its evals found a DeepSeek model the most accurate, fastest and cheapest on some datasets but not all, so a tax-agency intake should run the tax-agency winner while other flows keep theirs. DeepSeek is reachable only through OpenRouter, which is why routing covers OpenRouter as well as native vendors.

So the host configures, once per process, which vendors it may use and which models it prefers, and each LLM step may name its own ordered list of models. The gem picks the first one this process can actually reach.

## Configuration

```ruby
Inquirex::LLM.configure do |config|
  config.llm_vendors_priority        = %i[openrouter openai anthropic typesafe]
  config.llm_models_priority         = %w[anthropic/claude-haiku-5.5 openai/gpt-4.1-mini]
  config.dsl_can_reprioritize        = true # default
  config.dsl_can_use_unlisted_models = true # default
end.ensure_provider_models!
```

- `configure` returns the configuration, so `ensure_provider_models!` chains. `Inquirex::LLM.ensure_provider_models!` does the same.
- Model names are always OpenRouter-style `vendor/model`, e.g. `openai/gpt-4.1-mini`, `anthropic/claude-haiku-5.5`, `deepseek/deepseek-v4.1-flash-1017`.

### `ensure_provider_models!`

1. **Vendors.** Each listed vendor whose API key is not set is removed, with a yellow warning on stderr. Each remaining vendor's model catalog is downloaded (`GET /models`, 5 s timeout, all vendors in parallel). A vendor whose catalog cannot be downloaded is removed **for the life of this Ruby process**, with a yellow warning: a vendor that is down at boot would otherwise add its timeout to every call. If anything was removed, the surviving vendors are printed in green, in priority order. No vendor left: `Errors::MissingProviderAPIKeysError`.
1. **Models.** A model stays when at least one remaining vendor serves it (below). Others are removed with a yellow warning. No model left: `Errors::NoAvailableModelsError`.

Both errors subclass `Errors::ConfigurationError`. The family names errors `…Error`, so the requested `MissingProviderAPIKeysException` is spelled `MissingProviderAPIKeysError`.

### Which vendor serves a model

Validation is online, against the downloaded catalogs. An offline check could only verify the vendor prefix, and a catalog bundled with the gem is always out of date.

| Model prefix  | Served natively when                                                                     | Served through OpenRouter when     |
| ------------- | ---------------------------------------------------------------------------------------- | ---------------------------------- |
| `anthropic/`  | `anthropic` is enabled and lists the native id (`claude-haiku-5.5` → `claude-haiku-5-5`) | OpenRouter lists the id as written |
| `openai/`     | `openai` is enabled and lists the id without its prefix                                  | same                               |
| `typesafe/`   | `typesafe` is enabled and lists it; `extract` only, and only for schemas Jev can answer  | same                               |
| anything else | never                                                                                    | same                               |

When a model can be served both ways, the vendor priority decides.

## The DSL

```ruby
extract :business_extracted do
  from :business_description
  prompt "Extract structured business information."
  schema industry: :string, employee_count: :integer
  use_first_available_model "openai/gpt-4.1-mini",
                            "anthropic/claude-haiku-5.5",
                            "deepseek/deepseek-v4.1-flash-1017"
  temperature 0.2
  transition to: :next_step
end
```

- Arguments or one array, strings or symbols. Each entry must be `vendor/model`, or the flow fails to define.
- Allowed in `extract` and `summarize`. Builder methods only: no option hash, per the family grammar.
- When both `model` and `use_first_available_model` are declared, the list wins and the definition warns that `model` is ignored.
- The old `model :claude_sonnet` keeps working. Under routing it becomes a one-entry list through `Models::OPENROUTER_ALIASES` (`anthropic/claude-sonnet-5.5`). A step with neither uses `llm_models_priority`.
- `dsl_can_use_unlisted_models = false`: a step naming a model absent from `llm_models_priority` is a `DefinitionError`.
- `dsl_can_reprioritize = false`: the step's list only filters; the global order applies.

## When the model is chosen

At call time, not at load time. The full list stays on the node, so a definition loaded in another process (with other keys) still has its fallbacks. The choice is cached per node for the life of the process.

If no model in the step's list can be served, the step falls back to `llm_models_priority`, with one yellow warning per step per process. An LLM failure degrades, never blocks.

## Not on the wire

The list is never serialized. The server rebuilds a flow from its DSL source and finds the step by id, so it already holds the list. The widget never makes the LLM call, and per the family invariant it never sees a model name; hosts send it the flow without the `llm` block. The existing `llm.model` serialization is unchanged.

Consequence: anything that rebuilds a flow from JSON rather than DSL loses the list. Today that is `inquirex-webui`'s print-and-reload round trip.

## Calling it

```ruby
Inquirex::LLM.extract(node, answers)
Inquirex::LLM.summarize(node, transcript)
route = Inquirex::LLM.route(node, verb: :extract)
route.model      # => "anthropic/claude-haiku-5.5"
route.provider   # => :anthropic
route.native_id  # => "claude-haiku-5-5"
route.adapter    # => #<Inquirex::LLM::AnthropicAdapter>
```

- Every built-in adapter's `call` and `summarize` take an optional `model:` keyword that overrides the node's. Existing callers are unaffected.
- Adapters are built once per vendor, after `ensure_provider_models!`.
- When `llm_vendors_priority` is set and nothing has called `ensure_provider_models!`, the first `route` runs it, once.
- When `llm_vendors_priority` is not set, `extract` and `summarize` use `Inquirex::LLM.adapter`, as before.

## Backwards compatibility

- `provider`, `anthropic_model`, `openai_model`, `openrouter_model`, `jev_model`, `INQUIREX_LLM_ADAPTER` and `Inquirex::LLM.adapter` are deprecated and keep working. They are removed in a later minor release.
- `JevAdapter` changes are additive. A host calling adapters directly (qualified-at on 0.12.x) works on 0.13.0 unchanged.
- Lockstep versioning is a nice-to-have, not a requirement. inquirex-llm goes to 0.13.0 on its own.

## Out of scope

- Failing over to the next model after a call fails (5xx, timeout). Only key availability and catalog membership decide.
- Caching catalogs on disk between processes.
- Bringing a vendor back after it was removed at boot. Restart the process.
