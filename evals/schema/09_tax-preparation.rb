# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/09_tax-preparation.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  filing_status: { type: :enum,
    values: %w[single married_jointly married_separately head_of_household] },
  dependents: :integer,
  self_employed: :boolean,
  rental_properties: :integer,
  sold_investments: :boolean,
  owns_business_entity: :boolean,
  multi_state: :boolean,
  irs_letter: :boolean
}
