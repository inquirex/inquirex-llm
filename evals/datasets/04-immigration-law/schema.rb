# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsl.rb beside this file.
# Copied verbatim; `agent-evals verify` fails when the two drift apart.
{
  current_status: { type: :enum,
    values: %w[visitor student work_visa green_card pending_case no_status unsure] },
  primary_goal: { type: :enum,
    values: %w[employment family humanitarian citizenship] },
  in_us: :boolean,
  employer_sponsor: :boolean,
  prior_denial: :boolean,
  deadline_soon: :boolean,
  family_members: :integer
}
