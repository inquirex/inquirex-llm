# Demo flow — Tax Preparation (spec 012, segment 1: the flagship).
#
# Shows off all three superpowers in one pass:
#   Extract  — the opener is a free-text ramble; the LLM fills in as many of the
#              structured answers as it can, and every question it answered is
#              skipped by `skip_if not_empty(...)`.
#   Estimate — `accumulator :price` sums a base return plus per-schedule
#              surcharges. Prefilled answers accumulate exactly like typed ones,
#              so a skipped question still contributes its money.
#   Tier     — G1/G2/G3 is derived from the answers with ordinary rules (no
#              lambdas — `compute` is not allowlisted, and correctly so).
#
# PII-free by construction: counts, bands and yes/no only. Where a real intake
# form would collect a name and email, a `say` step says so instead.

Inquirex.define do
  meta title: "Tax Preparation Intake",
    subtitle: "Tell us about your year — we'll work out the rest"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "In a few sentences, tell us about your tax situation this year — " \
             "what's changed, and what you're worried about. It helps to mention " \
             "your filing status and dependents, whether you're self-employed or " \
             "own a business, any rental properties or investments you sold, " \
             "whether you file in more than one state, and any letters the IRS " \
             "has sent you."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the taxpayer's situation from their description. Only fill a " \
           "field when the text genuinely supports it — leave anything the writer " \
           "did not mention unset rather than guessing. `dependents` and " \
           "`rental_properties` are counts; use 0 when the writer says they have " \
           "none, and leave unset when they simply did not say."
    schema filing_status: { type: :enum,
                           values: %w[single married_jointly married_separately head_of_household] },
      dependents: :integer,
      self_employed: :boolean,
      rental_properties: :integer,
      sold_investments: :boolean,
      owns_business_entity: :boolean,
      multi_state: :boolean,
      irs_letter: :boolean
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Here's what we picked up from what you wrote:\n\n" \
         "{% if answers.filing_status %}• Filing status: **{{ answers.filing_status | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.dependents %}• Dependents: **{{ answers.dependents }}**\n{% endif %}" \
         "{% if answers.self_employed %}• Self-employment income\n{% endif %}" \
         "{% if answers.rental_properties %}• Rental properties: **{{ answers.rental_properties }}**\n{% endif %}" \
         "{% if answers.sold_investments %}• Sold stock or crypto\n{% endif %}" \
         "{% if answers.owns_business_entity %}• Owns a business entity\n{% endif %}" \
         "{% if answers.multi_state %}• Worked in more than one state\n{% endif %}" \
         "\nWe'll only ask about what's still missing."
    transition to: :filing_status
  end

  ask :filing_status do
    type :enum
    question "What's your filing status?"
    options single: "Single",
      married_jointly: "Married, filing jointly",
      married_separately: "Married, filing separately",
      head_of_household: "Head of household"
    skip_if not_empty(:filing_status)
    price single: 275, married_jointly: 350, married_separately: 400, head_of_household: 325
    transition to: :dependents
  end

  ask :dependents do
    type :integer
    question "How many dependents will you claim?"
    default 0
    min 0
    max 12
    skip_if not_empty(:dependents)
    price per_unit: 35
    transition to: :self_employed
  end

  confirm :self_employed do
    question "Did you have any self-employment or 1099 income?"
    skip_if not_empty(:self_employed)
    price flat: 250
    transition to: :owns_business_entity
  end

  confirm :owns_business_entity do
    question "Do you own a business entity (LLC, S-corp, or partnership)?"
    skip_if not_empty(:owns_business_entity)
    price flat: 450
    transition to: :entity_type, if_rule: equals(:owns_business_entity, true)
    transition to: :rental_properties
  end

  ask :entity_type do
    type :enum
    question "What kind of entity is it?"
    options sole_prop: "Sole proprietorship",
      llc: "LLC",
      s_corp: "S-corporation",
      partnership: "Partnership"
    price sole_prop: 0, llc: 150, s_corp: 400, partnership: 400
    transition to: :payroll
  end

  confirm :payroll do
    question "Do you run payroll for employees?"
    price flat: 300
    transition to: :contractors
  end

  confirm :contractors do
    question "Did you pay any 1099 contractors?"
    price flat: 150
    transition to: :rental_properties
  end

  ask :rental_properties do
    type :integer
    question "How many rental properties do you own?"
    default 0
    min 0
    max 20
    skip_if not_empty(:rental_properties)
    price per_unit: 225
    transition to: :sold_investments
  end

  confirm :sold_investments do
    question "Did you sell any stock, crypto, or other investments?"
    skip_if not_empty(:sold_investments)
    price flat: 200
    transition to: :multi_state
  end

  confirm :multi_state do
    question "Did you live or work in more than one state?"
    skip_if not_empty(:multi_state)
    price flat: 175
    transition to: :irs_letter
  end

  confirm :irs_letter do
    question "Have you received any letters from the IRS this year?"
    skip_if not_empty(:irs_letter)
    price flat: 250
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real intake form would ask for your name and " \
         "email so the firm could follow up.\n\n" \
         "This is a demo, so we're not collecting either — and notice that nothing " \
         "we asked identifies you. The estimate below came entirely from the shape " \
         "of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:owns_business_entity, true),
      equals(:multi_state, true),
      equals(:sold_investments, true),
      equals(:irs_letter, true)
    )
    transition to: :tier_standard, if_rule: any(
      equals(:self_employed, true),
      greater_than(:rental_properties, 0),
      greater_than(:dependents, 2)
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "Yours is a straightforward return — a single filing status, no business " \
         "income, no investment sales. We'd have this back to you inside a week.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "self-serve queue. You'd never see that; the firm would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "There's real substance here — self-employment, rental income, or a larger " \
         "household. Expect a preparer to walk your documents with you before filing.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to a " \
         "staff preparer. You'd never see that; the firm would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This one needs a senior preparer. Business entities, multi-state filing, " \
         "investment sales and IRS correspondence all carry real risk, and the " \
         "range reflects the review time that goes with them.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight to " \
         "a partner. You'd never see that; the firm would._"
  end
end
