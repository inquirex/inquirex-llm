# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/10_wedding-photography.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  event_type: { type: :enum,
    values: %w[wedding elopement engagement_session celebration corporate] },
  season: { type: :enum, values: %w[spring summer autumn winter still_deciding] },
  guest_count: :integer,
  coverage_hours: :integer,
  formats: { type: :enum, values: %w[photo video both] },
  locations: :integer,
  full_day_arc: :boolean,
  travel_required: :boolean,
  add_ons: { type: :multi_enum,
    values: %w[drone album engagement_session second_shooter same_day_edit] }
}
