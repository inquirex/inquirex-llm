# Changelog

## 0.12.0 (unreleased)

Hand-written until `github_changelog_generator` regenerates this file at release. The family-wide notes are in inquirex's `INQUIREX_VERSION_LOG.md`.

- **Current Claude model ids.** `AnthropicAdapter::MODELS` lists `claude-fable-5-1`, `claude-opus-5-5`, `claude-sonnet-5-5` and `claude-haiku-5-5`; the default (`claude-sonnet-5-5`) and the `:claude_sonnet`, `:claude_haiku`, `:claude_opus` and new `:claude_fable` aliases are looked up in it. 0.10.0 defaulted to `claude-sonnet-4-20250514`.
- **`Inquirex::LLM.configuration`.** Provider, API keys, default models, token limits, temperatures and debug are set in one place, from ENV first (`INQUIREX_LLM_ADAPTER`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, new `INQUIREX_LLM_ANTHROPIC_MODEL`, `INQUIREX_LLM_OPENAI_MODEL`, `INQUIREX_LLM_MAX_TOKENS`, `INQUIREX_LLM_TEMPERATURE`, `INQUIREX_LLM_SUMMARY_MAX_TOKENS`, `INQUIREX_LLM_SUMMARY_TEMPERATURE`, `INQUIREX_DEBUG`), then today's defaults; `Inquirex::LLM.configure` overrides them and `reset_configuration!` re-reads ENV. Invalid values raise `Errors::ConfigurationError` naming the variable. Model ids moved to `Inquirex::LLM::Models`; the adapter constants still answer. `Inquirex::LLM.adapter` builds the adapter with the selection rules inquirex-tty used to carry.
- **`OpenRouterAdapter`.** Any OpenRouter model through the OpenAI adapter's prompts and parsing, with an optional reasoning `effort:`. New `OPENROUTER_API_KEY` and `INQUIREX_LLM_OPENROUTER_MODEL` (default `anthropic/claude-sonnet-5.5`).
- **Extraction result object.** An `extract` call returns an `Inquirex::LLM::Extraction`: the schema-shaped Hash it always returned (it is a `Hash`, so `prefill!`, `==` and JSON are unchanged) with `raw`, the JSON exactly as the model sent it before enum values were canonicalized, and `usage`, the tokens and cost the provider reported. One LLM call per extraction, as before.
- **`JevAdapter`.** TypeSafe's Jev through its native typed-question API: `enum`, `boolean`, `multi_enum` and `integer` fields only, one request per step, `min_confidence:` to leave unsure fields unset, and per-field confidence in the `Extraction#raw`. Reads `TYPESAFE_API_KEY` and `INQUIREX_LLM_JEV_MODEL`, whose default is now `jev-latest` (was the unverified `jev-1.13.0`). Neither new adapter is auto-detected; `INQUIREX_LLM_ADAPTER` accepts `openrouter` and `jev`.
- **The extraction eval suite now runs on agent-evals.** `evals/` holds `.agent-eval.config.yml` and `datasets/<NN-slug>/` (dsl.rb, schema.rb, `cases/{complete,vague}/`); the adapter and the five-outcome scorer are `Inquirex::LLM::Evals`, in the gem but loaded only by `require "inquirex/llm/evals"`. The standalone `extract-eval` runner is gone; its results are in `docs/evals-history.md`.
- **Fix:** an `OpenAIAdapter` subclass's `MODEL_MAP` was ignored; model symbols always resolved through OpenAI's map.
- **No `temperature` for current models.** They answer any sampling parameter with HTTP 400, so the adapter omits it for ids in `MODELS` and still sends it to a model named by an older id.
- **Requires `inquirex ~> 0.12`**, which declares `prism` as a runtime dependency and so loads on Ruby 4.1.
- `spec/inquirex/llm/gemspec_spec.rb` fails when `lib/` requires a library that neither ships with the running Ruby nor is a declared runtime dependency.
- CircleCI config copied from inquirex core; `.ruby-version` pins 4.1.0-preview1.

## [v0.10.0](https://github.com/inquirex/inquirex-llm/tree/v0.10.0) (2026-08-17)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/v0.8.0...v0.10.0)

**Merged pull requests:**

- Set the lockstep version to 0.10.0 [#7](https://github.com/inquirex/inquirex-llm/pull/7) ([kigster](https://github.com/kigster))
- Bump to 0.9.6 [#6](https://github.com/inquirex/inquirex-llm/pull/6) ([kigster](https://github.com/kigster))
- Add the summarize verb [#5](https://github.com/inquirex/inquirex-llm/pull/5) ([kigster](https://github.com/kigster))
- Canonicalize LLM output against schema values [#3](https://github.com/inquirex/inquirex-llm/pull/3) ([kigster](https://github.com/kigster))

## [v0.8.0](https://github.com/inquirex/inquirex-llm/tree/v0.8.0) (2026-08-01)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/v0.6.0...v0.8.0)

## [v0.6.0](https://github.com/inquirex/inquirex-llm/tree/v0.6.0) (2026-07-20)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/v0.5.0...v0.6.0)

**Merged pull requests:**

- Resolve extract schemas from question references [#2](https://github.com/inquirex/inquirex-llm/pull/2) ([kigster](https://github.com/kigster))

## [v0.5.0](https://github.com/inquirex/inquirex-llm/tree/v0.5.0) (2026-07-16)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/v0.4.1...v0.5.0)

**Merged pull requests:**

- Reduce LLM verbs to `extract` and release v0.5.0 [#1](https://github.com/inquirex/inquirex-llm/pull/1) ([kigster](https://github.com/kigster))

## [v0.4.1](https://github.com/inquirex/inquirex-llm/tree/v0.4.1) (2026-07-13)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/v0.3.0...v0.4.1)

## [v0.3.0](https://github.com/inquirex/inquirex-llm/tree/v0.3.0) (2026-04-15)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/v0.1.0...v0.3.0)

## [v0.1.0](https://github.com/inquirex/inquirex-llm/tree/v0.1.0) (2026-04-14)

[Full Changelog](https://github.com/inquirex/inquirex-llm/compare/809890f89aa8230b34674820debf7a68ced283e5...v0.1.0)

\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
