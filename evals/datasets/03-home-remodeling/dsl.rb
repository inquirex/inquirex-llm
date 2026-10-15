# Demo flow — Kitchen, Bath & Whole-Home Remodeling (spec 012, segment 5).
#
# Headline superpower: the **scope × finish budget band**. A remodel number is
# the product of three things — which space, how deep you go, how nice the
# finishes are — and the spread between the cheap corner of that cube and the
# expensive one is a full order of magnitude. This flow makes the multiplication
# legible:
#
#   Extract  — "describe the remodel you're dreaming about" is a paragraph, not
#              a form. The LLM fills in rooms, scope, finish level, square
#              footage, layout changes, design status and timeline wherever the
#              writer actually said them; `skip_if not_empty(...)` then removes
#              every question it already answered.
#   Estimate — `accumulator :price` adds a per-space base, a scope band, a
#              finish band, a per-square-foot rate, and the structural/permit
#              work on top. Prefilled answers accumulate exactly like typed
#              ones, so a skipped question still contributes its money.
#   Tier     — G1/G2/G3 falls out of ordinary rules over the answers (no
#              lambdas — `compute` is not allowlisted, and correctly so).
#
# Honest limitation, stated here because the copy below has to live with it:
# accumulators **add**, they never multiply a running total. The spec's
# "× finish tier" is therefore expressed as a large additive band — luxury
# contributes 85,000 whether the job is a powder room or a whole house. That is
# exactly why every terminal step calls the result a *band* and never a quote.
#
# The branching fork is `rooms`: kitchen or bath opens the plumbing question, an
# addition opens the addition-type question, whole-home opens the systems
# checklist. Nobody gets asked about moving a toilet for a den remodel.
#
# One behaviour worth knowing when reading `heard_you`: `Engine#prefill!` records
# a *suggestion* for a `:multi_enum` step, not an answer — so an extracted
# `rooms` list pre-ticks the checkboxes rather than skipping the question, and
# `answers.rooms` is still empty at that point. The Liquid line for rooms is
# guarded and simply doesn't render. Everything single-valued does skip.
#
# PII-free by construction: rooms, bands, counts and yes/no only — and
# deliberately no "what's your budget?", the one question every remodeling form
# asks and every homeowner answers wrong. Where a real intake form would collect
# a name and email, a `say` step says so instead.

Inquirex.define do
  meta title: "Remodeling Project Intake",
    subtitle: "Tell us about the house you're picturing — we'll size the job"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "Describe the remodel you're dreaming about. Which rooms or spaces, " \
             "roughly how many square feet, and how far would you take it — a " \
             "refresh, down to the studs, an addition? Mention if walls or plumbing " \
             "might move, whether you have plans drawn, your timeline, and whether " \
             "you'd be living there during the work."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the homeowner's remodeling project from their description. " \
           "Only fill a field when the text genuinely supports it — leave " \
           "anything the writer did not mention unset rather than guessing. " \
           "`scope` is how deep the work goes: `refresh` for cosmetic work over " \
           "the existing layout and cabinets, `mid_range` for new cabinetry, " \
           "tile and fixtures, `gut` for taking the space back to the studs. " \
           "`finish_level` is material quality, not budget: `builder` for stock, " \
           "`mid` for semi-custom, `luxury` for custom millwork or a designer's " \
           "specification. `square_feet` is the area being remodeled, not the " \
           "size of the house — leave it unset unless a number is actually " \
           "stated. `moving_walls` is true only if the writer describes changing " \
           "the layout, opening up a wall, or taking one down."
    schema rooms: { type: :multi_enum, values: %w[kitchen bath addition whole_home] },
      scope: { type: :enum, values: %w[refresh mid_range gut] },
      finish_level: { type: :enum, values: %w[builder mid luxury] },
      square_feet: :integer,
      moving_walls: :boolean,
      design_plans: { type: :enum, values: %w[full_plans working_with_designer none] },
      timeline: { type: :enum, values: %w[asap next_3_months next_6_months just_exploring] }
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Here's what we picked up from what you wrote:\n\n" \
         "{% if answers.rooms %}• Spaces: **{{ answers.rooms | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.scope %}• Scope: **{{ answers.scope | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.finish_level %}• Finish level: **{{ answers.finish_level | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.square_feet %}• Roughly **{{ answers.square_feet }}** square feet\n{% endif %}" \
         "{% if answers.moving_walls %}• Opening up or moving walls\n{% endif %}" \
         "{% if answers.design_plans %}• Design: **{{ answers.design_plans | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.timeline %}• Timeline: **{{ answers.timeline | replace: '_', ' ' }}**\n{% endif %}" \
         "\nWe'll only ask about what's still missing."
    transition to: :rooms
  end

  ask :rooms do
    type :multi_enum
    question "Which spaces are we talking about?"
    options kitchen: "Kitchen",
      bath: "Bathroom",
      addition: "An addition — brand new square footage",
      whole_home: "The whole house"
    skip_if not_empty(:rooms)
    price per_selection: { kitchen: 9_000, bath: 4_500, addition: 22_000, whole_home: 35_000 }
    transition to: :scope
  end

  ask :scope do
    type :enum
    question "How far do you want to take it?"
    options refresh: "A refresh — paint, fixtures, countertops, keep the layout",
      mid_range: "A remodel — new cabinets, tile and fixtures, some reconfiguring",
      gut: "A gut — back to the studs and start over"
    skip_if not_empty(:scope)
    price refresh: 2_500, mid_range: 16_000, gut: 32_000
    transition to: :finish_level
  end

  ask :finish_level do
    type :enum
    question "What finish level are you picturing?"
    options builder: "Builder grade — stock cabinets, in-stock tile and fixtures",
      mid: "Mid-range — semi-custom cabinets, quartz, name-brand fixtures",
      luxury: "High end — custom millwork, stone slabs, designer specification"
    skip_if not_empty(:finish_level)
    price builder: 2_500, mid: 16_000, luxury: 85_000
    transition to: :square_feet
  end

  ask :square_feet do
    type :integer
    question "Roughly how many square feet are we remodeling? A good guess is fine."
    default 200
    min 20
    max 10_000
    skip_if not_empty(:square_feet)
    price per_unit: 35
    transition to: :moving_walls
  end

  confirm :moving_walls do
    question "Are you moving or removing any walls?"
    skip_if not_empty(:moving_walls)
    price flat: 9_500
    transition to: :moving_plumbing, if_rule: any(
      contains(:rooms, "kitchen"),
      contains(:rooms, "bath")
    )
    transition to: :addition_type, if_rule: contains(:rooms, "addition")
    transition to: :whole_home_systems, if_rule: contains(:rooms, "whole_home")
    transition to: :permit_work
  end

  confirm :moving_plumbing do
    question "Would the sink, tub, or toilet end up somewhere new?"
    price flat: 7_500
    transition to: :addition_type, if_rule: contains(:rooms, "addition")
    transition to: :whole_home_systems, if_rule: contains(:rooms, "whole_home")
    transition to: :permit_work
  end

  ask :addition_type do
    type :enum
    question "What kind of addition are you imagining?"
    options bump_out: "A bump-out — a few feet onto a room that's already there",
      single_story: "A single-story addition on a new foundation",
      second_story: "A second story, or a full two-story addition"
    price bump_out: 15_000, single_story: 45_000, second_story: 90_000
    transition to: :whole_home_systems, if_rule: contains(:rooms, "whole_home")
    transition to: :permit_work
  end

  ask :whole_home_systems do
    type :multi_enum
    question "While the walls are open, which systems would you replace?"
    options hvac: "Heating and cooling",
      electrical_panel: "Electrical service and panel",
      plumbing_repipe: "Repiping the house",
      windows: "Windows throughout",
      none: "None of these — finishes only"
    price per_selection: { hvac: 18_000, electrical_panel: 9_000, plumbing_repipe: 14_000,
                          windows: 22_000, none: 0 }
    transition to: :permit_work
  end

  ask :permit_work do
    type :multi_enum
    question "Which of these will the work touch? Anything checked here means " \
             "drawings, a permit, and an inspector."
    options electrical: "Electrical",
      plumbing: "Plumbing",
      structural: "Structural — beams, headers, load-bearing walls",
      none: "None of the above"
    price per_selection: { electrical: 6_500, plumbing: 5_500, structural: 12_000, none: 0 }
    transition to: :design_plans
  end

  ask :design_plans do
    type :enum
    question "Where are you with design?"
    options full_plans: "We have finished drawings, ready to build from",
      working_with_designer: "We're working with a designer or architect now",
      none: "Nothing yet — we'd want help choosing everything"
    skip_if not_empty(:design_plans)
    price full_plans: 0, working_with_designer: 1_200, none: 2_000
    transition to: :timeline
  end

  ask :timeline do
    type :enum
    question "When would you like work to start?"
    options asap: "As soon as you can — we're ready",
      next_3_months: "In the next three months",
      next_6_months: "Sometime in the next six months",
      just_exploring: "No date yet — we're still dreaming"
    skip_if not_empty(:timeline)
    price asap: 8_500, next_3_months: 3_000, next_6_months: 0, just_exploring: 0
    transition to: :living_there
  end

  confirm :living_there do
    question "Will you be living in the house while the work is happening?"
    price flat: 1_800
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real intake form would ask for your name and " \
         "email so the builder could follow up.\n\n" \
         "This is a demo, so we're not collecting either — and notice that nothing " \
         "we asked identifies you, or your address, or your budget. The band below " \
         "came entirely from the shape of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:scope, "gut"),
      equals(:finish_level, "luxury"),
      contains(:rooms, "addition"),
      contains(:rooms, "whole_home"),
      contains(:permit_work, "structural")
    )
    transition to: :tier_standard, if_rule: any(
      equals(:scope, "mid_range"),
      equals(:finish_level, "mid"),
      equals(:moving_walls, true),
      equals(:moving_plumbing, true)
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This is the happy end of remodeling: the layout stays, the plumbing stays, " \
         "and the room you walk into afterwards is the one you already have — just " \
         "the version you wanted. Jobs like this are measured in weeks, not seasons, " \
         "and the number above moves mostly with the finishes you fall in love with.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "self-serve queue. You'd never see that; the firm would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This is a real remodel — new cabinetry or tile, and enough reconfiguring " \
         "that a plan has to exist before anyone swings a hammer. Read the number " \
         "above as a band rather than a price: scope and finish level multiply " \
         "against each other, so the same footprint can land a good way either side " \
         "of it once the selections are made. Expect a walkthrough and a fixed bid.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to a " \
         "project manager. You'd never see that; the firm would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This one has structure in it — studs, footings, new square footage, or " \
         "finishes specified rather than shopped. That means drawings, permits, an " \
         "engineer's stamp on somebody's desk, and a superintendent who lives on " \
         "your site. The band above is wide on purpose and it should be: at this " \
         "scope, the difference between a good estimate and a real one is a set of " \
         "plans. The next conversation is about getting you those.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight to " \
         "a senior estimator. You'd never see that; the firm would._"
  end
end
