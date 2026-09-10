# Decision log

Every non-obvious choice in this project, with the reasoning that produced it.
Newest at the bottom. Each entry stands on its own so it can be read cold.

Status values: `accepted`, `superseded by NNN`, `revisited`.

---

## 001 — Warehouse: DuckDB, not Snowflake or BigQuery

**Date:** 2026-09-08
**Status:** accepted

**Context.** No Snowflake access. A Snowflake trial expires in 30 days, which is
shorter than this project. BigQuery's sandbox is free and permanent but adds
network latency and a credentials step to every local iteration.

**Decision.** dbt-core with the DuckDB adapter, running against a local file.

**Consequences.** Every dbt concept exercised here — `ref`, sources, tests,
macros, incremental models, snapshots, docs — is adapter-agnostic, so nothing
learned is DuckDB-specific. The tradeoff is that no cloud warehouse name appears
on the project. Revisit if a target role explicitly requires Snowflake or
BigQuery on the résumé rather than in the work.

---

## 002 — Data source: TCGCSV, not the TCGplayer API

**Date:** 2026-09-08
**Status:** accepted

**Context.** TCGplayer's official API is the obvious first choice, but its
documentation states it is no longer granting new API access, with no published
waitlist or timeline. Access has stayed restricted to existing key holders and
approved partners since the eBay acquisition.

**Decision.** Use TCGCSV, a public daily mirror of TCGplayer's categories,
groups, products and prices. Filter to categoryId 3 (Pokemon).

**Consequences.**
- TCGCSV publishes daily price archives back to 2024-02-08, so the project starts
  with real history instead of accumulating it. This is the difference between a
  price analysis and a two-day line chart.
- TCGCSV exposes products, not SKUs, so condition-level pricing (Near Mint through
  Damaged) is not available. All analysis is at the printing level.
- The mirror is a volunteer project. It is a single point of failure and its
  schema is not contractually stable. Source freshness checks exist partly to
  detect it going dark.
- Direct scraping of tcgplayer.com was considered and rejected: their terms
  discourage it, and the mirror already provides the same data.

---

## 003 — Card attributes come from pokemontcg.io, refreshed separately

**Date:** 2026-09-08
**Status:** accepted

**Context.** TCGplayer's extendedData carries rarity, card number, HP, stage and
card text, but not artist, release date, subtypes or format legality — several of
which are the more interesting explanatory variables for price.

**Decision.** Enrich from pokemontcg.io, pulled on its own monthly cadence rather
than inside the daily price loop. Free tier is 1,000 requests/day unauthenticated,
20,000/day with a free key.

**Consequences.** Adds a fuzzy join between two catalogs that do not share an
identifier (see 005). Card attributes change far more slowly than prices, so
coupling them to the daily run would waste requests and add a failure mode to the
critical path.

---

## 004 — Fact grain is (product_id, printing_type, price_date)

**Date:** 2026-09-08
**Status:** accepted

**Context.** TCGplayer prices are not per card. Each price record carries a
`subTypeName` — Normal, Holofoil, Reverse Holofoil, 1st Edition Holofoil — with
its own low/mid/high/market points. One Charizard product can have three
independent price series that diverge substantially.

**Decision.** The fact grain is one row per product per printing per day. The
dimension grain is one row per product per printing. A surrogate key
`card_printing_key` over (product_id, printing_type) is the join key throughout.

**Consequences.** This is the load-bearing decision in the project. Aggregating to
the product level without accounting for printing would let reverse holos drag
down every rarity-level average, silently. Enforced by a
`unique_combination_of_columns` test at staging and again at the mart.

---

## 005 — Catalog join failures are reported, not hidden

**Date:** 2026-09-08
**Status:** accepted

**Context.** TCGCSV products and pokemontcg.io cards share no identifier. The join
has to be made on set plus collector number, and it will not fully succeed —
promos, special subsets and reprint variants are the expected failure classes.

**Decision.** Build a reconciliation model that reports unmatched rate by set, and
a test that fails when the unmatched rate crosses a threshold. Do not silently
inner-join the failures away.

**Consequences.** Unmatched cards keep their TCGplayer attributes and carry null
enrichment, so they remain in price analysis but drop out of any cut that depends
on an enriched field. The threshold is a judgement call and should be set from the
first real measurement, not guessed in advance.

---

## 006 — Extraction is outside dbt and idempotent

**Date:** 2026-09-08
**Status:** accepted

**Context.** dbt transforms; it does not extract. Mixing an API client into the
transformation layer makes both harder to test and reason about.

**Decision.** `extract/fetch_tcgcsv.py` writes parquet to a hive-partitioned
landing zone. dbt reads that directory as an external source via DuckDB's
`read_parquet`. The script skips partitions that already exist, so re-running it
is safe and a failed backfill can be resumed.

**Consequences.** The landing zone is gitignored and reproducible from the script,
so the repo stays small. `price_date` is carried by the partition path rather than
the payload, because TCGCSV price records contain no date field of their own.

**Materialization change, 2026-09-10.** Staging models moved from `view` to
`table`, and `fct_card_price_daily` from `table` to `incremental`.

*Why.* At ~35M rows, staging views re-scanned every parquet partition on each
downstream query. A full `dbt build` took 3m51s and every ad-hoc query paid the
same scan cost. Materializing staging brought the build to seconds. This is the
trigger condition recorded above — build time became annoying, not a date on a
calendar.

*What it cost.* Two things, both worth stating plainly.

The relative-path fragility above disappeared, which was the intended side
benefit: a table holds real data, so nothing resolves `../landing` at query time.

But it introduced a staleness failure mode that views did not have. A staging
table holds a snapshot from its last build and does not see new parquet until it
rebuilds. Running `dbt build --select fct_card_price_daily` after landing a new
day now silently does nothing — the fact reads stale staging, finds no dates past
its current maximum, and inserts zero rows. There is no error. It looks exactly
like "no new data."

*Operational consequence.* The daily run must be a full `dbt build` with no
selector, or `--select stg_tcgcsv_prices+` at minimum. Recorded in the RUNBOOK.
Narrower selectors are for iterating on a model whose upstream is known current.

*Incremental configuration.* `unique_key=['card_printing_key', 'price_date']`
with `incremental_strategy='delete+insert'`, filtered on
`price_date > (select max(price_date) from {{ this }})`. Verified three ways:
`--full-refresh` and incremental runs produce identical row counts (37,143,284);
a re-run with no new data inserts nothing; landing 2026-09-08 added 43,030 rows
and advanced the maximum date. The `delete+insert` strategy makes re-running a
date idempotent rather than duplicating it.

The model was deliberately left as a table until the backfill completed. An
incremental model filtering on `max(price_date)` would have permanently skipped
every date landing behind the running maximum.

## 007 — Sealed product is flagged at the intermediate layer, filtered at the mart

**Date:** 2026-09-09
**Status:** accepted

**Context.** TCGplayer's product catalog contains booster boxes, elite trainer
boxes and tins alongside single cards. These have prices and would otherwise be
averaged in with card prices. The obvious move is to filter them out early.

**Decision.** `int_card_printings` and `int_price_snapshots` keep sealed product
and carry an `is_sealed_product` flag. `dim_card_printing` applies the filter.

**Consequences.** Intermediate models should not discard rows a mart might
legitimately want. Sealed product prices are a valid series in their own right,
and sealed-versus-single is an interesting comparison. If that analysis is added
later it needs a new mart, not a re-plumbing of the intermediate layer. The
identification rule is a heuristic: a product with no card number and no rarity
is treated as sealed. It has not been validated against a known list.

---

## 008 — market_price and mid_price are not coalesced

**Date:** 2026-09-09
**Status:** accepted

**Context.** `market_price` is null for products with no recent sales, which is
common on illiquid cards. The convenient fix is to fall back to `mid_price` so
every row has a price.

**Decision.** Keep them as separate columns. Analysis uses `market_price`. A
`has_market_price` boolean makes the coverage gap explicit.

**Consequences.** `market_price` is derived from completed sales; `mid_price` is
the midpoint of open listings. They measure different things. Coalescing would
produce a column whose meaning silently changes with a card's liquidity — sales
based for liquid cards, listing based for illiquid ones — and any comparison
across those two populations would be invalid without the reader knowing.

Coverage was measured after the fact and is high: 97% for base, 99.2% rare,
99.3% ultra, 99% chase, 95.4% promo. The 69.8% figure for the excluded tier
confirms that code cards genuinely do not trade. Because coverage is high and
roughly even across tiers, cross-tier comparisons do not carry a selection
effect. This was worth verifying rather than assuming.

---

## 009 — Cohort eligibility is about whether a release event happened, not whether a date exists

**Date:** 2026-09-09
**Status:** accepted

**Context.** TCGplayer's `publishedOn` field is unreliable. Of 220 sets, 19 carry
the date the catalog was extracted rather than a release date. The obvious fix is
to research the 19 missing dates and fill them in.

**Decision.** Split the 19 by whether a single-day release event actually
occurred, using a seed (`set_release_date_overrides`) with a sourced date, a
cohort-eligibility flag, and a written reason per row.

- **Datable and eligible:** EX Trainer Kit 1 and 2. Retail products with street
  dates.
- **Datable but not eligible:** POP Series 1 through 9. Distributed over roughly
  twelve-month windows through Organized Play events rather than released on a
  date. A window start can be recorded, but days-since-release would not measure
  what it measures for a normal set.
- **Neither:** Alternate Art Promos, Blister Exclusives, Burger King Promos,
  First Partner Pack, Miscellaneous Cards & Products, Nintendo Promos, Pikachu
  World Collection Promos, Professor Program Promos. These are catch-all buckets
  accumulating cards across decades. They were never released; assigning them any
  date would be inventing data.

**Consequences.** `int_card_printings` coalesces the override over
`publishedOn` and exposes `is_set_cohort_eligible`. Eligible sets span 1999-01-09
to 2026-11-06. The reasoning generalizes: for any cohort analysis, the question
is whether the anchoring event is a point in time, not whether a timestamp is
available.

A singular test flags any set whose release date falls within seven days of the
current date with no override row, catching newly catalogued legacy sets before
they poison a cohort.

---

## 010 — Rarity is tiered via seed, with three values excluded from analysis

**Date:** 2026-09-09
**Status:** accepted

**Context.** TCGplayer rarity is free text with 29 distinct values. Naming has
drifted across eras, and the expensive modern rarities (Special Illustration
Rare at 224 cards, Hyper Rare at 74) are thin enough that single outliers move
their averages.

**Decision.** A `rarity_tiers` seed maps raw strings to six tiers — base, rare,
ultra, chase, promo, excluded — with an `is_analysis_eligible` flag. Unmapped
values default to `unmapped` and ineligible, so a new rarity from upstream is
excluded until reviewed rather than silently included.

Three values are excluded outright:
- **Code Card** (1,091): digital redemption codes, not collectibles. Worthless by
  design and would drag down base-tier averages.
- **None** (129) and **Unconfirmed** (66): missing-data markers, not rarities.

**Consequences.** Tier boundaries are a judgement call informed by card-game
convention, not an official taxonomy. They are visible and versioned in the seed,
so disagreement is a one-line change rather than a model rewrite. The
`card_count` column in the seed is a snapshot from generation time, informational
only, and will drift as the catalog grows.

---

## 011 — Percent change is null across non-consecutive observations

**Date:** 2026-09-09
**Status:** accepted

**Context.** A `dbt_expectations` bounds test on `pct_change_1d` (-99% to +1000%)
fired on 580 rows. The tempting fix is to widen the bounds until it passes.

**Investigation.** Splitting the failures by direction showed two distinct
causes:

- **572 upward spikes, mean prior price $3.17.** Penny-card relisting noise. A
  card at $0.05 relisting at $18 is a +36,000% change that is arithmetically
  correct and analytically meaningless. Concentrated in illiquid categories:
  Countdown Calendar Promos, Jumbo Cards, League & Championship Cards, energy
  cards.
- **8 downward crashes, mean prior price $75.28.** Real cards at real prices,
  few enough to inspect individually.

Applying a $1.00 materiality floor (`is_move_material`) left 191. Of those, 169
shared a single date: 2026-08-25. That date's own statistics were entirely normal
— 42,933 rows, mean $18.20, median $0.98, indistinguishable from its neighbours —
so the date was not the problem.

2026-08-25 is the boundary between the initial two-week extract and the ongoing
backfill. `lag(market_price, 1)` returns the previous *observation*, not the
previous *day*. Across the unfilled gap, cards were being compared against
observations up to eight months old, producing apparent one-day moves of several
thousand percent.

**Decision.** Compute the real interval with
`date_diff('day', lag(price_date) over w, price_date)` and return null for
`pct_change_1d` where that interval is not 1. Expose
`days_since_prev_observation` and `is_consecutive_day`.

Null is correct rather than conservative: across a gap the metric is undefined,
and a computed number would be mislabeled rather than merely noisy.

**Consequences.** Measured impact is small. Of 12.2M rows, 99.4% are consecutive.
The 79,232 non-consecutive rows decompose as 40,820 first-observations (one per
printing, unavoidable), 36,605 at the backfill seam (35,682 on 2026-08-25 alone,
which will close when the backfill completes), and 1,807 genuine mid-series gaps
— 0.015% of rows. TCGplayer prices nearly everything nearly every day.

Two follow-ups:
- `prev_week_price` uses `lag(..., 7)` and has the same rows-versus-days flaw. It
  needs the same treatment.
- The $1.00 materiality floor was chosen while the seam was still open. Revisit
  it against complete data rather than keeping a threshold set under bad
  conditions.

Moving averages (`moving_avg_7d`, `moving_avg_30d`) deliberately remain
observation-based rather than calendar-based. Given 0.015% genuine sparsity the
two are near-identical here, but the choice is a choice and is recorded as one.


**Revised 2026-09-10 — the penny-card diagnosis was mostly wrong.**

The original entry attributed 572 upward spikes to penny-card relisting noise and
introduced a $1.00 materiality floor on that basis. Re-measured against the
complete backfill, that attribution does not hold.

Extreme daily moves (|pct_change_1d| > 1000) by prior price band, over ~34.7M
rows with a defined daily change:

| Prior price | Rows | Extreme | Rate per 100k |
|---|---|---|---|
| under $0.50 | 15,094,705 | 175 | 1.16 |
| $0.50–$1.00 | 4,170,370 | 24 | 0.58 |
| $1.00–$5.00 | 7,681,437 | 17 | 0.22 |
| $5.00+ | 7,731,532 | 32 | 0.41 |

Cheap cards are noisier, but only by roughly threefold — not the order of
magnitude the original entry implied. The 572 spikes were overwhelmingly an
artifact of the backfill seam, where `lag()` compared cards against observations
up to eight months old. Price level was a secondary contributor that the seam made
look primary, because thin cards drift proportionally further over eight months
than liquid ones do.

**What this changes.** `is_move_material` is retained at the $1.00 threshold, but
it is a mild noise filter rather than the load-bearing correction the original
entry described. Analysts doing movement work should still use it; they should not
believe that excluding sub-$1 cards removes most extreme moves. It does not.

**What it does not change.** The window-function fix (null across non-consecutive
observations) was correct and remains the substantive part of this entry. It was
the actual cause.

**Residual after both fixes.** 58 warnings against the complete dataset, scattered
across dates with a maximum of 4 on any single day. That is a genuine heavy tail —
0.00017% of rows — not a defect. The bounds test stays at `warn` severity for
exactly this reason: it should prompt a look, not block a build.

**Method note.** The original diagnosis was made against a dataset with a known
14-month hole, and it was made confidently. Re-measuring after the hole closed
overturned it. Worth remembering that a plausible explanation measured against
incomplete data is a hypothesis, not a finding.

**Measured 2026-09-10.** The reasoning in this entry was directionally correct and
the stated mechanism was backwards.

Across cards carrying both printings, Reverse Holofoil trades at a median 2.74x
Normal for base-tier cards (n=9,283) and 2.01x for rares (n=1,946). The original
text warned that reverse holos would "drag down every rarity-level average." They
would do the opposite — they are the more expensive printing, and product-level
aggregation would inflate base-tier medians rather than depress them.

The conclusion stands and is now quantified: product-level aggregation blends
populations differing by nearly threefold, with a blend ratio varying by set
according to reverse-holo composition. The decision was right; the explanation
for why was wrong, and is corrected here rather than edited above.

Printing types observed across the full catalog, confirming the `accepted_values`
list was complete: Normal (17,357), Reverse Holofoil (13,798), Holofoil (10,766),
1st Edition (762), Unlimited (761), 1st Edition Holofoil (183), Unlimited Holofoil
(179). That test is now `error` rather than `warn` — a new printing type appearing
upstream should stop the build.

**Status revised 2026-09-10: deferred, not built.**

The reconciliation model described above does not exist in this repository, and
neither does the pokemontcg.io enrichment it would validate. This note records why
it was deferred rather than leaving the entry reading as if it had been
implemented.

**What changed since the decision.** Release date was the most load-bearing reason
for the enrichment, and 009 solved it another way — a 19-row seed at the set
level, sourced and documented, rather than a fuzzy join across ~43,500 card
printings. That removed the urgency without removing the case entirely: artist,
subtypes, and format legality are still only available from pokemontcg.io, and
they remain the most interesting unexplored explanatory variables for price.

**Why it is deferred rather than dropped.** The join is the genuinely difficult
part of this project and would take longer than everything built so far. It has to
match on set abbreviation plus collector number across two catalogs that share no
identifier, against a source where promos, reprints and special subsets are the
expected failure classes. Doing it properly means the reconciliation model, a
threshold set from a first real measurement, and manual review of the unmatched
tail — very likely a third seed in the same pattern as the other two.

Doing it badly means an inner join that silently drops the cards that fail to
match, which would be the single worst thing in the repository: a filter that
looks like a join, removing exactly the unusual cards most likely to be
interesting, with no test that would catch it.

**The design commitment stands.** If and when this is built, unmatched cards keep
their TCGplayer attributes and carry null enrichment. They stay in price analysis
and drop out only of cuts depending on an enriched field. The unmatched rate is
reported by set and tested against a threshold. That was the right call when
written and remains so; only the timing changed.

**What this entry is now.** A specification for future work, not a description of
the system. Anything in this decision log without a corresponding model should say
so plainly — a log that mixes what was built with what was intended is worse than
no log, because a reader cannot tell which is which.