# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/03_home-remodeling.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  rooms: { type: :multi_enum, values: %w[kitchen bath addition whole_home] },
  scope: { type: :enum, values: %w[refresh mid_range gut] },
  finish_level: { type: :enum, values: %w[builder mid luxury] },
  square_feet: :integer,
  moving_walls: :boolean,
  design_plans: { type: :enum, values: %w[full_plans working_with_designer none] },
  timeline: { type: :enum, values: %w[asap next_3_months next_6_months just_exploring] }
}
