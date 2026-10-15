# Demo flow — Managed IT Services / MSP (spec 012, segment 8).
#
# Headline superpower: **per-seat recurring pricing**. Every number in here is
# monthly, and the dominant term is a single `price per_unit:` on the seat
# count, so the arithmetic stays visible — 40 seats at $95 is $3,800 before a
# single adder is applied. Everything else is a comparatively small correction
# on top of that line.
#
#   Extract  — the opener is a free-text gripe about their IT; the LLM fills in
#              whatever it can, and every question it answered is skipped by
#              `skip_if not_empty(...)`.
#   Estimate — `accumulator :price` sums seats × per-seat rate, infrastructure
#              and server adders, and a compliance premium. Prefilled answers
#              accumulate exactly like typed ones, so a skipped question still
#              contributes its money.
#   Tier     — G1/G2/G3 falls out of ordinary rules (no lambdas — `compute` is
#              not allowlisted, and correctly so).
#
# Deliberately NOT asked: vendor names, product versions, firewall or VPN
# details, IP ranges, mail domains, "who do you use for backups". A visitor
# typing that into a public form is assembling an attack profile for whoever
# reads it next, and none of it is needed to quote a price — categories and
# counts scope the work just as well. `btw :nothing_fingerprintable` says so out
# loud, because a prospect noticing that restraint is itself the argument for
# hiring the firm. `security_incident` is a bare yes/no for the same reason: the
# fact changes the scope, the details belong on a call under NDA.
#
# PII-free by construction: counts, categories and yes/no only. Where a real
# intake form would collect a name and email, a `say` step says so instead.
#
# One nuance behind the `skip_if` lines: an extracted multi_enum (`compliance`)
# is recorded as a *suggestion* rather than an answer, so that question is still
# asked — with the boxes pre-ticked. Only single-value fields skip outright.

Inquirex.define do
  meta title: "Managed IT Services — Scoping",
    subtitle: "Tell us how you work; we'll price the support around it"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "In a few sentences, tell us about your company's IT setup and " \
             "what's frustrating you about it right now. How many seats do you " \
             "have, do people mostly work at the office or remote, and what's your " \
             "infrastructure model — on-prem, cloud, or a mix? How many servers do " \
             "you manage, and what are your compliance requirements, if any? Have " \
             "you already had a security incident, or are you working to mitigate " \
             "the threat of one? And perhaps share your biggest pain at the moment."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the company's IT profile from their description. Only fill a " \
           "field when the text genuinely supports it — leave anything the writer " \
           "did not mention unset rather than guessing. `seat_count` and " \
           "`server_count` are counts of people and of physical or virtual " \
           "servers; use 0 for servers when the writer says they have none, and " \
           "leave both unset when they simply did not say. Do not infer " \
           "compliance from the industry alone; only record a framework the " \
           "writer actually named or clearly described."
    schema seat_count: :integer,
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
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Here's what we picked up from what you wrote:\n\n" \
         "{% if answers.seat_count %}• People to support: **{{ answers.seat_count }}**\n{% endif %}" \
         "{% if answers.work_model %}• Where they work: **{{ answers.work_model | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.infrastructure %}• Infrastructure: **{{ answers.infrastructure | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.server_count %}• Servers: **{{ answers.server_count }}**\n{% endif %}" \
         "{% if answers.current_support %}• IT support today: **{{ answers.current_support | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.security_incident %}• A recent security incident\n{% endif %}" \
         "{% if answers.growth_planned %}• Headcount growth coming\n{% endif %}" \
         "{% if answers.response_time %}• Response expectation: **{{ answers.response_time | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.biggest_pain %}• Biggest pain: **{{ answers.biggest_pain | replace: '_', ' ' }}**\n{% endif %}" \
         "\nWe'll only ask about what's still missing."
    transition to: :seat_count
  end

  ask :seat_count do
    type :integer
    question "How many people need support? Count everyone with a company " \
             "login, including part-timers. This is billed monthly per seat, so " \
             "it's the single biggest driver of the number at the end."
    min 1
    max 2000
    skip_if not_empty(:seat_count)
    price per_unit: 95
    transition to: :work_model
  end

  ask :work_model do
    type :enum
    question "Where does the team actually work?"
    options mostly_office: "Mostly in one office",
      mostly_remote: "Mostly remote",
      hybrid: "Hybrid — a bit of both"
    skip_if not_empty(:work_model)
    price mostly_office: 150, mostly_remote: 350, hybrid: 500
    transition to: :nothing_fingerprintable
  end

  btw :nothing_fingerprintable do
    text "Quick note before the infrastructure questions.\n\n" \
         "We ask for **categories and counts** — never vendor names, product " \
         "versions, firewall or VPN details, or anything else that would let a " \
         "stranger map your network. A public form on the open internet is the " \
         "wrong place to write those down, and we don't need them to quote you.\n\n" \
         "If a provider's intake form asks an unauthenticated visitor which " \
         "security products they run, that tells you something about the " \
         "provider."
    transition to: :infrastructure
  end

  ask :infrastructure do
    type :enum
    question "Broadly, where do your systems live?"
    options cloud_only: "Cloud only — nothing in a server room",
      on_prem: "On-premises servers",
      hybrid: "Some of each"
    skip_if not_empty(:infrastructure)
    price cloud_only: 0, on_prem: 750, hybrid: 950
    transition to: :server_count, if_rule: any(
      equals(:infrastructure, "on_prem"),
      equals(:infrastructure, "hybrid")
    )
    transition to: :cloud_footprint
  end

  # ── On-prem / hybrid branch ────────────────────────────────────────────────

  ask :server_count do
    type :integer
    question "Roughly how many servers do you run — physical or virtual, all " \
             "sites combined?"
    default 1
    min 0
    max 100
    skip_if not_empty(:server_count)
    price per_unit: 185
    transition to: :onsite_visits
  end

  confirm :onsite_visits do
    question "Do you want scheduled on-site visits, rather than remote support " \
             "plus call-outs when something breaks?"
    price flat: 550
    transition to: :current_support
  end

  # ── Cloud-only branch ──────────────────────────────────────────────────────

  ask :cloud_footprint do
    type :multi_enum
    question "Which of these do you run in the cloud? Categories only — please " \
             "don't name the products."
    options email_and_docs: "Email and documents",
      file_storage: "Shared file storage",
      line_of_business: "A line-of-business application",
      finance_and_hr: "Finance, payroll or HR",
      dev_infrastructure: "Developer or hosting infrastructure"
    price per_selection: { email_and_docs: 60,
                          file_storage: 60,
                          line_of_business: 180,
                          finance_and_hr: 120,
                          dev_infrastructure: 240 }
    transition to: :current_support
  end

  # ── Back on the main line ──────────────────────────────────────────────────

  ask :current_support do
    type :enum
    question "Who handles IT today?"
    options none: "Nobody, really — whoever is free",
      internal_person: "Someone internal, alongside their real job",
      another_provider: "An outside provider we'd be replacing"
    skip_if not_empty(:current_support)
    price none: 450, internal_person: 250, another_provider: 150
    transition to: :compliance
  end

  ask :compliance do
    type :multi_enum
    question "Does anything you do carry a compliance obligation?"
    options hipaa: "HIPAA — we handle patient information",
      soc2: "SOC 2 — customers audit our security",
      pci: "PCI DSS — we take card payments",
      other: "Something else regulated",
      none: "Nothing we're aware of"
    skip_if not_empty(:compliance)
    price per_selection: { hipaa: 900, soc2: 1100, pci: 650, other: 500, none: 0 }
    transition to: :security_incident
  end

  confirm :security_incident do
    question "Have you had a security incident in the last twelve months? " \
             "Yes or no is all we want here — no details, please."
    skip_if not_empty(:security_incident)
    price flat: 400
    transition to: :growth_planned
  end

  confirm :growth_planned do
    question "Do you expect headcount to grow noticeably over the next year?"
    skip_if not_empty(:growth_planned)
    price flat: 300
    transition to: :response_time
  end

  ask :response_time do
    type :enum
    question "When something is broken, how fast do you need someone on it?"
    options next_business_day: "Next business day is fine",
      four_hours: "Within four hours",
      one_hour: "Within an hour, around the clock"
    skip_if not_empty(:response_time)
    price next_business_day: 0, four_hours: 400, one_hour: 1200
    transition to: :biggest_pain
  end

  ask :biggest_pain do
    type :enum
    question "Last one: what bothers you most about IT right now?"
    options downtime: "Things go down too often",
      slow_support: "Help takes too long to arrive",
      security_worries: "We're not confident we're secure",
      cost: "We're spending more than it seems worth",
      scaling: "We're outgrowing what we have"
    skip_if not_empty(:biggest_pain)
    price downtime: 200, slow_support: 100, security_worries: 350, cost: 0, scaling: 150
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real intake form would ask for your name and " \
         "email so the provider could follow up.\n\n" \
         "This is a demo, so we're not collecting either — and notice that " \
         "nothing we asked identifies you, your company, or a single system you " \
         "run. The estimate below came entirely from the shape of the work."
    transition to: :tier_complex, if_rule: any(
      greater_than(:seat_count, 74),
      greater_than(:server_count, 2),
      contains(:compliance, "hipaa"),
      contains(:compliance, "soc2"),
      contains(:compliance, "pci"),
      contains(:compliance, "other")
    )
    transition to: :tier_standard, if_rule: any(
      greater_than(:seat_count, 14),
      equals(:infrastructure, "on_prem"),
      equals(:infrastructure, "hybrid"),
      equals(:response_time, "one_hour"),
      equals(:response_time, "four_hours"),
      equals(:security_incident, true)
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }} per month\n\n" \
         "A small, cloud-only team with no compliance overhang is the cleanest " \
         "case there is — a standard per-seat plan covers it, and onboarding " \
         "takes about a week. The number moves with your headcount and nothing " \
         "else.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "standard-plan queue. You'd never see that; the provider would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }} per month\n\n" \
         "There's real ground to cover here — enough seats, infrastructure or " \
         "response-time pressure that someone will want to walk your environment " \
         "before quoting firmly. Expect a scoping call and a documented " \
         "onboarding plan.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to an " \
         "account engineer. You'd never see that; the provider would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }} per month\n\n" \
         "This one needs a named vCIO rather than a support queue. Scale, " \
         "on-premises infrastructure and regulated data each carry audit and " \
         "review time that a per-seat rate alone doesn't cover, and the range " \
         "reflects it.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight " \
         "to a principal. You'd never see that; the provider would._"
  end
end
