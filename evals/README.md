# Extract evals

Which model best turns what a visitor writes into the structured answers an Inquirex `extract` step declares? This folder answers that with ten real flows, ten paragraphs, and Braintrust experiments.

Each case is one basename. The flow and its schema are shared; each dataset brings its own texts and truth:

| Path                                 | Holds                                                                                 |
| ------------------------------------ | ------------------------------------------------------------------------------------- |
| `dsls/`                              | the flow; its single `extract` step supplies prompt and schema                        |
| `schema/`                            | that step's `schema`, copied verbatim (`verify` fails on drift)                       |
| `datasets/<name>/extracted-answers/` | what a visitor wrote                                                                  |
| `datasets/<name>/ground-truth/`      | the answers a perfect extraction returns; `null` where the text never answers a field |

| Dataset | Texts                                                                                          |
| ------- | ---------------------------------------------------------------------------------------------- |
| `clear` | answer every field; `01` answers directly, `10` is an essay                                    |
| `vague` | hedged and incomplete; about half the fields go unanswered (truth `null`), more so toward `10` |

Every model gets the gem's production prompt (`Inquirex::LLM::OpenAIAdapter`), sent through RubyLLM to OpenRouter, and its reply is parsed and canonicalized exactly as in production.

## Setup

Keys live in the repo's `.env`: `OPENROUTER_API_KEY`, `BRAINTRUST_API_KEY`, and `BRAINTRUST_PROJECT_ID`.

```bash
just install
just ci          # lint, specs, fixture verification; no network
```

## Commands

```bash
exe/extract-eval cases                                   # list the cases
exe/extract-eval verify                                  # check fixtures, offline
exe/extract-eval run -m openai/gpt-4o-mini               # one model, per-case breakdown
exe/extract-eval run -m anthropic/claude-haiku-5.5 -e low -c 08,09,10
exe/extract-eval compare                                 # everything in config.yml
exe/extract-eval compare -n                              # show that matrix, call nothing
exe/extract-eval compare -m a/x,b/y -t 0 --local         # ad hoc, without Braintrust
exe/extract-eval compare -d clear,vague                  # every contender on both datasets
```

`-e/--effort`, `-t/--temperature` and `--max-tokens` override `config.yml`. `-d/--dataset` picks the texts (default `clear`). `--local` scores without logging to Braintrust; otherwise the best experiment opens in the browser (`--no-open` to skip).

## Scores

| Scorer           | Meaning                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------ |
| `field_accuracy` | mean per-field score; multi_enum earns Jaccard overlap                                     |
| `exact_match`    | 1 when every field is right                                                                |
| `valid_json`     | 1 when the reply parsed and carried every schema key                                       |
| `restraint`      | share of unanswered fields the model left unset; recorded only when the truth has a `null` |

Where the truth is `null`, a reply of `null`, `""` or `[]` is correct. `0` and `false` are answers (no dependents, not self-employed) that the engine would prefill, so they score 0.

Each case's wrong fields are attached as scorer metadata in Braintrust.

## Results

Run 2026-10-14 into the `BRAINTRUST_PROJECT_ID` project: `exe/extract-eval compare -d clear,vague` over the `config.yml` lineup, temperature 0.2, all ten cases per dataset, after the gem's prompt began asking for `null` on missing values.

### clear

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

`typesafe-api/<model>` contenders use the gem's `Inquirex::LLM::JevAdapter`: one typed question per field, all in one request. Same day, same fixtures:

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
