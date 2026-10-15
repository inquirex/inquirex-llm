# Extraction evals: history

The suite in [`evals/`](../evals/README.md) ran first as a standalone `extract-eval` executable of its own (2026-10-14), with its own scorer. It now runs on agent-evals, whose decisions are recorded in that gem's `docs/decisions.md`. What follows is what the first runner measured and decided, kept so the numbers below can be read against the scorer that produced them.

## Results of 2026-10-14 (old scorer)

The old scorer graded a field 1 or 0 (`multi_enum` by Jaccard overlap), with `field_accuracy` the mean per field, `exact_match` all fields right, `valid_json` parsed with every key present, and `restraint` the share of `null`-truth fields left unset. These columns are **not** today's `score`, which weights missed, hallucinated, incorrect and invalid answers differently; compare them with each other, not with a current run.

Run into the `BRAINTRUST_PROJECT_ID` project: `extract-eval compare -d clear,vague` over the lineup, temperature 0.2, all ten cases per dataset, after the gem's prompt began asking for `null` on missing values. `clear` is today's `complete` variant.

### clear (today: complete)

| Model                             | Effort  | Field accuracy | Exact match | Valid JSON |
| --------------------------------- | ------- | -------------- | ----------- | ---------- |
| google/gemini-2.5-flash           | default | 98.9%          | 80.0%       | 100.0%     |
| anthropic/claude-haiku-5.5        | low     | 96.6%          | 80.0%       | 100.0%     |
| anthropic/claude-haiku-5.5        | default | 96.6%          | 80.0%       | 100.0%     |
| typesafe/jev-router               | default | 96.6%          | 80.0%       | 100.0%     |
| openai/gpt-4.1-mini               | default | 96.2%          | 70.0%       | 100.0%     |
| anthropic/claude-sonnet-5.5       | default | 95.1%          | 70.0%       | 100.0%     |
| openai/gpt-4o-mini                | default | 88.4%          | 50.0%       | 100.0%     |
| meta-llama/llama-3.3-70b-instruct | default | 87.6%          | 60.0%       | 100.0%     |

### vague

| Model                             | Effort  | Field accuracy | Exact match | Restraint | Valid JSON |
| --------------------------------- | ------- | -------------- | ----------- | --------- | ---------- |
| anthropic/claude-sonnet-5.5       | default | 97.1%          | 70.0%       | 96.3%     | 100.0%     |
| anthropic/claude-haiku-5.5        | default | 96.1%          | 60.0%       | 95.2%     | 100.0%     |
| typesafe/jev-router               | default | 96.1%          | 60.0%       | 93.8%     | 100.0%     |
| anthropic/claude-haiku-5.5        | low     | 95.0%          | 60.0%       | 94.3%     | 100.0%     |
| google/gemini-2.5-flash           | default | 87.1%          | 20.0%       | 81.1%     | 100.0%     |
| openai/gpt-4.1-mini               | default | 83.6%          | 10.0%       | 78.6%     | 100.0%     |
| meta-llama/llama-3.3-70b-instruct | default | 81.6%          | 20.0%       | 80.8%     | 100.0%     |
| openai/gpt-4o-mini                | default | 79.1%          | 10.0%       | 85.9%     | 100.0%     |

The clear texts barely separate the models: with ten cases, one field is about one point, and repeated runs move the leaders by a point or two. The vague texts do separate them. Gemini, which leads on clear texts, drops to fifth because it fills in fields the writer never answered: about one guess in five where the truth is `null`. Claude and Jev mostly leave those fields unset.

The `typesafe/jev-router` rows reach Jev through OpenRouter's chat completions, like every other model.

### Jev through TypeSafe's own API

`typesafe-api/<model>` contenders used the gem's `Inquirex::LLM::JevAdapter`: one typed question per field, all in one request. Same day, same fixtures. (The agent-evals suite is prompt-only and does not list TypeSafe's API; measuring `JevAdapter` on its own terms is a separate suite.)

| Dataset | Model                    | Field accuracy | Exact match | Restraint | Time for 10 cases |
| ------- | ------------------------ | -------------- | ----------- | --------- | ----------------- |
| clear   | typesafe-api/jev-latest  | 99.0%          | 90.0%       | -         | 2.0s              |
| clear   | typesafe-api/jev-preview | 99.0%          | 90.0%       | -         | 4.0s              |
| clear   | typesafe/jev-router      | 96.6%          | 80.0%       | -         | 31.2s             |
| vague   | typesafe/jev-router      | 94.3%          | 60.0%       | 90.9%     | 48.6s             |
| vague   | typesafe-api/jev-preview | 91.3%          | 40.0%       | 87.5%     | 4.6s              |
| vague   | typesafe-api/jev-latest  | 89.5%          | 30.0%       | 82.8%     | 3.7s              |

Native Jev ties for the best clear-text score of any model at a tenth of the time, but guesses more often when the text is silent. The adapter's `min_confidence:` trades the one for the other; a local sweep with `jev-latest`:

| min_confidence | clear accuracy | vague accuracy | vague restraint |
| -------------- | -------------- | -------------- | --------------- |
| none           | 99.0%          | 88.5%          | 82.0%           |
| 0.5            | 97.9%          | 89.3%          | 87.5%           |
| 0.6            | 97.9%          | 90.4%          | 92.0%           |
| 0.7            | 96.8%          | 88.7%          | 94.0%           |
| 0.8            | 94.5%          | 86.9%          | 95.5%           |

## History

Decisions settled with the maintainer on 2026-10-14 while building the first runner. Its rows on the runner itself (the dry-cli commands, `config.yml`, the RubyLLM transport, the self-contained `evals/Gemfile`, Braintrust wiring) are superseded by agent-evals' `docs/decisions.md`, rows 1 to 14. What still holds:

- **What the model sees.** The gem's real prompt. Each `dsl.rb` is loaded with `load_dsl(unsafe: true)` and the `extract` step's system and user prompts are built by `Inquirex::LLM::OpenAIAdapter`, so scores reflect production.
- **How JSON comes back.** As production does it: JSON in the reply text (`response_format: json_object`), parsed and canonicalized by the gem. A reply that is not a JSON object scores 0 rather than erroring; a transport failure is the run's error, not the model's.
- **Ground truth and `null`.** The complete texts answer every field, including `08`'s three feature lists that its prompt says to leave unset; a model that obeys that prompt line loses those points on `08`. The vague texts leave about half the fields unanswered, truth `null`, vagueness growing toward `10`.
- **What counts as unset.** `null`, `""` or `[]`. `0` and `false` are answers the engine would prefill, so they are never "left unset".
- **The gem's prompt once told models to use `0` or `""` for missing values.** Fixed in the gem: both adapters share `Adapter#missing_values_instruction`, which asks for `null` and forbids `0`, `""`, `false` and `[]` for a missing value.
- **Objective scoring, no LLM judge.** Every expected value is a typed, closed answer. The first scorer's 1-or-0 fields, Jaccard for `multi_enum` and the `restraint` column gave way to the five outcomes and `hallucinated_rate` described in `evals/README.md`.
- **File formats.** `schema.rb` is a Ruby Hash copied verbatim from the DSL; `verify` fails when the two drift.
