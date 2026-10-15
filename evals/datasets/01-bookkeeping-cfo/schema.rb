# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsl.rb beside this file.
# Copied verbatim; `agent-evals verify` fails when the two drift apart.
{
  entity_type: { type: :enum,
    values: %w[sole_prop single_member_llc multi_member_llc s_corp multi_entity] },
  industry: { type: :enum,
    values: %w[professional_services retail_or_ecommerce construction_or_trades
    restaurant_or_hospitality healthcare real_estate other_industry] },
  revenue_band: { type: :enum,
    values: %w[under_25k from_25k_to_100k from_100k_to_500k over_500k] },
  transaction_volume: :integer,
  account_count: :integer,
  books_state: { type: :enum, values: %w[up_to_date behind not_started] },
  months_behind: :integer,
  filing_blocked: :boolean,
  accounting_software: { type: :enum,
    values: %w[cloud_software desktop_software spreadsheets nothing_yet] },
  payroll: :boolean,
  service_needed: { type: :enum, values: %w[monthly_bookkeeping controller fractional_cfo] }
}
