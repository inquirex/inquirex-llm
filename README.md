# inquirex-llm

LLM integration verbs for the [Inquirex](https://github.com/inquirex/inquirex) questionnaire engine.

Extends the core DSL with four server-side verbs -- `clarify`, `describe`, `summarize`, and `detour` -- that bridge free-text answers and structured data via LLM processing. Ships with a pluggable adapter interface and a `NullAdapter` for testing.

## Status

- Version: `0.1.0`
- Ruby: `>= 4.0.0`
- Test suite: `111 examples, 0 failures`
- Depends on: `inquirex` (core gem)

## Installation

```ruby
gem "inquirex-llm"
```

## Usage

`require "inquirex-llm"` injects the LLM verbs into the core `Inquirex.define` DSL. No separate entry point needed.

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

  clarify :extracted do
    from :description
    prompt "Extract structured business information from the description."
    schema industry:          :string,
           entity_type:       :string,
           employee_count:    :integer,
           estimated_revenue: :currency
    model :claude_sonnet
    temperature 0.2
    transition to: :summary
  end

  summarize :summary do
    from_all
    prompt "Summarize this client's tax situation and flag complexity concerns."
    transition to: :done
  end

  say :done do
    text "Thank you! We'll be in touch."
  end
end
```

All core verbs (`ask`, `say`, `header`, `btw`, `warning`, `confirm`) and widget hints work alongside LLM verbs in the same `Inquirex.define` block.

## LLM Verbs

### `clarify`

Extract structured data from a free-text answer. Requires `from`, `prompt`, and `schema`.

```ruby
clarify :business_extracted do
  from :business_description
  prompt "Extract structured business information."
  schema industry: :string, employee_count: :integer, revenue: :currency
  model :claude_sonnet
  temperature 0.2
  max_tokens 1024
  transition to: :next_step
end
```

### `describe`

Generate natural-language text from structured data. Requires `from` and `prompt`. No schema needed.

```ruby
describe :business_narrative do
  from :business_extracted
  prompt "Write a brief narrative of this business for the intake report."
  transition to: :next_step
end
```

### `summarize`

Produce a summary of all or selected answers. Use `from_all` to pass everything, or `from` to select specific steps.

```ruby
summarize :intake_summary do
  from_all
  prompt "Summarize this client's tax situation."
  transition to: :review
end
```

### `detour`

Dynamically generate follow-up questions based on an answer. The server adapter handles presenting the generated questions and collecting responses. Requires `from`, `prompt`, and `schema`.

```ruby
detour :followup do
  from :description
  prompt "Generate 2-3 follow-up questions to clarify the tax situation."
  schema questions: :array, answers: :hash
  transition to: :next_step
end
```

## DSL Methods (inside LLM verb blocks)

| Method | Purpose | Required |
|--------|---------|----------|
| `prompt "..."` | LLM prompt template | Always |
| `schema key: :type, ...` | Expected output structure | `clarify`, `detour` |
| `from :step_id` | Source step(s) whose answers feed the LLM | `clarify`, `describe`, `detour` |
| `from_all` | Pass all collected answers to the LLM | Alternative to `from` |
| `model :claude_sonnet` | Optional model hint for the adapter | No |
| `temperature 0.3` | Optional sampling temperature | No |
| `max_tokens 1024` | Optional max output tokens | No |
| `fallback { \|answers\| ... }` | Server-side fallback (stripped from JSON) | No |
| `transition to: :step` | Conditional transition (same as core) | No |
| `skip_if rule` | Skip step when condition is true | No |

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

## JSON Serialization

LLM steps serialize with `"requires_server": true` so the JS widget knows to round-trip to the server. LLM metadata lives under an `"llm"` key:

```json
{
  "verb": "clarify",
  "requires_server": true,
  "transitions": [{ "to": "summary", "requires_server": true }],
  "llm": {
    "prompt": "Extract structured business information.",
    "schema": {
      "industry": "string",
      "employee_count": "integer",
      "revenue": "currency"
    },
    "from_steps": ["business_description"],
    "model": "claude_sonnet",
    "temperature": 0.2,
    "max_tokens": 1024
  }
}
```

Fallback procs are stripped from JSON (server-side only).

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

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
