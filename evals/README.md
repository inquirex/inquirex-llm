# Extraction evals

Which model best turns what a visitor writes into the structured answers an Inquirex `extract` step declares? Ten real flows, each with a complete paragraph and a vague one, run on [agent-evals](https://github.com/kigster/agent-evals) with this gem's production prompts.

This folder holds only the lineup file and the data. The Ruby is the gem's, under `lib/inquirex/llm/evals/`, named by three keys in `.agent-eval.config.yml`: `Inquirex::LLM::Evals::Adapter` runs one case through `Inquirex::LLM::OpenAIAdapter`'s prompts and parsing, and `Inquirex::LLM::Evals::Scorer` grades the reply field by field. Neither is loaded by `require "inquirex-llm"`.

## Layout

```text
evals/
  .agent-eval.config.yml          the models to compare, and the three keys that name the Ruby
  datasets/<NN-slug>/
    dsl.rb                        the flow; its single extract step supplies prompt and schema
    schema.rb                     that step's schema, copied verbatim (verify fails on drift)
    cases/complete/input.txt      a paragraph that answers every field
    cases/complete/expected.json  the answers a perfect extraction returns
    cases/vague/input.txt         hedged and incomplete; about half the fields go unanswered
    cases/vague/expected.json     null where the text never answers a field
```

Each dataset is one case per variant, so the suite is 10 datasets and 20 cases. A `concise` variant (short texts that still answer every field) is planned; the folder that used to carry that name held a copy of `vague` and was dropped.

## Running

From the repository root, with the `:evals` group bundled:

```bash
bundle exec agent-evals cases                              # the 20 cases, no calls
bundle exec agent-evals verify                             # schemas, inputs and expected answers, offline
bundle exec agent-evals run -m openai/gpt-4o-mini          # one model, every dataset, per-case breakdown
bundle exec agent-evals run -m anthropic/claude-haiku-5.5 -e low -d 05-managed-it-services
bundle exec agent-evals compare                            # everything the lineup lists, leaderboard only
bundle exec agent-evals compare -n                         # show that matrix, call nothing
bundle exec agent-evals run --local -m google/gemini-2.5-flash   # score without Braintrust
```

Keys: `OPENROUTER_API_KEY` for every contender, `BRAINTRUST_API_KEY` and `BRAINTRUST_PROJECT_ID` unless `--local`. The repository's `.envrc` exports them from `.env.encrypted`.

## Scoring

Every schema field ends in one of five outcomes, each worth a fixed share of the point, and a case's `score` is the mean over its fields:

| Outcome        | Worth | When                                                                       |
| -------------- | ----- | -------------------------------------------------------------------------- |
| `correct`      | 1.0   | what the text says, as the schema spells it (a case variant counts, noted) |
| `missed`       | 0.2   | the text answers it and the reply left it null, empty, or the key out      |
| `hallucinated` | 0.15  | the text never answers it (truth `null`) and the reply answered anyway     |
| `incorrect`    | 0.1   | an allowed value, the wrong one                                            |
| `invalid`      | 0     | a value the schema does not allow: off the list, wrong type, or not JSON   |

A `multi_enum` is graded per element (in both lists correct, truth-only missed, reply-only hallucinated, off-list invalid) and the field is the mean of its elements. Where the truth is `null`, `""` and `[]` are correct with a form-drift note; `0` and `false` are answers the engine would prefill, so they are hallucinated. The reply is read as the model sent it, before the gem canonicalized it.

The other metrics: `exact` (every field correct), `hallucinated_rate` (over the `null`-truth fields, the share answered anyway; nothing recorded when a text answers everything) and `invalid_rate`.

Results from the previous runner, and the decisions it was built on, are in [docs/evals-history.md](../docs/evals-history.md).
