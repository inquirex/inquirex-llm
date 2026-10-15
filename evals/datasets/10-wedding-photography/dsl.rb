# Demo flow — Wedding & Event Photography / Videography (spec 012, segment 9).
#
# The headline here is **coverage-based packaging**: the number that comes out
# the far end is built almost entirely from `price per_unit:` (hours of
# coverage, locations, guests) and `price per_selection:` (the add-on menu).
# Nothing else in the ten demos leans on those two shapes as hard.
#
#   Extract  — the opener is a free-text daydream about the day; the LLM fills
#              in whatever the writer already told us, and every question it
#              answered is skipped by `skip_if not_empty(...)`.
#   Estimate — `accumulator :price` accretes hours × rate, per-location travel
#              time, format tier and the add-on menu into one package number.
#   Tier     — G1/G2/G3 falls out of ordinary rules. No lambdas: `compute` is
#              not allowlisted, and correctly so.
#
# Two deliberate limitations worth knowing about before you "fix" them:
#
#   * **No date is asked for.** A venue plus an exact date is enough to name a
#     specific couple in most towns, so this form asks for a *season* instead.
#     It prices just as well — peak season is what moves the number, not the
#     Saturday — and it keeps the demo honestly PII-free.
#   * **Peak season is a surcharge, not a multiplier.** Accumulators only add;
#     multiplying the running total would need arithmetic over `price`, which
#     means a Ruby block, which means `compute`. So the peak-season premium is
#     expressed as a season-tier addition and the copy never promises a
#     percentage.

Inquirex.define do
  meta title: "Wedding & Event Coverage",
    subtitle: "Tell us about the day — we'll shape the coverage around it"

  accumulator :price, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "Tell us about your event and the kind of coverage you're picturing. " \
             "What are we celebrating and in what season, roughly how many guests, " \
             "and how many hours of coverage? Mention whether you want photo, " \
             "video, or both, how many locations the day spans, and whether " \
             "travel is involved."
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the event and the coverage the writer is imagining. Only fill " \
           "a field when the text genuinely supports it — leave anything the " \
           "writer did not mention unset rather than guessing. `guest_count`, " \
           "`coverage_hours` and `locations` are counts; take an approximate " \
           "number when one is given and leave them unset when the writer only " \
           "gestures at size. Map an exact date to the season it falls in, and " \
           "never invent one. `formats` is `photo` unless video, film or a " \
           "highlight reel is mentioned."
    schema event_type: { type: :enum,
                        values: %w[wedding elopement engagement_session celebration corporate] },
      season: { type: :enum, values: %w[spring summer autumn winter still_deciding] },
      guest_count: :integer,
      coverage_hours: :integer,
      formats: { type: :enum, values: %w[photo video both] },
      locations: :integer,
      full_day_arc: :boolean,
      travel_required: :boolean,
      add_ons: { type: :multi_enum,
                values: %w[drone album engagement_session second_shooter same_day_edit] }
    text "Picturing it…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Lovely. Here's what we picked up from what you wrote:\n\n" \
         "{% if answers.event_type %}• Event: **{{ answers.event_type | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.season %}• Season: **{{ answers.season | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.guest_count %}• Guests: **about {{ answers.guest_count }}**\n{% endif %}" \
         "{% if answers.coverage_hours %}• Coverage: **{{ answers.coverage_hours }} hours**\n{% endif %}" \
         "{% if answers.formats %}• Format: **{{ answers.formats | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.locations %}• Locations: **{{ answers.locations }}**\n{% endif %}" \
         "{% if answers.full_day_arc %}• Getting ready through the reception\n{% endif %}" \
         "{% if answers.travel_required %}• Travel involved\n{% endif %}" \
         "\nWe'll only ask about what's still missing."
    transition to: :event_type
  end

  ask :event_type do
    type :enum
    question "What are we celebrating?"
    options wedding: "A wedding",
      elopement: "An elopement or small ceremony",
      engagement_session: "An engagement or proposal shoot",
      celebration: "A milestone celebration — anniversary, birthday, family gathering",
      corporate: "A corporate or brand event"
    skip_if not_empty(:event_type)
    price wedding: 900, elopement: 400, engagement_session: 300, celebration: 500, corporate: 700
    transition to: :season
  end

  # Season, not a date. See the header comment — a venue plus a date names a
  # couple, and the season is what actually moves the price anyway.
  ask :season do
    type :enum
    question "Roughly when? A season is plenty — we don't need the date yet."
    options spring: "Spring",
      summer: "Summer",
      autumn: "Autumn",
      winter: "Winter",
      still_deciding: "Still deciding"
    skip_if not_empty(:season)
    price spring: 500, summer: 750, autumn: 400, winter: 0, still_deciding: 0
    transition to: :guest_count
  end

  ask :guest_count do
    type :integer
    question "About how many guests are you expecting?"
    default 100
    min 0
    max 600
    skip_if not_empty(:guest_count)
    price per_unit: 2
    transition to: :coverage_hours
  end

  # The headline unit. Everything else adjusts around this number.
  ask :coverage_hours do
    type :integer
    question "How many hours of coverage are you picturing?"
    default 8
    min 1
    max 16
    skip_if not_empty(:coverage_hours)
    price per_unit: 425
    transition to: :formats
  end

  # The fork. Photo goes to prints, video goes to the edit, both goes to both.
  ask :formats do
    type :enum
    question "Photo, video, or both?"
    options photo: "Photography",
      video: "Videography",
      both: "Both — stills and film"
    skip_if not_empty(:formats)
    price photo: 0, video: 600, both: 1500
    transition to: :highlight_length, if_rule: any(
      equals(:formats, "video"),
      equals(:formats, "both")
    )
    transition to: :print_package
  end

  ask :highlight_length do
    type :enum
    question "How long should the finished film be?"
    options teaser: "A 60-second teaser for sharing",
      highlight: "A 4–6 minute highlight reel",
      feature: "A 15-minute feature edit",
      documentary: "Full documentary edit — ceremony and speeches in full"
    price teaser: 400, highlight: 1100, feature: 2200, documentary: 3200
    transition to: :print_package, if_rule: equals(:formats, "both")
    transition to: :locations
  end

  ask :print_package do
    type :enum
    question "And how would you like the photographs to arrive?"
    options digital_only: "A digital gallery is perfect",
      print_credit: "Gallery plus a print credit",
      fine_art: "Gallery plus fine-art prints",
      heirloom: "The full heirloom box — mounted prints, hand-wrapped"
    price digital_only: 0, print_credit: 300, fine_art: 750, heirloom: 1500
    transition to: :locations
  end

  ask :locations do
    type :integer
    question "How many places will we be shooting — venue, getting-ready suite, " \
             "a spot for portraits?"
    default 1
    min 1
    max 8
    skip_if not_empty(:locations)
    price per_unit: 250
    transition to: :full_day_arc
  end

  confirm :full_day_arc do
    question "Would you like us there for the whole arc — getting ready through " \
             "the last dance?"
    skip_if not_empty(:full_day_arc)
    price flat: 400
    transition to: :travel_required
  end

  confirm :travel_required do
    question "Will the day take us somewhere that needs travel — a destination, " \
             "or more than a few hours from home?"
    skip_if not_empty(:travel_required)
    price flat: 1800
    transition to: :add_ons
  end

  # The other half of coverage-based packaging: a menu where every tick has its
  # own number. Note the asymmetry with the single-value questions above —
  # `Engine#prefill!` files an extracted multi_enum as a *suggestion*, not an
  # answer, so this step is always shown, with the extractor's picks pre-ticked,
  # and it contributes nothing to `price` until the guest confirms them. That is
  # the right behaviour for a menu you are about to be charged for. The
  # `skip_if` is here for symmetry, and for a host that writes answers directly.
  ask :add_ons do
    type :multi_enum
    question "Anything you'd like to add?"
    options drone: "Aerial and drone coverage",
      album: "A designed album",
      engagement_session: "An engagement session beforehand",
      second_shooter: "A second shooter",
      same_day_edit: "A same-day edit to play at the reception"
    skip_if not_empty(:add_ons)
    price per_selection: { drone: 450,
                          album: 850,
                          engagement_session: 600,
                          second_shooter: 900,
                          same_day_edit: 1200 }
    transition to: :budget_band
  end

  # Costs nothing and prices nothing — it exists so the artist knows how to
  # open the conversation, not so the form can push.
  ask :budget_band do
    type :enum
    question "Last one, and it's genuinely optional: where are you hoping to land?"
    options under_3k: "Under $3,000",
      three_to_7k: "$3,000 – $7,000",
      seven_to_15k: "$7,000 – $15,000",
      over_15k: "Above $15,000",
      rather_not_say: "I'd rather not say yet"
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real intake form would ask for your name and " \
         "email so the studio could send a full proposal.\n\n" \
         "This is a demo, so we're not collecting either — and notice that nothing " \
         "we asked identifies you, or the day. No names, no venue, not even a " \
         "date. The estimate below came entirely from the shape of the coverage."
    transition to: :tier_complex, if_rule: any(
      equals(:travel_required, true),
      greater_than(:locations, 2),
      greater_than(:guest_count, 200),
      greater_than(:coverage_hours, 10),
      equals(:highlight_length, "feature"),
      equals(:highlight_length, "documentary")
    )
    transition to: :tier_standard, if_rule: any(
      equals(:formats, "both"),
      equals(:formats, "video"),
      equals(:full_day_arc, true),
      greater_than(:coverage_hours, 6),
      greater_than(:guest_count, 75)
    )
    transition to: :tier_simple
  end

  say :tier_simple do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "A short, single-location shoot with one photographer — the kind of day " \
         "that runs beautifully on its own. One of our associate artists would " \
         "cover it, and your gallery would be with you inside two weeks.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "associate roster. You'd never see that; the studio would._"
  end

  say :tier_standard do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "This is a full day, and it deserves to be photographed like one — a " \
         "lead artist with a second pair of hands, the whole arc from the quiet " \
         "morning to the loud end of the night.\n\n" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to a " \
         "lead artist. You'd never see that; the studio would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }}\n\n" \
         "Multiple locations, a long day, travel, or a proper film — this is a " \
         "production, and it wants a crew. A lead artist, a cinema team, and " \
         "someone whose entire job is making sure none of it touches you.\n\n" \
         "We'd want a real conversation before quoting the day properly. That's " \
         "not a hedge; it's how the good ones get made.\n\n" \
         "_Behind the scenes this lead was tagged **Group 3** and routed straight " \
         "to the studio principal. You'd never see that; the studio would._"
  end
end
