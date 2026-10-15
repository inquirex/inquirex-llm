# Demo flow — Immigration Law (spec 012, segment 3).
#
# The headline here is **pathway-driven branching**. One question — "what are you
# trying to do?" — forks into four genuinely different interviews. An employment
# case asks about sponsors and categories; a family case asks about the relative
# and the sponsor's own status; a humanitarian case asks about protection type and
# whether the government has started a case; a citizenship case asks about years
# held, English, and long trips. Nothing is shared between the four but the tail.
#
# The other two superpowers ride along:
#   Extract  — the opener is a free-text description. The LLM fills in whatever it
#              can, and `skip_if not_empty(...)` means every question it answered is
#              never asked. Extracting `primary_goal` is the good demo: the fork
#              itself resolves from the ramble, and the visitor lands straight in
#              their own pathway.
#   Estimate — `accumulator :price` sums a flat fee per petition type. A family
#              green card, an EB-1 and an asylum case are different orders of
#              effort, and the branches price accordingly.
#   Tier     — G1/G2/G3 falls out of ordinary rules. No lambdas: `compute` is not
#              allowlisted, and correctly so.
#
# PII-free by construction, and deliberately more careful than the other demos:
# no country of origin, no A-numbers, no dates, no case numbers, no arrest
# history. Categories, counts and yes/no only. The copy is plain-spoken because
# this audience is anxious and often reading in a second language.

Inquirex.define do
  meta title: "Immigration Consultation",
    subtitle: "Tell us where you are and where you want to be"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "In your own words, what are you hoping to accomplish, and where do " \
             "things stand right now? It helps to mention your current status, " \
             "whether you're in the U.S. today, what you're aiming for — work, " \
             "family, humanitarian relief, citizenship — and any deadlines or " \
             "prior denials. Write as much or as little as you like."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the writer's immigration situation from their description. " \
           "Only fill a field when the text genuinely supports it — leave " \
           "anything the writer did not mention unset rather than guessing. " \
           "`family_members` is a count of relatives who would be included with " \
           "them; use 0 when the writer says nobody else is involved, and leave " \
           "it unset when they simply did not say. Never infer `prior_denial` " \
           "from worry or uncertainty alone — only from a stated denial or court " \
           "case. Do not record nationality, dates, or any identifying detail."
    schema current_status: { type: :enum,
                            values: %w[visitor student work_visa green_card pending_case no_status unsure] },
      primary_goal: { type: :enum,
                     values: %w[employment family humanitarian citizenship] },
      in_us: :boolean,
      employer_sponsor: :boolean,
      prior_denial: :boolean,
      deadline_soon: :boolean,
      family_members: :integer
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Thank you. Here is what we understood — you can correct anything later:\n\n" \
         "{% if answers.current_status %}• Where you stand now: **{{ answers.current_status | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.primary_goal %}• What you're working toward: **{{ answers.primary_goal }}**\n{% endif %}" \
         "{% if answers.in_us %}• You're in the United States right now\n{% endif %}" \
         "{% if answers.employer_sponsor %}• An employer is willing to sponsor you\n{% endif %}" \
         "{% if answers.prior_denial %}• There's been a denial or a court case before\n{% endif %}" \
         "{% if answers.deadline_soon %}• Something is due soon\n{% endif %}" \
         "{% if answers.family_members %}• Family included: **{{ answers.family_members }}**\n{% endif %}" \
         "\nWe'll only ask about what you haven't already told us."
    transition to: :current_status
  end

  ask :current_status do
    type :enum
    question "Which of these is closest to your situation today?"
    options visitor: "Here on a visitor or tourist visa",
      student: "Here on a student visa",
      work_visa: "Here on a work visa",
      green_card: "I have a green card",
      pending_case: "I already have a case filed and waiting",
      no_status: "I have no status right now, or mine has expired",
      unsure: "I'm not sure"
    skip_if not_empty(:current_status)
    price visitor: 400, student: 400, work_visa: 450, green_card: 350,
      pending_case: 600, no_status: 850, unsure: 500
    transition to: :in_us
  end

  confirm :in_us do
    question "Are you in the United States right now?"
    skip_if not_empty(:in_us)
    price flat: 350
    transition to: :primary_goal
  end

  ask :primary_goal do
    type :enum
    question "What are you mainly trying to do?"
    options employment: "Work in the U.S., or stay through my job",
      family: "Be with family, or bring family here",
      humanitarian: "Get protection or safety",
      citizenship: "Become a U.S. citizen"
    skip_if not_empty(:primary_goal)
    price employment: 1200, family: 900, humanitarian: 1500, citizenship: 400
    transition to: :employer_sponsor, if_rule: equals(:primary_goal, "employment")
    transition to: :family_relationship, if_rule: equals(:primary_goal, "family")
    transition to: :humanitarian_type, if_rule: equals(:primary_goal, "humanitarian")
    transition to: :green_card_years, if_rule: equals(:primary_goal, "citizenship")
    transition to: :prior_denial
  end

  confirm :employer_sponsor do
    question "Is there a U.S. employer who has offered to sponsor you?"
    skip_if not_empty(:employer_sponsor)
    price flat: 1500
    transition to: :employment_category
  end

  ask :employment_category do
    type :enum
    question "Which of these sounds like the route you're on?"
    options h1b: "A work visa such as H-1B",
      intracompany: "A transfer within the company I already work for",
      perm: "A green card sponsored by my employer",
      niw: "A green card based on my own work being in the national interest",
      eb1: "A green card based on outstanding achievement in my field",
      unsure: "I don't know which one fits"
    price h1b: 3500, intracompany: 4500, perm: 7500, niw: 10_000,
      eb1: 12_000, unsure: 3500
    transition to: :job_offer_stage
  end

  ask :job_offer_stage do
    type :enum
    question "How far along is the job side of this?"
    options offer_signed: "I have a written offer",
      verbal: "A verbal offer, nothing in writing yet",
      searching: "Still looking for the right role",
      self_petition: "I'd be applying on my own, without an employer"
    price offer_signed: 0, verbal: 500, searching: 750, self_petition: 1800
    transition to: :prior_denial
  end

  ask :family_relationship do
    type :enum
    question "Who is the family member this is about?"
    options spouse: "My husband or wife",
      fiance: "The person I plan to marry",
      parent: "My parent",
      child: "My child",
      sibling: "My brother or sister"
    price spouse: 3500, fiance: 3800, parent: 3000, child: 3000, sibling: 4200
    transition to: :sponsor_status
  end

  ask :sponsor_status do
    type :enum
    question "What is the status of the person doing the sponsoring?"
    options citizen: "U.S. citizen",
      green_card: "Green card holder",
      not_sure: "I'm not sure"
    price citizen: 0, green_card: 900, not_sure: 500
    transition to: :marriage_length
  end

  ask :marriage_length do
    type :enum
    question "If this is a marriage case, how long have you been married?"
    options under_two: "Less than two years",
      over_two: "Two years or more",
      not_married: "This isn't a marriage case"
    price under_two: 1100, over_two: 300, not_married: 0
    transition to: :prior_denial
  end

  ask :humanitarian_type do
    type :enum
    question "Which kind of protection are you asking about?"
    options asylum: "Asylum — I'm afraid to return to my home country",
      abuse: "Protection after abuse by a family member",
      crime_victim: "I was the victim of a crime here",
      trafficking: "I was forced into work or trafficked",
      temporary: "Temporary protected status for my country",
      unsure: "I'm not sure which one applies"
    price asylum: 9000, abuse: 7500, crime_victim: 6500, trafficking: 7000,
      temporary: 2200, unsure: 6500
    transition to: :one_year_in_us
  end

  confirm :one_year_in_us do
    question "Have you been in the United States for more than one year?"
    price flat: 1500
    transition to: :removal_proceedings
  end

  confirm :removal_proceedings do
    question "Has the government started a case to remove you from the country?"
    price flat: 4500
    transition to: :prior_denial
  end

  ask :green_card_years do
    type :enum
    question "How long have you held your green card?"
    options not_yet: "I don't have one yet",
      under_three: "Less than three years",
      three_to_five: "Between three and five years",
      over_five: "More than five years"
    price not_yet: 1200, under_three: 600, three_to_five: 0, over_five: 0
    transition to: :english_comfort
  end

  ask :english_comfort do
    type :enum
    question "How do you feel about the English part of the interview?"
    options comfortable: "Comfortable — no help needed",
      some_help: "I'd like some practice first",
      exemption: "I may not have to take it, because of my age or health"
    price comfortable: 0, some_help: 400, exemption: 700
    transition to: :long_trips_abroad
  end

  confirm :long_trips_abroad do
    question "Since getting your green card, have you taken any trip outside the " \
             "U.S. longer than six months?"
    price flat: 900
    transition to: :prior_denial
  end

  confirm :prior_denial do
    question "Has any immigration application of yours ever been denied, or have " \
             "you been in immigration court?"
    skip_if not_empty(:prior_denial)
    price flat: 1800
    transition to: :deadline_soon
  end

  confirm :deadline_soon do
    question "Is there a deadline, a court date, or a status running out in the " \
             "next couple of months?"
    skip_if not_empty(:deadline_soon)
    price flat: 950
    transition to: :family_members
  end

  ask :family_members do
    type :integer
    question "How many family members would be included with you?"
    default 0
    min 0
    max 10
    skip_if not_empty(:family_members)
    price per_unit: 650
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is where a real intake form would ask for your name and email so " \
         "the firm could call you back.\n\n" \
         "This is a demo, so we're collecting neither — and look back at what we " \
         "asked: no country, no dates, no case numbers, nothing that identifies " \
         "you. The estimate below came only from the shape of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:primary_goal, "humanitarian"),
      equals(:prior_denial, true),
      equals(:removal_proceedings, true),
      equals(:current_status, "no_status"),
      equals(:employment_category, "eb1"),
      equals(:employment_category, "niw")
    )
    transition to: :tier_standard, if_rule: any(
      equals(:primary_goal, "employment"),
      equals(:employer_sponsor, true),
      equals(:deadline_soon, true),
      greater_than(:family_members, 2)
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "Yours is the kind of case a firm handles start to finish without drama — " \
         "one petition, a clear record, no deadline breathing down your neck. Most " \
         "of the work is getting the paperwork exactly right the first time.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "firm's intake team. You'd never see that; the firm would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "There's real work here — an employer in the picture, or several people on " \
         "the case, or a date to hit. Expect an attorney to map out the sequence " \
         "with you before anything gets filed.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to an " \
         "associate attorney. You'd never see that; the firm would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This one belongs with a senior attorney. Protection cases, a past denial, " \
         "a court case, a lapse in status, or a petition built on your own record " \
         "all carry real stakes, and the range reflects the hours that go with " \
         "them.\n\n" \
         "You should also know that a range is not advice, and nothing here creates " \
         "a lawyer-client relationship. It's a starting point for a conversation " \
         "with someone who can actually look at your situation.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight " \
         "to a partner. You'd never see that; the firm would._"
  end
end
