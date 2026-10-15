# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/05_managed-it-services.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  seat_count: :integer,
  work_model: { type: :enum,
    values: %w[mostly_office mostly_remote hybrid] },
  infrastructure: { type: :enum,
    values: %w[cloud_only on_prem hybrid] },
  server_count: :integer,
  current_support: { type: :enum,
    values: %w[none internal_person another_provider] },
  compliance: { type: :multi_enum,
    values: %w[hipaa soc2 pci other none] },
  security_incident: :boolean,
  growth_planned: :boolean,
  response_time: { type: :enum,
    values: %w[next_business_day four_hours one_hour] },
  biggest_pain: { type: :enum,
    values: %w[downtime slow_support security_worries cost scaling] }
}
