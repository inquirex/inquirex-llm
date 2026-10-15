# Demo flow — Roofing & Exterior Restoration (spec 012, segment 4).
#
# The headline here is the **formula**. This is the one segment where the
# estimate is arithmetic a roofer would recognise rather than a judgement call:
#
#   roof area × $/sq ft   →  `price per_unit:`  — the one number we always ask
#   + pitch premium       →  `price lookup:`    — access, staging, fall arrest
#   + material tier       →  `price lookup:`    — like-for-like assumed
#   + scope, stories, age, extras, storm/insurance, urgency
#
# Accumulators add; they do not multiply. A literal "footprint × pitch ×
# material" product is therefore approximated as area × rate plus tiered
# adders — which is also how a real estimate is written, line by line, so the
# approximation costs nothing in credibility.
#
# Two things to read before editing:
#
#   `roof_area_sqft` is deliberately absent from the extract schema. Every
#   other prefilled answer is a category; that one is money. `prefill!` runs
#   accumulations exactly like a typed answer, so an LLM that hears "our
#   2,000 sq ft house has a leak over the garage" and helpfully fills in 2,000
#   would bill a shingle repair as a full re-roof. The homeowner types that
#   number, every time.
#
#   Every priced step sits on the main line. The only branch-local questions
#   belong to the storm/insurance fork, and that fork routes on
#   `any(storm_damage, filing_insurance)` precisely so an extracted
#   `filing_insurance` cannot charge for a branch it never enters.
#
# PII-free by construction: stories, bands, counts and yes/no. No address, no
# name, no email — the `contact_placeholder` step says so out loud.

Inquirex.define do
  meta title: "Roofing & Exterior Restoration",
    subtitle: "Tell us what's happening up there — we'll price it from the roof, not the guesswork"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "Tell us about your roof and what's going on with it. How old is it, " \
             "what's it made of, and what are you seeing — leaks, missing shingles, " \
             "sagging? Mention how many stories the house is, roughly how big the " \
             "roof is, whether a storm had anything to do with it, and if an " \
             "insurance claim is in the picture."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the roof job from the homeowner's description. Only fill a field " \
           "when the text genuinely supports it — leave anything the writer did not " \
           "mention unset rather than guessing. Do not infer `project_scope` from a " \
           "leak alone: a leak can be a repair or the reason for a full replacement, " \
           "so leave it unset unless the writer says which. Set `leaking_now` true " \
           "only for water coming in now, not for past or repaired leaks. Never " \
           "estimate roof area, pitch, or age from a photo description or a house " \
           "size — those are unset unless stated."
    schema project_scope: { type: :enum,
                           values: %w[repair full_replacement full_exterior] },
      stories: { type: :enum, values: %w[one two three_plus] },
      roof_pitch: { type: :enum, values: %w[flat walkable steep] },
      material: { type: :enum,
                 values: %w[asphalt_3tab architectural wood_shake metal tile_slate not_sure] },
      roof_age: { type: :enum, values: %w[under_10 ten_to_twenty over_20 not_sure] },
      leaking_now: :boolean,
      storm_damage: :boolean,
      filing_insurance: :boolean,
      timeline: { type: :enum,
                 values: %w[emergency weeks planning researching] }
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Here's what we picked up from what you wrote:\n\n" \
         "{% if answers.project_scope %}• What you need: **{{ answers.project_scope | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.stories %}• Stories: **{{ answers.stories | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.material %}• Current material: **{{ answers.material | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.roof_pitch %}• Pitch: **{{ answers.roof_pitch }}**\n{% endif %}" \
         "{% if answers.roof_age %}• Roof age: **{{ answers.roof_age | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.leaking_now %}• Water coming in now — we're treating this as urgent\n{% endif %}" \
         "{% if answers.storm_damage %}• Storm damage\n{% endif %}" \
         "{% if answers.filing_insurance %}• Insurance claim involved\n{% endif %}" \
         "{% if answers.timeline %}• Timeline: **{{ answers.timeline | replace: '_', ' ' }}**\n{% endif %}" \
         "\nWe'll only ask about what's still missing — and none of it is personal."
    transition to: :leaking_now
  end

  # Urgency first. Somebody with water in the house does not want to answer nine
  # questions before anyone acknowledges the water.
  confirm :leaking_now do
    question "Is water getting into the house right now?"
    skip_if not_empty(:leaking_now)
    price flat: 450
    transition to: :leak_urgency, if_rule: equals(:leaking_now, true)
    transition to: :project_scope
  end

  warning :leak_urgency do
    text "Understood — active water intrusion moves you to the front of the queue.\n\n" \
         "If you can do it safely from **inside**, put a bucket under the drip and " \
         "move anything valuable out from under it. Do not go up on a wet roof. " \
         "The rest of this takes about a minute and tells us what to put on the truck."
    transition to: :project_scope
  end

  ask :project_scope do
    type :enum
    question "Are we fixing something, or replacing the roof?"
    options repair: "Repair a specific problem",
      full_replacement: "Replace the whole roof",
      full_exterior: "Roof plus siding, gutters or trim"
    skip_if not_empty(:project_scope)
    # Mobilisation, tear-off and dumpster. The area question below carries the
    # size of the job; this is the fixed cost of showing up and hauling away.
    price repair: 250, full_replacement: 1200, full_exterior: 3200
    transition to: :stories
  end

  ask :stories do
    type :enum
    question "How many stories is the house?"
    options one: "One story",
      two: "Two stories",
      three_plus: "Three or more"
    skip_if not_empty(:stories)
    price one: 0, two: 700, three_plus: 1800
    transition to: :roof_area_sqft
  end

  # ---------------------------------------------------------------------------
  # The formula. Area sets the magnitude; pitch and material are the multipliers
  # a roofer would apply, flattened into tier adders because accumulators sum.
  # Written with the explicit `per_unit:` / `lookup:` shapes so the arithmetic
  # reads as arithmetic — the rest of this flow uses the plain-keys shorthand.
  # ---------------------------------------------------------------------------

  ask :roof_area_sqft do
    type :integer
    question "Roughly how many square feet of roof are we working on? " \
             "For a repair that's the damaged area; for a replacement it's the whole roof. " \
             "A rough guess is fine — we measure it properly on site."
    default 2000
    min 50
    max 12_000
    # Deliberately no skip_if. See the header: this is the only answer that sets
    # the order of magnitude, so it is never taken from an LLM's reading.
    price per_unit: 5.25
    transition to: :roof_pitch
  end

  ask :roof_pitch do
    type :enum
    question "How steep is it?"
    options flat: "Flat or very low slope",
      walkable: "Normal — you could walk it",
      steep: "Steep — you'd need to be tied off"
    skip_if not_empty(:roof_pitch)
    price lookup: { flat: 900, walkable: 0, steep: 2400 }
    transition to: :material
  end

  ask :material do
    type :enum
    question "What's on the roof right now?"
    options asphalt_3tab: "Asphalt — 3-tab shingles",
      architectural: "Asphalt — architectural or dimensional",
      wood_shake: "Wood shake or shingle",
      metal: "Metal",
      tile_slate: "Tile or slate",
      not_sure: "Not sure"
    skip_if not_empty(:material)
    # Assumes like-for-like, which is what insurance pays for and what most
    # homeowners choose. `material_preference` below prices the upgrade delta.
    price lookup: { asphalt_3tab: 0, architectural: 1400, wood_shake: 4200,
                   metal: 6800, tile_slate: 9500, not_sure: 700 }
    transition to: :roof_age
  end

  ask :roof_age do
    type :enum
    question "How old is the current roof?"
    options under_10: "Less than 10 years",
      ten_to_twenty: "10 to 20 years",
      over_20: "More than 20 years",
      not_sure: "Not sure"
    skip_if not_empty(:roof_age)
    # Older decking hides more rot. This is the contingency, not a penalty.
    price under_10: 0, ten_to_twenty: 350, over_20: 900, not_sure: 350
    transition to: :additional_work
  end

  ask :additional_work do
    type :multi_enum
    question "Anything else on the exterior while we're set up?"
    options roof_only: "Roof only",
      gutters: "Gutters and downspouts",
      ventilation: "Attic ventilation",
      skylights: "Skylights",
      siding: "Siding"
    # No skip_if: an LLM's read of a multi_enum is recorded as a *suggestion*,
    # never an answer, so it cannot satisfy not_empty. The visitor confirms the
    # selection — which is the right call when each checkbox costs real money.
    price per_selection: { roof_only: 0, gutters: 1400, ventilation: 750,
                          skylights: 2200, siding: 8500 }
    transition to: :storm_damage
  end

  # ---------------------------------------------------------------------------
  # The fork: storm/insurance work is a different business from cash work.
  # ---------------------------------------------------------------------------

  confirm :storm_damage do
    question "Did a storm — wind, hail, or a fallen limb — cause this?"
    skip_if not_empty(:storm_damage)
    # Documented storm inspection: photographs, slope-by-slope test squares, and
    # a report an adjuster will actually accept.
    price flat: 300
    transition to: :filing_insurance, if_rule: any(
      equals(:storm_damage, true),
      equals(:filing_insurance, true)
    )
    transition to: :budget_band
  end

  confirm :filing_insurance do
    question "Are you filing an insurance claim for it?"
    skip_if not_empty(:filing_insurance)
    # Claim work is real labour: scope sheets, supplements, and meeting the
    # adjuster on the roof. It is also why these leads go to a senior estimator.
    price flat: 900
    transition to: :claim_status, if_rule: equals(:filing_insurance, true)
    transition to: :timeline
  end

  ask :claim_status do
    type :enum
    question "Where does the claim stand?"
    options not_filed: "Haven't filed yet",
      filed_waiting: "Filed, waiting to hear back",
      adjuster_scheduled: "Adjuster is scheduled",
      approved: "Approved",
      denied: "Denied or underpaid"
    price not_filed: 0, filed_waiting: 0, adjuster_scheduled: 0,
      approved: 0, denied: 1200
    transition to: :timeline
  end

  ask :budget_band do
    type :enum
    question "Do you have a number in mind for this?"
    options under_10k: "Under $10,000",
      ten_to_25k: "$10,000 to $25,000",
      twentyfive_to_50k: "$25,000 to $50,000",
      over_50k: "Over $50,000",
      not_sure: "No idea — that's what I'm here for"
    # No price. What you're willing to spend does not change what the roof
    # costs, and quoting back the number somebody just told you is how estimates
    # stop being estimates. It routes and it primes the follow-up call; that's all.
    transition to: :material_preference
  end

  ask :material_preference do
    type :enum
    question "Staying with what's up there, or upgrading?"
    options like_for_like: "Same as what's there now",
      upgrade_shingle: "Better shingle — architectural or impact-rated",
      standing_seam_metal: "Standing-seam metal",
      tile_or_slate: "Tile or slate",
      want_advice: "Tell me what you'd put on your own house"
    # The delta on top of the like-for-like tier priced at `material`.
    price like_for_like: 0, upgrade_shingle: 1200, standing_seam_metal: 6500,
      tile_or_slate: 9000, want_advice: 0
    transition to: :timeline
  end

  ask :timeline do
    type :enum
    question "When do you need this done?"
    options emergency: "Emergency — this week",
      weeks: "Next few weeks",
      planning: "Planning ahead, a few months out",
      researching: "Just gathering numbers for now"
    skip_if not_empty(:timeline)
    # Pulling a crew off a scheduled job costs money and everybody knows it.
    price emergency: 950, weeks: 0, planning: 0, researching: 0
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is where a real intake form would ask for your name, your email and " \
         "the address of the house so a crew chief could come out and measure.\n\n" \
         "This is a demo, so we're collecting none of it — and notice that nothing " \
         "we asked identifies you or your house. The number below came entirely " \
         "from the shape of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:project_scope, "full_exterior"),
      equals(:storm_damage, true),
      equals(:filing_insurance, true),
      equals(:roof_pitch, "steep"),
      equals(:stories, "three_plus"),
      equals(:material, "wood_shake"),
      equals(:material, "metal"),
      equals(:material, "tile_slate"),
      greater_than(:roof_area_sqft, 3000),
      contains(:additional_work, "siding")
    )
    transition to: :tier_standard, if_rule: any(
      equals(:project_scope, "full_replacement"),
      equals(:stories, "two"),
      equals(:material, "architectural"),
      equals(:timeline, "emergency"),
      greater_than(:roof_area_sqft, 1200),
      contains(:additional_work, "gutters"),
      contains(:additional_work, "skylights")
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This is a contained job — single story, walkable pitch, asphalt, a defined " \
         "area. A two-person crew, most likely one day, no dumpster on the street.\n\n" \
         "The number assumes the decking underneath is sound. If we open it up and " \
         "find rot, we stop and call you before we spend a dollar of it.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "repair schedule. You'd never see that; the contractor would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This is a standard re-roof: tear-off, deck inspection, ice-and-water at the " \
         "eaves and valleys, new underlayment, new roof. Plan on two to four days on " \
         "site and a dumpster in the driveway for most of it.\n\n" \
         "Anything hidden — rotted sheathing, a chimney flashing that was never right " \
         "— gets photographed and priced before it gets fixed.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to a " \
         "field estimator. You'd never see that; the contractor would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This one needs the senior estimator on the roof before anybody quotes it " \
         "firm. Steep or multi-story access, premium material, work beyond the roof " \
         "line, or an insurance claim — each of those changes the crew, the equipment " \
         "and the schedule, and the number above reflects that.\n\n" \
         "If there's a claim in play: don't sign anything with anyone until the scope " \
         "is documented slope by slope. An underpaid claim is far harder to reopen " \
         "than it is to get right the first time.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight to " \
         "the owner. You'd never see that; the contractor would._"
  end
end
