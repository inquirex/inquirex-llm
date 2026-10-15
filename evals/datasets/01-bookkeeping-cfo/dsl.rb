# Demo flow — Bookkeeping & Fractional CFO Services (spec 012, segment 10).
#
# Headline superpower: **messiness / volume tiering**. Effort in this trade
# scales with three things an owner can describe in plain English — how many
# transactions run through the business, how complicated the entity structure
# is, and how far behind the books have fallen — and not one of the three
# requires an account number.
#
# Two accumulators, because the money here has two different shapes:
#
#   :price   — the ONGOING MONTHLY RETAINER. Every contribution below is a
#              per-month figure, which is why the tier copy says "per month".
#   :cleanup — the ONE-TIME catch-up project, touched only on the "behind"
#              branch. Keeping it out of :price is the entire point: folding a
#              one-off cleanup into the monthly number would quote a retainer
#              nobody would pay a second time, and the lead would find out on
#              invoice two. The tier steps print it on its own line.
#
# Financially discreet by construction. Revenue is asked as a BAND and never as
# a figure; bank and card accounts are asked as a COUNT and never as a number,
# a balance, or an institution. That is the segment's argument in one form: you
# can scope this engagement to within a few hundred dollars a month without
# ever seeing inside the business's accounts.
#
# Note also what `service_needed` does *not* offer: "cleanup only". Cleanup is
# not a service level — it is the :cleanup accumulator, discovered by the fork.

Inquirex.define do
  meta title: "Bookkeeping & CFO Services",
    subtitle: "Tell us where the books are — we'll scope it from there"

  accumulator :price, type: :currency, default: 0
  accumulator :cleanup, type: :currency, default: 0

  start :situation

  ask :situation do
    type :text
    question "Describe your business's finances and where you need help. " \
             "How is the business set up (LLC, S-corp, sole prop), roughly what " \
             "revenue are you doing, and how busy are the books — transactions, " \
             "accounts, payroll? Are the books current or behind, what software " \
             "are you on, and what would you most like off your plate?"
    transition to: :understanding
  end

  extract :understanding do
    from :situation
    prompt "Extract the business's bookkeeping situation from their description. " \
           "Only fill a field when the text genuinely supports it — leave " \
           "anything the writer did not mention unset rather than guessing. " \
           "`transaction_volume` is a rough count of transactions per month and " \
           "`account_count` is how many bank and credit card accounts the " \
           "business uses; leave either unset when the writer only gestured at " \
           "size. `months_behind` applies only when the writer says the books " \
           "are behind or nonexistent. Never infer a revenue figure — " \
           "`revenue_band` is a band, and only when the writer named one."
    schema entity_type: { type: :enum,
                         values: %w[sole_prop single_member_llc multi_member_llc s_corp multi_entity] },
      industry: { type: :enum,
                 values: %w[professional_services retail_or_ecommerce construction_or_trades
                   restaurant_or_hospitality healthcare real_estate other_industry] },
      revenue_band: { type: :enum,
                     values: %w[under_25k from_25k_to_100k from_100k_to_500k over_500k] },
      transaction_volume: :integer,
      account_count: :integer,
      books_state: { type: :enum, values: %w[up_to_date behind not_started] },
      months_behind: :integer,
      filing_blocked: :boolean,
      accounting_software: { type: :enum,
                            values: %w[cloud_software desktop_software spreadsheets nothing_yet] },
      payroll: :boolean,
      service_needed: { type: :enum, values: %w[monthly_bookkeeping controller fractional_cfo] }
    text "Reading what you wrote…"
    transition to: :heard_you
  end

  say :heard_you do
    text "Here's what we picked up from what you wrote:\n\n" \
         "{% if answers.entity_type %}• Entity: **{{ answers.entity_type | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.industry %}• Industry: **{{ answers.industry | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.revenue_band %}• Monthly revenue: **{{ answers.revenue_band | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.transaction_volume %}• Transactions a month: **{{ answers.transaction_volume }}**\n{% endif %}" \
         "{% if answers.account_count %}• Bank and card accounts: **{{ answers.account_count }}**\n{% endif %}" \
         "{% if answers.books_state %}• Books: **{{ answers.books_state | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.months_behind %}• Months behind: **{{ answers.months_behind }}**\n{% endif %}" \
         "{% if answers.accounting_software %}• Kept in: **{{ answers.accounting_software | replace: '_', ' ' }}**\n{% endif %}" \
         "{% if answers.payroll %}• Runs payroll\n{% endif %}" \
         "{% if answers.service_needed == 'monthly_bookkeeping' %}• Looking for: **monthly bookkeeping**\n{% endif %}" \
         "{% if answers.service_needed == 'controller' %}• Looking for: **controller-level support**\n{% endif %}" \
         "{% if answers.service_needed == 'fractional_cfo' %}• Looking for: **fractional CFO support**\n{% endif %}" \
         "\nWe'll only ask about what's still missing."
    transition to: :entity_type
  end

  ask :entity_type do
    type :enum
    question "How is the business set up?"
    options sole_prop: "Sole proprietor",
      single_member_llc: "Single-member LLC",
      multi_member_llc: "Multi-member LLC or partnership",
      s_corp: "S-corporation",
      multi_entity: "More than one entity"
    skip_if not_empty(:entity_type)
    price sole_prop: 150, single_member_llc: 225, multi_member_llc: 400,
      s_corp: 500, multi_entity: 900
    transition to: :industry
  end

  ask :industry do
    type :enum
    question "What line of work is it?"
    options professional_services: "Professional or consulting services",
      retail_or_ecommerce: "Retail or e-commerce",
      construction_or_trades: "Construction or the trades",
      restaurant_or_hospitality: "Restaurant or hospitality",
      healthcare: "Healthcare practice",
      real_estate: "Real estate or property",
      other_industry: "Something else"
    skip_if not_empty(:industry)
    price professional_services: 0, retail_or_ecommerce: 150, construction_or_trades: 150,
      restaurant_or_hospitality: 200, healthcare: 150, real_estate: 100,
      other_industry: 50
    transition to: :revenue_band
  end

  # Revenue is a BAND, deliberately. A band is everything the estimate needs —
  # it sorts a business into a service level — and it is not a figure anyone
  # has to think twice about typing into a website they met five minutes ago.
  # The same reasoning governs :account_count below: how many accounts, never
  # which ones, never their numbers, never what is in them.
  ask :revenue_band do
    type :enum
    question "Roughly what does the business bring in each month?"
    options under_25k: "Under $25k",
      from_25k_to_100k: "$25k to $100k",
      from_100k_to_500k: "$100k to $500k",
      over_500k: "Over $500k"
    skip_if not_empty(:revenue_band)
    price under_25k: 0, from_25k_to_100k: 100, from_100k_to_500k: 300, over_500k: 600
    transition to: :transaction_volume
  end

  ask :transaction_volume do
    type :integer
    question "About how many transactions move through the business in a month " \
             "— bank lines, card charges, invoices, all of it? A rough number " \
             "is fine; nobody counts these exactly."
    default 50
    min 0
    max 5000
    step_size 10
    skip_if not_empty(:transaction_volume)
    price per_unit: 2
    transition to: :account_count
  end

  ask :account_count do
    type :integer
    question "How many bank and credit card accounts does the business use?"
    default 2
    min 0
    max 40
    skip_if not_empty(:account_count)
    price per_unit: 25
    transition to: :books_state
  end

  # The fork. Everything downstream of "behind" or "not started" is catch-up
  # scope, priced into :cleanup; "up to date" walks straight on to the ongoing
  # engagement. The messiness also moves the monthly number a little, because
  # books that arrived in bad shape tend to keep arriving in bad shape.
  ask :books_state do
    type :enum
    question "Where do the books stand right now?"
    options up_to_date: "Up to date — closed through last month",
      behind: "Behind — some months aren't done",
      not_started: "Nothing formal yet — receipts and a bank feed"
    skip_if not_empty(:books_state)
    price up_to_date: 0, behind: 150, not_started: 300
    transition to: :behind_is_normal, if_rule: any(
      equals(:books_state, "behind"),
      equals(:books_state, "not_started")
    )
    transition to: :accounting_software
  end

  btw :behind_is_normal do
    text "For what it's worth: that is the most common answer to that question, " \
         "by a wide margin. Nobody starts a business because they wanted to " \
         "reconcile a bank feed, and the months get away from everyone.\n\n" \
         "It changes the quote, not the welcome. Two more questions and we'll " \
         "scope the catch-up **separately** from the ongoing work, so you can " \
         "see exactly what is one-time and what is monthly."
    transition to: :months_behind
  end

  ask :months_behind do
    type :integer
    question "Roughly how many months of catch-up are we talking about?"
    default 3
    min 1
    max 36
    skip_if not_empty(:months_behind)
    accumulate :cleanup, per_unit: 225
    transition to: :filing_blocked
  end

  confirm :filing_blocked do
    question "Is anything waiting on these books — a tax filing, a loan " \
             "application, an investor, an audit?"
    skip_if not_empty(:filing_blocked)
    accumulate :cleanup, flat: 400
    transition to: :accounting_software
  end

  # Deliberately vendor-neutral. What moves the number is whether a ledger
  # exists and how well it is being fed, not whose logo is on it — and a demo
  # form has no business advertising anybody's product.
  ask :accounting_software do
    type :enum
    question "What are the books kept in today?"
    options cloud_software: "Cloud accounting software",
      desktop_software: "Desktop accounting software",
      spreadsheets: "Spreadsheets",
      nothing_yet: "Nothing formal yet"
    skip_if not_empty(:accounting_software)
    price cloud_software: 0, desktop_software: 75, spreadsheets: 200, nothing_yet: 275
    transition to: :payroll
  end

  confirm :payroll do
    question "Does the business run payroll?"
    skip_if not_empty(:payroll)
    price flat: 150
    transition to: :service_needed
  end

  # The service level, which is the largest single lever on the retainer:
  # bookkeeping → controller → fractional CFO.
  ask :service_needed do
    type :enum
    question "What would you want handled every month?"
    options monthly_bookkeeping: "Bookkeeping — categorize, reconcile, close the month",
      controller: "Controller — the above, plus reporting, process, and someone reviewing the work",
      fractional_cfo: "Fractional CFO — forecasting, cash planning, lender and board reporting"
    skip_if not_empty(:service_needed)
    price monthly_bookkeeping: 0, controller: 750, fractional_cfo: 1900
    transition to: :contact_placeholder
  end

  say :contact_placeholder do
    text "This is the point where a real intake form would ask for your name " \
         "and email so the firm could send a proposal.\n\n" \
         "This is a demo, so we're collecting neither — and look back at what " \
         "we did ask. Not one account number, not one balance, not one login, " \
         "not one dollar figure. The estimate below came entirely from the " \
         "shape of the work."
    transition to: :tier_complex, if_rule: any(
      equals(:entity_type, "multi_entity"),
      equals(:service_needed, "fractional_cfo"),
      equals(:revenue_band, "over_500k"),
      greater_than(:transaction_volume, 500)
    )
    transition to: :tier_standard, if_rule: any(
      equals(:service_needed, "controller"),
      equals(:books_state, "behind"),
      equals(:books_state, "not_started"),
      equals(:entity_type, "multi_member_llc"),
      equals(:entity_type, "s_corp"),
      equals(:revenue_band, "from_100k_to_500k"),
      equals(:payroll, true),
      greater_than(:transaction_volume, 150)
    )
    transition to: :tier_simple
  end

  # Group 1 carries no cleanup line by construction: any answer other than
  # "up to date" routes to Group 2 or 3, so :cleanup is always zero here.
  say :tier_simple do
    text "## Your estimate: {{ price | money_range }} per month\n\n" \
         "One entity, a manageable stack of transactions, and books that are " \
         "already current — this is the tidy version of this engagement. A " \
         "monthly close, a clean set of statements, and very little of your " \
         "attention. No catch-up work to quote.\n\n" \
         "_Behind the scenes this lead was tagged **Group 1** and routed to the " \
         "standard bookkeeping queue. You'd never see that; the firm would._"
  end

  # The catch-up line is guarded on `cleanup > 0`, not on `answers.months_behind`.
  # The extractor can set months_behind from a stray phrase while the lead then
  # answers "up to date" — in which case the behind branch never ran, nothing
  # accumulated, and the answer is a false positive. The accumulator total is
  # the only thing that knows whether cleanup was actually scoped.
  say :tier_standard do
    text "## Your estimate: {{ price | money_range }} per month\n\n" \
         "There's real volume here, or a structure with more than one moving " \
         "part, or a few months to bring forward. That's a staffed monthly " \
         "close with a second set of eyes on it, not a shoebox and a shrug.\n\n" \
         "{% if cleanup > 0 %}**One-time catch-up: {{ cleanup | money }}.** " \
         "That is separate from the monthly figure above and you pay it once, " \
         "to get the history current before the ongoing work starts.\n\n{% endif %}" \
         "_Behind the scenes this lead was tagged **Group 2** and routed to a " \
         "senior bookkeeper with controller oversight. You'd never see that; " \
         "the firm would._"
  end

  say :tier_complex do
    text "## Your estimate: {{ price | money_range }} per month\n\n" \
         "This one wants a finance function, not a bookkeeper. Multiple " \
         "entities, high transaction volume, or forecasting and reporting that " \
         "somebody outside the business is going to read — each of those adds " \
         "review time, and the range reflects it.\n\n" \
         "{% if cleanup > 0 %}**One-time catch-up: {{ cleanup | money }}.** " \
         "That is separate from the monthly figure above and you pay it once, " \
         "to get the history current before the ongoing work starts.\n\n{% endif %}" \
         "_Behind the scenes this lead was tagged **Group 3** and routed " \
         "straight to a fractional CFO. You'd never see that; the firm would._"
  end
end
