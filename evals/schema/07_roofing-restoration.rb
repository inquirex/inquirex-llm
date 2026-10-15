# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/07_roofing-restoration.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  project_scope: { type: :enum,
    values: %w[repair full_replacement full_exterior] },
  stories: { type: :enum, values: %w[one two three_plus] },
  roof_pitch: { type: :enum, values: %w[flat walkable steep] },
  material: { type: :enum,
    values: %w[asphalt_3tab architectural wood_shake metal tile_slate not_sure] },
  roof_age: { type: :enum, values: %w[under_10 ten_to_twenty over_20 not_sure] },
  leaking_now: :boolean,
  storm_damage: :boolean,
  filing_insurance: :boolean,
  timeline: { type: :enum,
    values: %w[emergency weeks planning researching] }
}
