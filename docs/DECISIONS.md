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
