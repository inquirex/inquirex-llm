# frozen_string_literal: true

# Example 8: Tax Preparer Intake (Realistic, Privacy-Safe)
#
# Real-world intake wizard used by tax preparers to estimate how long a
# return will take and how much phone time the client will consume. Every
# question is scoped so the answer changes the fee quote.
#
# Privacy rule: this form lives on an unsecured embeddable widget, so we
# collect NO PII — no names, no SSN / ITIN, no date of birth, no addresses,
# no account numbers. The only contact field is an email so we can send
# the quote back. Everything else is bucketed multiple choice.
#
# The flow branches on:
#
#   * residency status (non-resident / dual-status multiplies the fee),
#   * business ownership (entity mix, employee / contractor bands, and
#     which books — P&L, Balance Sheet, GL, Trial Balance — are ready),
#   * investment, crypto, rental, and foreign-earned income blocks,
#   * the "surprise pile" (IRS letters, state notices) that blows up
#     timelines if not flagged early.
#
# Bucketed `enum` and `multi_enum` options are used everywhere so a
# downstream pricing pass can `accumulate` fees per selected option.
#
# Run (from inquirex-tty): bundle exec exe/inquirex run ../inquirex-llm/examples/tax-preparation-estimator.rb

US_STATES = %w[
  AL AK AZ AR CA CO CT DE FL GA
  HI ID IL IN IA KS KY LA ME MD
  MA MI MN MS MO MT NE NV NH NJ
  NM NY NC ND OH OK OR PA RI SC
  SD TN TX UT VT VA WA WV WI WY
  DC
].freeze

Inquirex.define id: "tax-preparer-2025", version: "2.0.0" do
  meta title: "Tax Preparation Intake",
    subtitle: "Help us scope your return and quote you a fair fee"

  start :intro

  # -----------------------------------------------------------------------
  # Opening
  # -----------------------------------------------------------------------

  say :intro do
    text "Short multiple-choice scoping questions — 2 to 3 minutes.\n" \
         "Please do NOT enter any personal information: no names,\n" \
         "SSN, ITIN, addresses, or account numbers. We only need\n" \
         "enough to quote a fee."
    transition to: :describe
  end

  # -----------------------------------------------------------------------
  # Opening
  # -----------------------------------------------------------------------

  ask :describe do
    type :text
    question "Describe your last year's tax situation, your residency/citizenship status, your filing status, any dependents, various income types, which state(s) you are filing in,and whether you have your prior year returns available. If you also participate in businesses, please describe their tax status (S-Corp, LLC, etc), and if you have any foreign investments or property."
    transition to: :summary
  end

  extract :summary do
    from :describe

    # :auto generates the prompt from the referenced questions' own wording.
    # Hand-write a prompt string instead when you need domain framing the
    # questions don't carry.
    prompt :auto

    # Each symbol references a question defined further down in this flow.
    # The gem resolves the question's type and — for enum / multi_enum
    # questions — folds its allowed option values into the JSON schema sent
    # to the LLM, so extracted values always match the downstream options.
    schema :filing_status,
      :dependents,
      :income_types,
      :state_filing,
      :residency_status,
      :prior_return_available,
      :business_entities

    model :claude_sonnet
    transition to: :residency_status
  end

  # -----------------------------------------------------------------------
  # Scope-driving baseline (residency + prior return)
  # -----------------------------------------------------------------------

  ask :residency_status do
    type :enum
    question "Which best describes your US tax residency for 2025?"
    options({
      "us_person"    => "US citizen or permanent resident",
      "resident"     => "Resident alien (substantial presence)",
      "non_resident" => "Non-resident alien (1040-NR)",
      "dual_status"  => "Dual-status (arrived or departed this year)"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 2
    widget target: :mobile,  type: :dropdown
    transition to: :prior_return_available
  end

  ask :prior_return_available do
    type :enum
    question "Do you have a copy of your most recent tax return?"
    options({
      "yes_last_year" => "Yes, last year's return",
      "yes_older"     => "Yes, but older than last year",
      "no"            => "No",
      "first_time"    => "First return — never filed before"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 2
    transition to: :filing_status
  end

  ask :filing_status do
    type :enum
    question "What is your filing status for 2025?"
    options({
      "single"                    => "Single",
      "married_filing_jointly"    => "Married Filing Jointly",
      "married_filing_separately" => "Married Filing Separately",
      "head_of_household"         => "Head of Household",
      "widowed"                   => "Qualifying Widow(er)"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 1
    widget target: :mobile,  type: :dropdown
    transition to: :dependents
  end

  ask :dependents do
    type :enum
    question "How many dependents will you claim?"
    options %w[0 1 2 3 4+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    widget target: :mobile,  type: :dropdown
    transition to: :income_types
  end

  # -----------------------------------------------------------------------
  # Income sources
  # -----------------------------------------------------------------------

  ask :income_types do
    type :multi_enum
    question "Select every type of income you had in 2025."
    options({
      "W2"          => "W-2 wages",
      "1099_nec"    => "1099-NEC (contractor)",
      "1099_k"      => "1099-K (payment apps, marketplaces)",
      "business"    => "Business income (self-employed or entity)",
      "investment"  => "Investment income (brokerage, dividends)",
      "crypto"      => "Cryptocurrency",
      "rental"      => "Rental property",
      "retirement"  => "Retirement distributions (1099-R)",
      "social_sec"  => "Social Security",
      "gambling"    => "Gambling / lottery winnings",
      "foreign"     => "Foreign earned income",
      "home_sale"   => "Sold a home or primary residence",
      "inheritance" => "Inheritance or large gift received",
      "none"        => "None of the above"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :w2_count,           if_rule: contains(:income_types, "W2")
    transition to: :business_entities,  if_rule: contains(:income_types, "business")
    transition to: :investment_details, if_rule: contains(:income_types, "investment")
    transition to: :crypto_volume,      if_rule: contains(:income_types, "crypto")
    transition to: :rental_count,       if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned,     if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  ask :w2_count do
    type :enum
    question "How many W-2s will you report?"
    options %w[1 2 3 4 5+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    transition to: :business_entities,  if_rule: contains(:income_types, "business")
    transition to: :investment_details, if_rule: contains(:income_types, "investment")
    transition to: :crypto_volume,      if_rule: contains(:income_types, "crypto")
    transition to: :rental_count,       if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned,     if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  # -----------------------------------------------------------------------
  # Business block
  # -----------------------------------------------------------------------

  ask :business_entities do
    type :multi_enum
    question "Which business entity types do you own or partner in?"
    options({
      "sole_prop"   => "Sole Proprietor / Schedule C",
      "single_llc"  => "Single-member LLC",
      "multi_llc"   => "Multi-member LLC / Partnership",
      "s_corp"      => "S-Corporation",
      "c_corp"      => "C-Corporation",
      "partnership" => "Partnership (non-LLC)",
      "trust"       => "Trust / Estate",
      "nonprofit"   => "Nonprofit / 501(c)"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :business_count_band
  end

  ask :business_count_band do
    type :enum
    question "Across all entities, how many separate business returns?"
    options %w[1 2-3 4-5 6+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 4
    transition to: :books_ready
  end

  ask :books_ready do
    type :multi_enum
    question "Which of these are already prepared for the full year?"
    options({
      "pnl"       => "Profit & Loss (Income Statement)",
      "balance"   => "Balance Sheet (beginning and end of year)",
      "gl"        => "General Ledger",
      "trial"     => "Trial Balance",
      "bank_recs" => "Bank reconciliations",
      "none"      => "None / unsure"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :employee_band
  end

  ask :employee_band do
    type :enum
    question "How many W-2 employees across all businesses?"
    options({
      "0"        => "None",
      "1-10"     => "1-10",
      "10-50"    => "10-50",
      "50-500"   => "50-500",
      "500-1000" => "500-1,000",
      "1000+"    => "1,000 or more"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 3
    widget target: :mobile,  type: :dropdown
    transition to: :contractor_band
  end

  ask :contractor_band do
    type :enum
    question "How many 1099 contractors paid over $600 in 2025?"
    options %w[0 1-5 6-20 21-50 50+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    transition to: :ppp_eidl
  end

  ask :ppp_eidl do
    type :multi_enum
    question "Any pandemic-era loans or credits still open?"
    options({
      "ppp_forgiven" => "PPP (forgiven)",
      "ppp_pending"  => "PPP (forgiveness pending)",
      "eidl"         => "EIDL loan still outstanding",
      "erc"          => "Employee Retention Credit claimed",
      "none"         => "None"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :fringe_benefits
  end

  ask :fringe_benefits do
    type :multi_enum
    question "Fringe benefits or business deductions to account for?"
    options({
      "company_car" => "Company vehicle / personal use",
      "reimburse"   => "Accountable-plan reimbursements",
      "home_office" => "Home office",
      "meals"       => "Business meals / travel",
      "education"   => "Education / tuition assistance",
      "none"        => "None"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :business_retirement
  end

  ask :business_retirement do
    type :multi_enum
    question "Business-side retirement plans in 2025?"
    options({
      "solo_401k"  => "Solo 401(k)",
      "sep_ira"    => "SEP-IRA",
      "simple_ira" => "SIMPLE IRA",
      "401k"       => "Traditional 401(k) plan",
      "defined"    => "Defined benefit / cash balance plan",
      "none"       => "None"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :investment_details, if_rule: contains(:income_types, "investment")
    transition to: :crypto_volume,      if_rule: contains(:income_types, "crypto")
    transition to: :rental_count,       if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned,     if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  # -----------------------------------------------------------------------
  # Investment block
  # -----------------------------------------------------------------------

  ask :investment_details do
    type :multi_enum
    question "What types of investments did you hold?"
    options({
      "brokerage"   => "Taxable brokerage (stocks, ETFs)",
      "options"     => "Options / derivatives",
      "private"     => "Private equity / angel / K-1s",
      "real_estate" => "REITs",
      "hsa"         => "HSA",
      "529"         => "529 plan"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :brokerage_count, if_rule: contains(:investment_details, "brokerage")
    transition to: :k1_count,        if_rule: contains(:investment_details, "private")
    transition to: :crypto_volume,   if_rule: contains(:income_types, "crypto")
    transition to: :rental_count,    if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned,  if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  ask :brokerage_count do
    type :enum
    question "How many brokerage 1099-B statements will you receive?"
    options %w[1 2 3 4-5 6+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    transition to: :k1_count,       if_rule: contains(:investment_details, "private")
    transition to: :crypto_volume,  if_rule: contains(:income_types, "crypto")
    transition to: :rental_count,   if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned, if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  ask :k1_count do
    type :enum
    question "How many K-1s will you receive?"
    options %w[1 2-3 4-6 7-10 10+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    transition to: :crypto_volume,  if_rule: contains(:income_types, "crypto")
    transition to: :rental_count,   if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned, if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  # -----------------------------------------------------------------------
  # Crypto block
  # -----------------------------------------------------------------------

  ask :crypto_volume do
    type :enum
    question "Roughly how many crypto transactions in 2025?"
    options({
      "0-10"       => "Fewer than 10",
      "10-100"     => "10-100",
      "100-1000"   => "100-1,000",
      "1000-10000" => "1,000-10,000",
      "10000+"     => "More than 10,000"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    transition to: :crypto_activity
  end

  ask :crypto_activity do
    type :multi_enum
    question "Which crypto activities apply?"
    options({
      "trading"  => "Buying / selling",
      "staking"  => "Staking rewards",
      "mining"   => "Mining",
      "nfts"     => "NFTs",
      "defi"     => "DeFi (lending, LP, yield)",
      "airdrops" => "Airdrops / forks",
      "payments" => "Received crypto as payment"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :crypto_report_ready
  end

  ask :crypto_report_ready do
    type :boolean
    question "Do you already have a CoinTracker / Koinly / TokenTax " \
             "tax report covering 2025?"
    widget target: :tty,     type: :yes_no
    widget target: :desktop, type: :yes_no_buttons
    transition to: :rental_count,   if_rule: contains(:income_types, "rental")
    transition to: :foreign_earned, if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  # -----------------------------------------------------------------------
  # Rental block
  # -----------------------------------------------------------------------

  ask :rental_count do
    type :enum
    question "How many rental properties do you own?"
    options %w[1 2-3 4-6 7-10 10+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 5
    transition to: :rental_types
  end

  ask :rental_types do
    type :multi_enum
    question "What types of rental properties?"
    options({
      "residential_long" => "Residential long-term",
      "short_term"       => "Short-term (Airbnb / VRBO)",
      "commercial"       => "Commercial",
      "vacation"         => "Vacation / mixed personal use",
      "foreign_rental"   => "Foreign rental"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :foreign_earned, if_rule: contains(:income_types, "foreign")
    transition to: :state_filing
  end

  # -----------------------------------------------------------------------
  # Foreign earned income block
  # -----------------------------------------------------------------------

  ask :foreign_earned do
    type :multi_enum
    question "What foreign income situation applies?"
    options({
      "worked_abroad"    => "Worked abroad during 2025",
      "foreign_employer" => "Paid by a foreign employer",
      "foreign_self"     => "Self-employed abroad",
      "us_expat"         => "US citizen living abroad",
      "treaty"           => "Tax treaty benefits expected"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :state_filing
  end

  # -----------------------------------------------------------------------
  # State filing (all 50 + DC, rendered as a grid)
  # -----------------------------------------------------------------------

  ask :state_filing do
    type :multi_enum
    question "Select every state (and DC) you need to file a return in."
    options US_STATES
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 10, layout: :grid
    widget target: :mobile,  type: :multi_select_dropdown
    transition to: :state_residency
  end

  ask :state_residency do
    type :enum
    question "Were you a resident of more than one state during 2025?"
    options({
      "no"           => "No, one state all year",
      "part_year"    => "Yes, part-year resident",
      "multi"        => "Yes, multiple states",
      "non_resident" => "No, but earned income in another state"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 2
    transition to: :foreign_accounts
  end

  # -----------------------------------------------------------------------
  # Foreign accounts (FBAR / Form 8938 scope trigger)
  # -----------------------------------------------------------------------

  ask :foreign_accounts do
    type :enum
    question "Did you hold foreign financial accounts in 2025?"
    options({
      "no"       => "No",
      "under10k" => "Yes, aggregate always under $10,000",
      "over10k"  => "Yes, aggregate exceeded $10,000",
      "unsure"   => "Not sure"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 2
    transition to: :foreign_account_count, if_rule: equals(:foreign_accounts, "over10k")
    transition to: :foreign_account_count, if_rule: equals(:foreign_accounts, "unsure")
    transition to: :surprise_heads_up
  end

  ask :foreign_account_count do
    type :enum
    question "How many foreign accounts?"
    options %w[1 2-3 4-10 10+]
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 4
    transition to: :surprise_heads_up
  end

  # -----------------------------------------------------------------------
  # "Surprise pile" — late-arriving items that blow up timelines
  # -----------------------------------------------------------------------

  warning :surprise_heads_up do
    text "Last stretch: items that commonly arrive late and add billable\n" \
         "hours. Flagging them now keeps our quote accurate."
    transition to: :tax_notices
  end

  ask :tax_notices do
    type :multi_enum
    question "Any outstanding tax notices we should know about?"
    options({
      "irs_cp2000"    => "IRS CP2000 (underreported income)",
      "irs_balance"   => "IRS balance-due notice",
      "irs_audit"     => "IRS audit or examination",
      "irs_identity"  => "IRS identity verification",
      "irs_lien_levy" => "IRS lien or levy",
      "state_notice"  => "State or local tax notice",
      "none"          => "None"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :estimated_payments
  end

  ask :estimated_payments do
    type :enum
    question "Did you make 2025 federal estimated tax payments?"
    options({
      "all_four" => "Yes, all four quarters",
      "some"     => "Yes, some quarters",
      "none"     => "No",
      "refund"   => "No — applied prior-year refund instead",
      "unsure"   => "Not sure"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 2
    transition to: :deduction_types
  end

  # -----------------------------------------------------------------------
  # Deductions & credits
  # -----------------------------------------------------------------------

  ask :deduction_types do
    type :multi_enum
    question "Which deductions or credits apply?"
    options({
      "mortgage"   => "Mortgage interest",
      "salt"       => "State & local taxes (SALT)",
      "medical"    => "Major medical expenses",
      "charitable" => "Charitable contributions",
      "education"  => "Education credits / student loan interest",
      "energy"     => "Energy / EV credits",
      "childcare"  => "Childcare expenses",
      "hsa_fsa"    => "HSA / FSA contributions",
      "none"       => "None / standard deduction"
    })
    widget target: :tty,     type: :multi_select
    widget target: :desktop, type: :checkbox_group, columns: 2
    transition to: :charitable_band, if_rule: contains(:deduction_types, "charitable")
    transition to: :timeline
  end

  ask :charitable_band do
    type :enum
    question "Roughly how much in charitable contributions?"
    options({
      "under1k"  => "Under $1,000",
      "1k-5k"    => "$1,000 - $5,000",
      "5k-25k"   => "$5,000 - $25,000",
      "25k-100k" => "$25,000 - $100,000",
      "over100k" => "Over $100,000",
      "non_cash" => "Includes non-cash donations"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 3
    transition to: :timeline
  end

  # -----------------------------------------------------------------------
  # Timing (affects rush pricing)
  # -----------------------------------------------------------------------

  ask :timeline do
    type :enum
    question "How soon do you need this return filed?"
    options({
      "asap"        => "As soon as possible",
      "by_april"    => "By the April deadline",
      "extension"   => "Happy to file an extension",
      "already_ext" => "Already on extension"
    })
    widget target: :tty,     type: :select
    widget target: :desktop, type: :radio_group, columns: 2
    transition to: :client_email
  end

  # -----------------------------------------------------------------------
  # Single contact field — email only, so we can send the quote back.
  # No names, no phone numbers, no addresses.
  # -----------------------------------------------------------------------

  ask :client_email do
    type :email
    question "Email address to send your fee quote to:"
    widget target: :tty, type: :text_input
    transition to: :thanks
  end

  say :thanks do
    text "Thanks! We'll email your fee quote and a document checklist\n" \
         "within one business day. No personal information was stored."
  end
end
