# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/06_personal-injury-law.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  incident_type: { type: :enum,
    values: %w[auto_accident slip_and_fall medical product other] },
  how_long_ago: { type: :enum, values: %w[days weeks months over_a_year] },
  injury_type: { type: :enum, values: %w[soft_tissue broken_bones head_or_spine permanent] },
  treated_by_doctor: :boolean,
  still_treating: :boolean,
  surgery_or_hospitalization: :boolean,
  fault: { type: :enum, values: %w[other_party shared unsure] },
  police_report: :boolean,
  other_party_insured: { type: :enum, values: %w[yes no unsure] },
  missed_work: :boolean,
  already_represented: :boolean
}
