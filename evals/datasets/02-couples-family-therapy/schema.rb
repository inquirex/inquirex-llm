# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsl.rb beside this file.
# Copied verbatim; `agent-evals verify` fails when the two drift apart.
{
  seeking_for: { type: :enum, values: %w[individual couple family] },
  participation: { type: :enum, values: %w[solo together] },
  primary_concern: { type: :enum,
    values: %w[communication trust parenting intimacy separation] },
  how_long: { type: :enum,
    values: %w[under_three_months three_to_twelve_months
    one_to_three_years longer_than_that] },
  both_attending: :boolean,
  session_format: { type: :enum, values: %w[virtual in_person either] },
  start_timing: { type: :enum,
    values: %w[as_soon_as_possible next_few_weeks just_exploring] },
  prior_therapy: :boolean
}
