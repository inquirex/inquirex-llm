# frozen_string_literal: true

# The `schema` of the `extract :understanding` step in dsls/08_software-development.rb.
# Copied verbatim; `extract-eval verify` fails when the two drift apart.
{
  project_type: { type: :enum,
    values: %w[brochure_site web_app mobile_app api_integration] },
  brochure_features: { type: :multi_enum,
    values: %w[cms blog multilingual lead_forms booking catalog analytics] },
  app_features: { type: :multi_enum,
    values: %w[dashboards search notifications file_uploads realtime roles import_export audit_log] },
  mobile_features: { type: :multi_enum,
    values: %w[offline push camera_media location in_app_purchase biometrics wearables] },
  integration_features: { type: :multi_enum,
    values: %w[crm_sync accounting sso data_migration webhooks public_api scheduler] },
  user_accounts: :boolean,
  payments: :boolean,
  compliance: :boolean,
  integrations: :integer,
  platforms: { type: :multi_enum, values: %w[web ios android] },
  design_state: { type: :enum, values: %w[ready rough none] },
  timeline: { type: :enum, values: %w[flexible normal rush] },
  engagement: { type: :enum, values: %w[one_time ongoing] }
}
