# Demo flow — Couples & Family Therapy (spec 012, segment 6).
#
# The headline here is **multi-party branching**: the same link behaves
# differently depending on whether one person opened it or two people are sitting
# in front of it. One question — "are you filling this out on your own, or
# together?" — forks into two genuinely different interviews. The together path
# asks about the two of you: whether you both plan to come, how aligned you feel,
# what you're weighing. The solo path asks about you: where the other person is
# with the idea, who you'd picture in the room, what you'd want out of a first
# conversation. Nothing is shared between the two but the logistics tail.
#
# The other two superpowers ride along:
#   Extract  — the opener is a free-text description in the visitor's own words.
#              The LLM fills in whatever it honestly can, and `skip_if
#              not_empty(...)` means every question it answered is never asked.
#              `participation` is the good demo: the fork itself often resolves
#              from the ramble ("my wife and I are sitting down to do this"), and
#              the visitor lands straight in the right interview.
#   Estimate — `accumulator :price` builds a **per-session rate**, not a total.
#              A base rate by modality (individual / couple / family) plus small
#              adders for format, cadence, clinician seniority and out-of-hours
#              scheduling. The numbers stay inside the $130–$400 per session that
#              private-pay practices actually charge; the cadence recommendation
#              ("weekly for 8–12 weeks") lives in the tier copy.
#   Tier     — G1/G2/G3 falls out of ordinary rules. No lambdas: `compute` is not
#              allowlisted, and correctly so.
#
# Deliberately **not** clinical. This is lead routing, not triage. There are no
# symptoms, no diagnoses, no history, no safety questions — spec 012 cut the
# triage segment for exactly that reason, and the same logic applies here. What's
# asked are concern *categories*, durations, and logistics: enough to price the
# work and pick the right clinician, and nothing a practice would need a release
# form to hold. The copy is unhurried and non-judgmental because people fill this
# out on a hard day.

Inquirex.define do
  meta title: "Therapy Intake",
    subtitle: "Wherever you're starting from, this takes about two minutes"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "In your own words, what's bringing you to therapy right now? " \
             "It helps to mention whether this is for you, you and a partner, or " \
             "your family, how long things have felt this way, who would take part, " \
             "and how you'd prefer to meet — in person or online. Write as much or " \
             "as little as you like — there's no wrong answer."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the writer's situation from their description so the practice " \
           "can route and schedule them. Only fill a field when the text " \
           "genuinely supports it — leave anything the writer did not mention " \
           "unset rather than guessing. `primary_concern` is the single category " \
           "the writer leads with; if they name several, pick the one they spend " \
           "the most words on, and leave it unset when nothing dominates. Set " \
           "`participation` to `together` only when the writer clearly speaks as " \
           "two or more people filling this out at the same time. Never infer " \
           "`both_attending` from hope or intention — only from a stated plan. " \
           "Record no names, no ages, no locations, and nothing about symptoms, " \
           "diagnoses, medication or treatment history, even if the writer " \
           "volunteers it."
    schema seeking_for: { type: :enum, values: %w[individual couple family] },
      participation: { type: :enum, values: %w[solo together] },
      primary_concern: { type: :enum,
                        values: %w[communication trust parenting intimacy separation] },
      how_long: { type: :enum,
                 values: %w[under_three_months three_to_twelve_months
                   one_to_three_years longer_than_that] },
      both_attending: :boolean,
      session_format: { type: :enum, values: %w[virtual in_person either] },
      start_timing: { type: :enum,
                     values: %w[as_soon_as_possible next_few_weeks just_exploring] },
      prior_therapy: :boolean
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Thank you for writing that out. Here's what we took from it — you can " \
         "correct any of it as we go:\n\n" \
         "{% if answers.seeking_for %}• Who this is for: **{{ answers.seeking_for | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.participation %}• Filling this out: **{{ answers.participation }}**\n{% endif %}" \
         "{% if answers.primary_concern %}• What's front of mind: **{{ answers.primary_concern }}**\n{% endif %}" \
         "{% if answers.how_long %}• How long it's been going on: **{{ answers.how_long | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.both_attending %}• You're both planning to attend\n{% endif %}" \
         "{% if answers.session_format %}• Preferred format: **{{ answers.session_format | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.start_timing %}• When you'd like to start: **{{ answers.start_timing | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.prior_therapy %}• You've worked with a therapist before\n{% endif %}" \
         "\nWe'll only ask about what you haven't already told us."
    transition to: :not_an_emergency_line
  end

  btw :not_an_emergency_line do
    text "One thing before we go on. A real practice would put its crisis " \
         "resources right here — the local hotline, the after-hours number, who " \
         "to call tonight rather than next week.\n\n" \
         "This is a demo form, so it has none of that and handles no " \
         "emergencies. If something is urgent, please contact a real practice or " \
         "your local emergency services instead of finishing this."
    transition to: :seeking_for
  end

  ask :seeking_for do
    type :enum
    question "Who would this be for?"
    options individual: "Just me",
      couple: "My partner and me",
      family: "Our family — parents and children, or other relatives"
    skip_if not_empty(:seeking_for)
    price individual: 130, couple: 165, family: 175
    transition to: :primary_concern
  end

  ask :primary_concern do
    type :enum
    question "If you had to name one thing to start with, which is closest?"
    options communication: "How we talk to each other",
      trust: "Trust between us",
      parenting: "Parenting, or how we handle the kids",
      intimacy: "Closeness and intimacy",
      separation: "Whether to stay together"
    skip_if not_empty(:primary_concern)
    price communication: 0, trust: 15, parenting: 10, intimacy: 10, separation: 20
    transition to: :how_long
  end

  ask :how_long do
    type :enum
    question "Roughly how long has this been on your mind?"
    options under_three_months: "A few weeks or months",
      three_to_twelve_months: "Most of this year",
      one_to_three_years: "A year or two",
      longer_than_that: "Longer than that"
    skip_if not_empty(:how_long)
    price under_three_months: 0, three_to_twelve_months: 5,
      one_to_three_years: 10, longer_than_that: 10
    transition to: :participation
  end

  # The fork. Everything from here until :session_format differs by path.
  ask :participation do
    type :enum
    question "Are you filling this out on your own, or together with the other " \
             "person?"
    options solo: "On my own",
      together: "Together, right now"
    skip_if not_empty(:participation)
    price solo: 0, together: 15
    transition to: :both_attending, if_rule: equals(:participation, "together")
    transition to: :invite_note
  end

  # ---------------------------------------------------------------- solo path

  say :invite_note do
    text "That's completely normal — most people reach out first and bring the " \
         "other person along later.\n\n" \
         "In a real deployment this is the moment the form would offer to send " \
         "your partner their own private link. They'd answer their own version " \
         "of these questions, in their own words, without seeing yours, and the " \
         "practice would see the two side by side before the first session. " \
         "This demo doesn't send anything — it just shows you where that would " \
         "happen."
    transition to: :partner_readiness
  end

  ask :partner_readiness do
    type :enum
    question "Where do you think the other person is with the idea of therapy?"
    options ready_to_join: "Ready to come — we've talked about it",
      open_but_hesitant: "Open to it, but hesitant",
      not_ready_yet: "Not ready yet",
      not_sure: "Honestly, I'm not sure"
    price ready_to_join: 0, open_but_hesitant: 15, not_ready_yet: 20, not_sure: 15
    transition to: :who_would_attend
  end

  ask :who_would_attend do
    type :enum
    question "If this went ahead, who would you picture in the room?"
    options just_me: "Just me, at least to begin with",
      me_and_partner: "The two of us",
      whole_family: "The whole family",
      not_sure: "I haven't got that far"
    price just_me: 0, me_and_partner: 15, whole_family: 20, not_sure: 10
    transition to: :solo_goal
  end

  ask :solo_goal do
    type :enum
    question "What would you most want out of a first conversation?"
    options improve_communication: "Ideas for talking to each other differently",
      understand_options: "To understand what our options even are",
      decide_next_step: "Help deciding what to do next",
      support_for_myself: "Somewhere to think it through for myself"
    price improve_communication: 0, understand_options: 5,
      decide_next_step: 20, support_for_myself: 0
    transition to: :session_format
  end

  # ------------------------------------------------------------ together path

  confirm :both_attending do
    question "Are you both planning to come to the sessions?"
    skip_if not_empty(:both_attending)
    price flat: 10
    transition to: :shared_goal
  end

  ask :shared_goal do
    type :enum
    question "When the two of you talk about what you'd want from this, how " \
             "close together are you?"
    options mostly_aligned: "Mostly on the same page",
      partly_aligned: "Some of it overlaps",
      still_figuring_out: "Still working that out"
    price mostly_aligned: 0, partly_aligned: 10, still_figuring_out: 15
    transition to: :weighing_separation
  end

  confirm :weighing_separation do
    question "Is one of the things you're weighing whether to stay together?"
    price flat: 20
    transition to: :blended_household
  end

  confirm :blended_household do
    question "Are there children from a previous relationship in the household?"
    price flat: 15
    transition to: :session_format
  end

  # ------------------------------------------------------- shared logistics

  ask :session_format do
    type :enum
    question "Would you rather meet in person or by video?"
    options virtual: "By video",
      in_person: "In person",
      either: "Either works"
    skip_if not_empty(:session_format)
    price virtual: 0, in_person: 15, either: 5
    transition to: :session_cadence
  end

  ask :session_cadence do
    type :enum
    question "How often would you like to meet, if it were up to you?"
    options weekly: "Weekly",
      every_other_week: "Every other week",
      monthly: "About once a month",
      not_sure: "I'd take the therapist's advice"
    price weekly: 0, every_other_week: 10, monthly: 15, not_sure: 5
    transition to: :clinician_preference
  end

  ask :clinician_preference do
    type :enum
    question "Any preference about who you're matched with?"
    options no_preference: "No preference — whoever's the right fit",
      experienced: "Someone with more years in practice",
      specialist: "A specialist in what we're dealing with"
    price no_preference: 0, experienced: 30, specialist: 40
    transition to: :prior_therapy
  end

  confirm :prior_therapy do
    question "Have you worked with a therapist before, on this or anything else?"
    skip_if not_empty(:prior_therapy)
    price flat: 10
    transition to: :start_timing
  end

  ask :start_timing do
    type :enum
    question "When would you like to start?"
    options as_soon_as_possible: "As soon as there's an opening",
      next_few_weeks: "In the next few weeks",
      just_exploring: "Just looking into it for now"
    skip_if not_empty(:start_timing)
    price as_soon_as_possible: 15, next_few_weeks: 5, just_exploring: 0
    transition to: :scheduling_constraints
  end

  ask :scheduling_constraints do
    type :multi_enum
    question "Which times could you actually make? Pick as many as apply."
    options weekday_daytime: "Weekday daytime",
      evenings: "Weekday evenings",
      weekends: "Weekends",
      flexible: "I'm flexible"
    price per_selection: { weekday_daytime: 0, evenings: 10, weekends: 15, flexible: 0 }
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is where a real practice would ask for your name and email so " \
         "someone could get back to you with actual openings.\n\n" \
         "This is a demo, so we're collecting neither — and look back at what we " \
         "asked: no names, no ages, no history, nothing about what you're going " \
         "through beyond a category you picked yourself. Nothing here identifies " \
         "you. The estimate below came only from the shape of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:primary_concern, "separation"),
      equals(:weighing_separation, true),
      equals(:blended_household, true),
      equals(:both_attending, false),
      equals(:partner_readiness, "not_ready_yet"),
      equals(:partner_readiness, "not_sure"),
      equals(:solo_goal, "decide_next_step"),
      all(
        equals(:primary_concern, "trust"),
        equals(:how_long, "under_three_months")
      )
    )
    transition to: :tier_standard, if_rule: any(
      equals(:seeking_for, "family"),
      equals(:prior_therapy, true),
      equals(:shared_goal, "still_figuring_out"),
      equals(:partner_readiness, "open_but_hesitant"),
      equals(:who_would_attend, "whole_family"),
      equals(:how_long, "three_to_twelve_months"),
      equals(:how_long, "one_to_three_years"),
      equals(:how_long, "longer_than_that")
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }} per session\n\n" \
         "That's the per-session rate for this practice — private-pay rates in " \
         "most areas run somewhere between $130 and $400 depending on modality " \
         "and how senior the clinician is.\n\n" \
         "For something recent and reasonably well-defined, with everyone " \
         "involved on board, practices usually suggest **weekly sessions for " \
         "about 8 weeks**, then a conversation about whether to keep going. " \
         "Plenty of people are done at that point.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to an " \
         "associate clinician with near-term availability. You'd never see that; " \
         "the practice would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }} per session\n\n" \
         "That's the per-session rate for this practice — private-pay rates in " \
         "most areas run somewhere between $130 and $400 depending on modality " \
         "and how senior the clinician is.\n\n" \
         "Something that's been running for a while, or that involves more than " \
         "two people, usually takes a bit longer to unpick. The common shape is " \
         "**weekly for 10 to 12 weeks**, moving to every other week once things " \
         "settle.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to the " \
         "practice's standard couples-work caseload. You'd never see that; the " \
         "practice would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }} per session\n\n" \
         "That's the per-session rate for this practice — private-pay rates in " \
         "most areas run somewhere between $130 and $400 depending on modality " \
         "and how senior the clinician is.\n\n" \
         "What you've described is the kind of work practices hand to their most " \
         "experienced people: a decision in the balance, a blended household, or " \
         "one person further along than the other. That's ordinary, and it's " \
         "workable — it just isn't beginner's work. Expect **weekly for 12 weeks " \
         "or more**, sometimes with a session or two on your own alongside the " \
         "joint ones.\n\n" \
         "A range is not a treatment plan, and no form can tell you what will " \
         "help. It's a starting point for a conversation with someone who can " \
         "actually listen.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed to a " \
         "senior or specialist clinician. You'd never see that; the practice " \
         "would._"
  end
end
