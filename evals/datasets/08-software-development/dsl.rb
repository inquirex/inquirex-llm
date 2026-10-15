# Demo flow — Custom Software / Web & App Development (spec 012, segment 7).
#
# The wink-at-your-own-stack demo. Its headline superpower is **feature-adder
# scoping**: the four `multi_enum` checklists price with `per_selection:`, so
# every box the visitor ticks moves the number in front of them. That is the
# whole argument an agency has with a prospect, rendered as a form.
#
#   Extract  — the opener is the brief the prospect would have emailed anyway.
#              Single-value fields the LLM fills are skipped outright by
#              `skip_if not_empty(...)`; multi_enum fields come back as
#              *suggestions* rather than answers (Engine#prefill! routes them
#              through `prefill_suggestion`), so the checklists still render —
#              pre-ticked. Which is what you want: the ticking is the demo.
#   Estimate — `accumulator :price` sums a base platform, per-feature adders,
#              per-integration units, a design tier and a rush surcharge.
#   Tier     — G1/G2/G3 falls out of ordinary rules. No lambdas: `compute` is
#              not allowlisted, and correctly so.
#
# Two constraints worth knowing before you edit the numbers:
#
#   1. Accumulators only ever *add*. There is no shape that multiplies the
#      running total, so the spec's "rush multiplier" is expressed here as a
#      flat rush surcharge on :timeline. Honest, and it survives serialization.
#   2. `flat:` contributes when the answer is truthy, so a yes/no question can
#      only ever price the *yes*. Where the money is in the "no" — not having
#      designs costs more, not less — the question becomes an `:enum` whose
#      good branch prices at zero. See :design_state.
#
# PII-free by construction: project shapes, counts and bands only. Where a real
# agency form would collect a name and email, a `say` step says so instead.

Inquirex.define do
  meta title: "Software Project Scoping",
    subtitle: "Describe the build — we'll price the shape of it"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "Describe what you want to build and the problem it solves. What " \
             "kind of product is it — a site, a web app, mobile? Mention the " \
             "features that matter (accounts, payments, integrations), which " \
             "platforms you need, whether designs exist yet, and your timeline. " \
             "Write it the way you'd write it to a colleague — we'll pull the " \
             "scope out of it."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the software project's scope from the writer's description. " \
           "Only fill a field when the text genuinely supports it — leave " \
           "anything the writer did not mention unset rather than guessing. " \
           "`integrations` is a count of distinct third-party systems the " \
           "project must talk to; use 0 when the writer says there are none, " \
           "and leave it unset when they simply did not say. Do not infer " \
           "`compliance` from the industry alone — the writer has to actually " \
           "raise SOC 2, HIPAA, PCI or similar. Fill only the feature list that " \
           "matches `project_type`; leave the other three unset."
    schema project_type: { type: :enum,
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
    text "Reading the brief…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Here's what we picked up from your brief:\n\n" \
         "{% if answers.project_type %}• Building: **{{ answers.project_type | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.user_accounts %}• User accounts and login\n{% endif %}" \
         "{% if answers.payments %}• Taking payments\n{% endif %}" \
         "{% if answers.compliance %}• A compliance regime to satisfy\n{% endif %}" \
         "{% if answers.integrations %}• Third-party systems to talk to: **{{ answers.integrations }}**\n{% endif %}" \
         "{% if answers.design_state %}• Design: **{{ answers.design_state | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.timeline %}• Timeline: **{{ answers.timeline }}**\n{% endif %}" \
         "{% if answers.engagement %}• Engagement: **{{ answers.engagement | replace: '_', ' ' }}**\n{% endif %}" \
         "\nWe'll only ask about what's still missing — and where we spotted " \
         "features or platforms, we've pre-ticked them so you can correct us."
    transition to: :project_type
  end

  # The fork. Each project type carries its own base platform cost and opens its
  # own feature checklist; everything after the checklists is shared.
  ask :project_type do
    type :enum
    question "What are you building?"
    options brochure_site: "A marketing or brochure site",
      web_app: "A web application",
      mobile_app: "A mobile app",
      api_integration: "An integration between systems we already run"
    skip_if not_empty(:project_type)
    price brochure_site: 3500, api_integration: 9000, web_app: 18_000, mobile_app: 24_000
    transition to: :brochure_features, if_rule: equals(:project_type, "brochure_site")
    transition to: :app_features, if_rule: equals(:project_type, "web_app")
    transition to: :mobile_features, if_rule: equals(:project_type, "mobile_app")
    transition to: :integration_features
  end

  # The four checklists deliberately carry no `skip_if`: a multi_enum prefill
  # lands as a suggestion, so `not_empty` is never true here and the rule would
  # be decoration. The visitor always sees the boxes — that is the point.
  ask :brochure_features do
    type :multi_enum
    question "Which of these does the site need?"
    options cms: "Edit your own content (CMS)",
      blog: "Blog or news section",
      multilingual: "More than one language",
      lead_forms: "Contact and lead-capture forms",
      booking: "Online booking or scheduling",
      catalog: "A product or service catalogue",
      analytics: "Analytics and conversion tracking"
    price per_selection: { cms: 2500, blog: 1500, multilingual: 3500, lead_forms: 1200,
                          booking: 3000, catalog: 4500, analytics: 900 }
    transition to: :user_accounts
  end

  ask :app_features do
    type :multi_enum
    question "Which of these does the application need?"
    options dashboards: "Dashboards and reporting",
      search: "Search across your data",
      notifications: "Email or in-app notifications",
      file_uploads: "File uploads and document storage",
      realtime: "Real-time updates (live collaboration, presence)",
      roles: "Roles and permissions",
      import_export: "Bulk import and export",
      audit_log: "An audit trail of who changed what"
    price per_selection: { dashboards: 8000, search: 5000, notifications: 3500, file_uploads: 3000,
                          realtime: 9000, roles: 5500, import_export: 2500, audit_log: 4000 }
    transition to: :user_accounts
  end

  ask :mobile_features do
    type :multi_enum
    question "Which of these does the app need?"
    options offline: "Works offline and syncs later",
      push: "Push notifications",
      camera_media: "Camera, photo or video capture",
      location: "Maps and location",
      in_app_purchase: "In-app purchases or subscriptions",
      biometrics: "Face or fingerprint unlock",
      wearables: "A watch or wearable companion"
    price per_selection: { offline: 12_000, push: 3500, camera_media: 5000, location: 4500,
                          in_app_purchase: 6500, biometrics: 4000, wearables: 7000 }
    transition to: :user_accounts
  end

  ask :integration_features do
    type :multi_enum
    question "What does the integration have to do?"
    options crm_sync: "Two-way CRM sync",
      accounting: "Talk to accounting or ERP",
      sso: "Single sign-on (SAML or OIDC)",
      data_migration: "A one-time migration of existing data",
      webhooks: "Webhooks and event delivery",
      public_api: "Expose a public API to your own customers",
      scheduler: "Scheduled jobs with retries and alerting"
    price per_selection: { crm_sync: 6000, accounting: 5000, sso: 5500, data_migration: 7000,
                          webhooks: 3500, public_api: 9000, scheduler: 3000 }
    transition to: :user_accounts
  end

  confirm :user_accounts do
    question "Do people need to log in?"
    skip_if not_empty(:user_accounts)
    price flat: 4500
    transition to: :payments
  end

  confirm :payments do
    question "Does it take payments?"
    skip_if not_empty(:payments)
    price flat: 7500
    transition to: :compliance
  end

  # Skipped wholesale for brochure sites: a static marketing site has no data to
  # be compliant about, and asking anyway is how a form loses a lead.
  confirm :compliance do
    question "Is there a compliance regime it has to satisfy — SOC 2, HIPAA, PCI, GDPR?"
    skip_if any(not_empty(:compliance), equals(:project_type, "brochure_site"))
    price flat: 15_000
    transition to: :integrations
  end

  ask :integrations do
    type :integer
    question "How many other systems does it have to talk to?"
    default 0
    min 0
    max 15
    skip_if not_empty(:integrations)
    price per_unit: 2500
    transition to: :platforms
  end

  # Web is free because it is already in every base platform above; the money is
  # in the second and third surface, which is exactly the multi-platform tier.
  ask :platforms do
    type :multi_enum
    question "Where does it have to run?"
    options web: "The web",
      ios: "iOS",
      android: "Android"
    skip_if equals(:project_type, "brochure_site")
    price per_selection: { web: 0, ios: 11_000, android: 11_000 }
    transition to: :design_state
  end

  ask :design_state do
    type :enum
    question "How far along is the design?"
    options ready: "Finished designs, ready to build against",
      rough: "Wireframes, a sketch, or a site we want to look like",
      none: "Nothing yet — you'd be designing it too"
    skip_if not_empty(:design_state)
    price ready: 0, rough: 6000, none: 14_000
    transition to: :timeline
  end

  ask :timeline do
    type :enum
    question "When does it need to be live?"
    options flexible: "No fixed date",
      normal: "Two to three months",
      rush: "Under six weeks"
    skip_if not_empty(:timeline)
    price flexible: 0, normal: 0, rush: 12_000
    transition to: :engagement
  end

  ask :engagement do
    type :enum
    question "Is this a one-time build, or ongoing?"
    options one_time: "Build it, hand it over, we take it from there",
      ongoing: "Ongoing — roadmap, support, someone on call"
    skip_if not_empty(:engagement)
    price one_time: 0, ongoing: 18_000
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real agency form would ask for your name and " \
         "email so somebody could follow up.\n\n" \
         "This is a demo, so we're collecting neither — and notice that nothing " \
         "we asked identifies you. The number below came entirely from the shape " \
         "of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:project_type, "mobile_app"),
      equals(:engagement, "ongoing"),
      equals(:compliance, true),
      equals(:payments, true),
      contains(:platforms, "ios"),
      contains(:platforms, "android"),
      greater_than(:integrations, 3)
    )
    transition to: :tier_standard, if_rule: any(
      equals(:project_type, "web_app"),
      equals(:project_type, "api_integration"),
      equals(:user_accounts, true),
      equals(:timeline, "rush"),
      greater_than(:integrations, 0)
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "Planning range: **{{ price | money_range }}**\n\n" \
         "This is a content project, not a software project — pages, a CMS, and " \
         "nothing behind them that has to be kept running. Scope like this " \
         "usually lands in weeks rather than quarters, and the cost moves almost " \
         "entirely with how much design has to be invented from scratch.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "self-serve queue. You'd never see that; the agency would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "Planning range: **{{ price | money_range }}**\n\n" \
         "There's a real application here — accounts, data that has to stay " \
         "consistent, and systems that have to keep agreeing with each other. " \
         "Every box you ticked above is a week or three of somebody's time, " \
         "which is why the number moved as you ticked them.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to a " \
         "delivery lead. You'd never see that; the agency would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "Planning range: **{{ price | money_range }}**\n\n" \
         "This one needs an architect before it needs a developer. Native " \
         "platforms, money moving through the system, a compliance regime or an " \
         "ongoing retainer each change who has to be in the room — and each " \
         "widens the range, because the expensive part of work like this is the " \
         "part nobody can see from the brief.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight " \
         "to a principal. You'd never see that; the agency would._"
  end
end
