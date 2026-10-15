# Decisions on the extract evals

Settled with the maintainer on 2026-10-14 while building `evals/`.

| #   | Question                      | Decision                                                                                                                                                                                                                                   |
| --- | ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | What does the model see?      | The gem's real prompt. Each DSL is loaded with `load_dsl(unsafe: true)` and the `extract` node's system and user prompts are built by `Inquirex::LLM::OpenAIAdapter`. Scores reflect production.                                           |
| 2   | How does JSON come back?      | As production does it: JSON in the reply text (`response_format: json_object`), parsed and canonicalized by the gem. A reply that is not a JSON object scores 0 rather than erroring.                                                      |
| 3   | Can ground truth hold `null`? | No. Every paragraph answers every field, including 08's three feature lists that its prompt says to leave unset. A model that obeys that prompt line loses those points on 08.                                                             |
| 4   | Scoring                       | Objective, per field: enum, boolean and integer exact; multi_enum by Jaccard overlap. Scorers `field_accuracy` (mean), `exact_match` (all fields right) and `valid_json` (parsed, every key present). No LLM judge.                        |
| 5   | File formats                  | `schema/*.rb` (Ruby hash, copied verbatim from the DSL), `extracted-answers/*.txt`, `ground-truth/*.json`, one basename across all four folders.                                                                                           |
| 6   | CLI                           | dry-cli: `run`, `compare`, `cases`, `verify`, `version`, `completion`.                                                                                                                                                                     |
| 7   | Models                        | `config.yml` lists vendors and models; `effort` and `temperature` accept lists and expand. Default lineup is a cross-vendor mix plus TypeSafe's Jev (`typesafe/jev-router`).                                                               |
| 8   | Transport                     | `ExtractEval::OpenRouterAdapter` subclasses `OpenAIAdapter` and replaces only the HTTP call (RubyLLM to OpenRouter). It lives in `evals/`; moving it into the gem would add `ruby_llm` as a runtime dependency and is a separate decision. |
| 9   | Dependencies and secrets      | `evals/Gemfile` is self-contained. Keys come from the repo's `.env` only. Experiments go to `BRAINTRUST_PROJECT_ID`; `--project NAME` overrides.                                                                                           |

## Second dataset: vague

| #   | Question                                                           | Decision                                                                                                                                                           |
| --- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 10  | What does "vague" mean?                                            | A mix: about half the fields are never answered (truth `null`, so a guess scores 0), the rest are hedged but decidable. Vagueness grows toward `10`.               |
| 11  | What counts as "unset"?                                            | `null`, `""` or `[]`. `0` and `false` are answers and score 0.                                                                                                     |
| 12  | The gem's prompt told models to use `0` or `""` for missing values | Fixed in the gem: both adapters now share `Adapter#missing_values_instruction`, which asks for `null` and forbids `0`, `""`, `false` and `[]` for a missing value. |
| 13  | Layout                                                             | `datasets/<name>/{extracted-answers,ground-truth}`; `dsls/` and `schema/` stay shared. `--dataset` selects; experiment names and tags carry it.                    |
| 14  | Measuring restraint                                                | A `restraint` scorer: the share of `null`-truth fields left unset. It records nothing on cases without a `null`, so `clear` gets no free points.                   |

## Open

- **Jev native.** Jev is built for typed judgments (Choice, Noul, Score) with calibrated probabilities. Through OpenRouter it is measured as a chat model producing one JSON object. A second task calling TypeSafe's API per field would measure it on its own terms.
- **LLM as judge.** Not needed while every expected value is a typed, closed answer.
