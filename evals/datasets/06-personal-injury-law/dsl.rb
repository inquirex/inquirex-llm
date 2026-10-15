# Demo flow — Personal Injury Law (spec 012, segment 2: value, not fee).
#
# Shows off all three superpowers in one pass:
#   Extract  — the opener is a free-text account of what happened; the LLM fills
#              in as many of the structured answers as it can, and every question
#              it answered is skipped by `skip_if not_empty(...)`.
#   Estimate — `accumulator :price` sums a **case-value** band, not a fee. A
#              contingency firm never quotes a price; it quotes what the case
#              might be worth. Same accumulator, opposite meaning — the wizard
#              calls it `:price` by convention and the copy calls it value.
#   Tier     — G1/G2/G3 is derived from injury severity and liability clarity
#              with ordinary rules (no lambdas — `compute` is not allowlisted,
#              and correctly so).
#
# The branching fork is the incident type: auto accident, slip and fall, medical
# and product each open one follow-up question the others never see.
#
# PII-free by construction: categories, counts, bands and yes/no only. Nothing
# here is a medical record — "did a doctor see you" is a fact about the case,
# not about the injury. Where a real intake form would collect a name and email,
# a `say` step says so instead.

Inquirex.define do
  meta title: "Personal Injury Case Review",
    subtitle: "Tell us what happened — we'll tell you what a case like yours can be worth"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "Tell us what happened, in your own words. What kind of incident was " \
             "it and how long ago, have you seen a doctor or had surgery, and are " \
             "you still treating? If you know, mention who was at fault, whether " \
             "there's a police report, and whether you've missed work. There's no " \
             "wrong way to say it — start wherever it makes sense to you."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the facts of an accident from the writer's account. Only fill " \
           "a field when the text genuinely supports it — leave anything the " \
           "writer did not mention unset rather than guessing. `fault` is who the " \
           "writer says caused it, not who you think did; use `unsure` only when " \
           "they say they don't know. Set `treated_by_doctor` false only when they " \
           "say they were not seen; leave it unset when they simply did not say."
    schema incident_type: { type: :enum,
                           values: %w[auto_accident slip_and_fall medical product other] },
      how_long_ago: { type: :enum, values: %w[days weeks months over_a_year] },
      injury_type: { type: :enum, values: %w[soft_tissue broken_bones head_or_spine permanent] },
      treated_by_doctor: :boolean,
      still_treating: :boolean,
      surgery_or_hospitalization: :boolean,
      fault: { type: :enum, values: %w[other_party shared unsure] },
      police_report: :boolean,
      other_party_insured: { type: :enum, values: %w[yes no unsure] },
      missed_work: :boolean,
      already_represented: :boolean
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Thank you — that can't have been easy to write out. Here's what we " \
         "picked up:\n\n" \
         "{% if answers.incident_type %}• Incident: **{{ answers.incident_type | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.how_long_ago %}• When: **{{ answers.how_long_ago | replace: '_', ' ' }} ago**\n{% endif %}" \
         "{% if answers.injury_type %}• Injury: **{{ answers.injury_type | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.treated_by_doctor %}• You were seen by a doctor\n{% endif %}" \
         "{% if answers.still_treating %}• You're still in treatment\n{% endif %}" \
         "{% if answers.surgery_or_hospitalization %}• Surgery or a hospital stay\n{% endif %}" \
         "{% if answers.fault %}• At fault: **{{ answers.fault | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.police_report %}• A police report was filed\n{% endif %}" \
         "{% if answers.missed_work %}• You've missed work\n{% endif %}" \
         "\nWe'll only ask about what's still missing."
    transition to: :incident_type
  end

  # The fork. Each incident type opens exactly one follow-up the others never
  # reach; all four paths rejoin at :how_long_ago.
  ask :incident_type do
    type :enum
    question "What kind of incident was it?"
    options auto_accident: "A car, truck, or motorcycle accident",
      slip_and_fall: "A slip, trip, or fall",
      medical: "Something that went wrong with medical care",
      product: "A product that failed or was unsafe",
      other: "Something else"
    skip_if not_empty(:incident_type)
    price auto_accident: 6000, slip_and_fall: 4000, medical: 12000, product: 8000, other: 2500
    transition to: :auto_role, if_rule: equals(:incident_type, "auto_accident")
    transition to: :fall_location, if_rule: equals(:incident_type, "slip_and_fall")
    transition to: :care_setting, if_rule: equals(:incident_type, "medical")
    transition to: :product_kind, if_rule: equals(:incident_type, "product")
    transition to: :how_long_ago
  end

  ask :auto_role do
    type :enum
    question "Where were you when it happened?"
    options driver: "Driving",
      passenger: "A passenger",
      motorcyclist: "On a motorcycle",
      cyclist: "On a bicycle",
      pedestrian: "On foot"
    price driver: 1500, passenger: 2500, motorcyclist: 7500, cyclist: 6000, pedestrian: 7000
    transition to: :how_long_ago
  end

  ask :fall_location do
    type :enum
    question "Where did the fall happen?"
    options business: "A store, restaurant, or other business",
      workplace: "At work",
      public_property: "On public or government property",
      private_residence: "At a private home"
    price business: 3000, workplace: 3500, public_property: 1500, private_residence: 2000
    transition to: :how_long_ago
  end

  ask :care_setting do
    type :enum
    question "Where was the care given?"
    options hospital: "A hospital",
      surgical_center: "A surgical center",
      doctor_office: "A doctor's office or clinic",
      pharmacy: "A pharmacy or prescription"
    price hospital: 9000, surgical_center: 11000, doctor_office: 5000, pharmacy: 6000
    transition to: :how_long_ago
  end

  ask :product_kind do
    type :enum
    question "What kind of product was involved?"
    options vehicle_part: "A vehicle or vehicle part",
      medical_device: "A medical device or drug",
      tool_or_machinery: "A tool or machine",
      appliance: "A household appliance",
      other: "Something else"
    price vehicle_part: 7000, medical_device: 11000, tool_or_machinery: 5500, appliance: 3500, other: 3000
    transition to: :how_long_ago
  end

  ask :how_long_ago do
    type :enum
    question "Roughly how long ago did this happen?"
    options days: "Within the last few days",
      weeks: "A few weeks ago",
      months: "Some months ago",
      over_a_year: "More than a year ago"
    skip_if not_empty(:how_long_ago)
    price days: 2000, weeks: 1500, months: 500, over_a_year: 0
    transition to: :treated_by_doctor
  end

  confirm :treated_by_doctor do
    question "Have you been seen by a doctor since it happened?"
    skip_if not_empty(:treated_by_doctor)
    price flat: 3500
    transition to: :providers_seen, if_rule: equals(:treated_by_doctor, true)
    transition to: :injury_type
  end

  ask :providers_seen do
    type :integer
    question "How many different doctors or clinics have you seen so far?"
    default 1
    min 1
    max 20
    price per_unit: 1200
    transition to: :still_treating
  end

  confirm :still_treating do
    question "Are you still being treated?"
    skip_if not_empty(:still_treating)
    price flat: 6000
    transition to: :surgery_or_hospitalization
  end

  confirm :surgery_or_hospitalization do
    question "Did any of it involve surgery or a stay in the hospital?"
    skip_if not_empty(:surgery_or_hospitalization)
    price flat: 30_000
    transition to: :injury_type
  end

  ask :injury_type do
    type :enum
    question "Which of these comes closest to your injuries?"
    options soft_tissue: "Bruising, sprains, or whiplash",
      broken_bones: "Broken bones or torn ligaments",
      head_or_spine: "A head, neck, or back injury",
      permanent: "Something that may not fully heal"
    skip_if not_empty(:injury_type)
    price soft_tissue: 2500, broken_bones: 14_000, head_or_spine: 45_000, permanent: 85_000
    transition to: :fault
  end

  ask :fault do
    type :enum
    question "As best you can tell, who caused it?"
    options other_party: "The other side",
      shared: "Some of both",
      unsure: "I honestly don't know"
    skip_if not_empty(:fault)
    price other_party: 6000, shared: 1500, unsure: 500
    transition to: :police_report
  end

  confirm :police_report do
    question "Was a police or incident report filed?"
    skip_if not_empty(:police_report)
    price flat: 2000
    transition to: :other_party_insured
  end

  ask :other_party_insured do
    type :enum
    question "Do you know whether the other side had insurance?"
    options yes: "Yes, they were insured",
      no: "No, they weren't",
      unsure: "I don't know yet"
    skip_if not_empty(:other_party_insured)
    price yes: 5000, no: 0, unsure: 1000
    transition to: :missed_work
  end

  confirm :missed_work do
    question "Have you missed any work because of this?"
    skip_if not_empty(:missed_work)
    price flat: 3000
    transition to: :work_time_missed, if_rule: equals(:missed_work, true)
    transition to: :already_represented
  end

  ask :work_time_missed do
    type :enum
    question "Roughly how much work have you missed?"
    options days: "A few days",
      weeks: "A few weeks",
      over_a_month: "More than a month",
      still_out: "I'm still not back"
    price days: 1500, weeks: 5000, over_a_month: 12_000, still_out: 22_000
    transition to: :already_represented
  end

  confirm :already_represented do
    question "Is another lawyer already representing you on this?"
    skip_if not_empty(:already_represented)
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real intake form would ask for your name and " \
         "a number, so an attorney could call you back today.\n\n" \
         "This is a demo, so we're collecting neither — and notice that nothing " \
         "we asked identifies you, or asks for a medical record. The range below " \
         "came entirely from the shape of the case." \
         "{% if answers.already_represented %}\n\nYou told us another firm already " \
         "represents you. In a real intake this is where the form would stop and " \
         "thank you: a firm can't talk to you about a case someone else is " \
         "handling.\n{% endif %}"
    transition to: :tier_complex, if_rule: any(
      equals(:injury_type, "head_or_spine"),
      equals(:injury_type, "permanent"),
      equals(:surgery_or_hospitalization, true),
      equals(:incident_type, "medical"),
      equals(:fault, "shared"),
      equals(:fault, "unsure")
    )
    transition to: :tier_standard, if_rule: any(
      equals(:injury_type, "broken_bones"),
      equals(:still_treating, true),
      equals(:missed_work, true),
      equals(:other_party_insured, "unsure")
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Potential case value: {{ price | money_range: 0.35 }}\n\n" \
         "That's a working midpoint, not a promise — real settlements move with " \
         "the medical bills and the insurer on the other side.\n\n" \
         "Yours reads as a clean one: the injuries are the kind that heal, the " \
         "other side is clearly at fault, and there's a record of it. Cases like " \
         "this usually resolve without ever seeing a courtroom.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "intake paralegal. You'd never see that; the firm would._"
  end

  say :tier_standard do
    text "## Potential case value: {{ price | money_range: 0.35 }}\n\n" \
         "That's a working midpoint, not a promise — the range widens or narrows " \
         "as treatment finishes and the bills come in.\n\n" \
         "There's real substance here: broken bones, ongoing treatment, or time " \
         "off work. An attorney will want to wait until you're done treating " \
         "before putting a number in front of the insurer, because that's when " \
         "the number stops moving.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to an " \
         "associate attorney. You'd never see that; the firm would._"
  end

  say :tier_complex do
    text "## Potential case value: {{ price | money_range: 0.35 }}\n\n" \
         "That's a working midpoint, not a promise — and in a case like yours the " \
         "spread around it is wide, which is exactly why it needs a senior hand.\n\n" \
         "Serious or lasting injuries, surgery, medical care that went wrong, or " \
         "fault that anyone might argue about all change how a case has to be " \
         "built. These are worked up as though they will be tried, whether or not " \
         "they ever are.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight " \
         "to a partner. You'd never see that; the firm would._"
  end
end
