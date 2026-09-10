# Changelog

A running log of what changed and why. One entry per working session, not per
commit — git already has the commits. This is for the reasoning that a diff
cannot show.

Format: date, then what moved, then anything that surprised you. The surprises
are the most valuable part; they are what you will be asked about.

---

## 2026-09-08 — Project scaffolded

**Added**
- Repo structure, dbt project config, DuckDB profile, dbt_utils and
  dbt_expectations packages.
- `extract/fetch_tcgcsv.py` with `catalog` and `prices` commands, supporting both
  live endpoints and archive backfill.
- Source definitions for the four landing tables, with freshness on `prices`.
- Staging layer: `stg_tcgcsv_prices`, `stg_tcgcsv_products`, `stg_tcgcsv_groups`.
- Decision log entries 001 through 006.

**Decisions made**
- DuckDB over a cloud warehouse (001).
- TCGCSV over the closed TCGplayer API (002).
- Fact grain fixed at product x printing x day (004).

**Open questions**
- Actual size of a single daily archive, and therefore how long a full backfill to
  2024-02-08 will take.
- Whether TCGCSV's `extendedData` attribute names are stable across sets, or vary
  by era. The pivot in `stg_tcgcsv_products` assumes they are stable.
- Whether `publishedOn` on groups is a genuine set release date or a mirror
  ingestion date. This matters for the release-cohort mart.

**Surprises**
- (nothing yet — first session)

---

## 2026-09-09 — Environment, full pipeline, and a data quality investigation

Longest session so far. Went from nothing installed to a working warehouse with
12.2M price rows and a modeled star schema.

**Environment**
- Python 3.12, venv, dbt-core 1.12.4, dbt-duckdb 1.11.0 on Windows.
- Public GitHub repository created and pushed.
- `query.py`, a small read-only DuckDB query helper. Chdirs into `analytics/` so
  relative source paths resolve the way they do under dbt.
- `docs/RUNBOOK.md` — session commands, setup from scratch, build roadmap,
  troubleshooting.

**Data loaded**
- Catalog: 220 sets, ~43,500 priced printings, product attributes.
- Prices: backfill from 2024-02-08 running throughout the session, reaching
  2026-09-07 by the end. ~45,000 rows per day, 12.2M rows total.

**Models built**
- Intermediate: `int_card_printings`, `int_price_snapshots`. Both views.
- Seeds: `set_release_date_overrides` (19 rows), `rarity_tiers` (29 rows).
- Marts: `dim_card_printing`, `fct_card_price_daily`, `fct_price_metrics`.
- Intermediate materialization switched from `ephemeral` to `view` so the tables
  can be queried directly while still learning what is in them.

**Decisions made**
- 007 sealed product flagged at intermediate, filtered at mart.
- 008 `market_price` and `mid_price` kept separate, not coalesced.
- 009 cohort eligibility is about whether a release event happened, not whether a
  date exists.
- 010 rarity tiered by seed; code cards and missing-data markers excluded.
- 011 percent change is null across non-consecutive observations.

**Questions answered**
- Grain confirmed: the `unique_combination_of_columns` test passes against 12.2M
  rows, so TCGCSV publishes exactly one row per product per printing per day.
- `extendedData` attribute names are stable — the pivot's assumed names all
  appear.
- `publishedOn` is a real release date for 201 of 220 sets, earliest 1999-01-09.
  The other 19 carry the extract date.
- Market price coverage is high and even across tiers: 97% base, 99.2% rare,
  99.3% ultra, 99% chase, 95.4% promo. So cross-tier comparisons carry no
  selection effect — worth having verified rather than assumed.

**Surprises**

- *Windows ships a decoy Python.* A Microsoft Store stub intercepts the `python`
  command and reports "Python was not found" even when Python is correctly
  installed and on the PATH, because `WindowsApps` sits earlier in the PATH than
  the real install. Both entries exist; the wrong one wins.

- *dbt's directory layout is not cosmetic.* With files flat in the repo root, dbt
  found nothing at all. `model-paths` is what makes `models/` meaningful, and the
  extract script resolves its landing folder relative to its own location. Both
  silently do the wrong thing when files sit in the wrong place.

- *Stale views produce errors that point at the wrong file.* A view holds its SQL
  until something rebuilds it, so a renamed column surfaces as an error in
  whatever model reads the view, not in the view itself. `dbt build` without a
  selector avoids this by rebuilding in dependency order.

- *A green pipeline is not a correct one.* `days_since_set_release` was computing
  nonsense for 19 sets whose `publishedOn` was the catalog load date. Every model
  built, every test passed. Only looking at the values caught it.

- *The most useful thing about the bad release dates was not the dates.* Eight of
  the nineteen turned out to be catch-all buckets — promos, "Miscellaneous Cards
  & Products" — that accumulate cards across decades and were never released at
  all. Researching a date for them would have been inventing data. The POP Series
  sets are a middle case: distributed over twelve-month windows through Organized
  Play, so a release date exists in a loose sense but a release *event* does not.
  Recognizing that category was worth more than filling in nineteen cells.

- *A bounds test fired and the cause was not what it looked like.* Full write-up
  in DECISIONS 011. Short version: 580 failures decomposed into penny-card
  relisting noise (572, mean prior price $3.17) and real crashes (8, mean prior
  price $75.28). After a $1 materiality floor, 169 of the remaining 191 shared one
  date. That date's own statistics were completely normal — it was the seam
  between two extraction runs, and `lag()` was comparing cards against
  observations up to eight months old. The bug was window-function semantics, not
  bad data. Measured impact once understood: genuine mid-series gaps affect 0.015%
  of rows.

- *Round numbers are a tell, except when they aren't.* Two Base Set Shadowless
  Charizard rows both landing on exactly $10,000.00 read as a system ceiling.
  They weren't — that is simply where the card trades.

**Open questions**
- Backfill still filling the gap between 2024 and 2026-08-25. Until it closes,
  ~35,700 rows carry an artificial observation gap.
- `prev_week_price` uses `lag(..., 7)` and has the same rows-versus-days flaw as
  `pct_change_1d` did. Needs the same fix.
- The $1.00 materiality floor was chosen while the seam was open. Re-derive it
  from complete data.
- EX Trainer Kit 1 and 2 release dates still blank in the seed.

---

## Next session

- Fill the two EX Trainer Kit dates, re-seed, rebuild.
- Once the backfill completes: rebuild, re-check the bounds test, revisit the
  materiality floor, fix `prev_week_price`.
- Convert `fct_card_price_daily` to incremental. Not before the backfill finishes
  — an incremental model filtering on `max(price_date)` would permanently miss
  every date landing behind the current maximum.
- Materialize `stg_tcgcsv_prices` as a table if build times get annoying.
- One-pagers for the three marts.
- Phase 6 enrichment and the reconciliation model (DECISIONS 005).
- GitHub Action running `dbt build` on pull requests.

## 2026-09-10 — Backfill complete; earlier diagnosis partly overturned

**Data**
- Backfill finished. Complete daily coverage 2024-02-08 to 2026-09-07, ~945 days,
  no gaps. Month-level check confirms every month full; 2024-02 shows 22 days
  because archives begin on the 8th.

**Changed**
- Full `dbt build` against complete data: 51 tests pass, 1 warn, 0 errors.
- DECISIONS 011 revised — see below.
- `fct_price_metrics` one-pager updated with corrected reasoning on
  `is_move_material`.

**Questions answered**
- Bounds test warnings fell from 191 to 58 once the seam closed, confirming the
  window-function fix addressed the dominant cause.
- The residual 58 are scattered, maximum 4 on any single date. Genuine heavy tail,
  not a defect.

**Surprises**
- *The penny-card diagnosis was mostly wrong, and it had been made confidently.*
  Re-measuring extreme move rates by prior price band against complete data showed
  only a threefold difference between sub-$0.50 and $5+ cards, not the order of
  magnitude assumed. The spikes had been overwhelmingly seam artifact; price level
  was a secondary factor that the seam amplified. The `is_move_material` flag is
  retained but its documented justification was rewritten.

  The general lesson is the one worth keeping: a plausible explanation measured
  against a dataset with a known hole in it is a hypothesis, not a finding. The
  original analysis was internally consistent and wrong.

- *Build time scaled worse than expected.* 10 seconds over 12.2M rows became
  3 minutes 51 seconds over the full dataset, because staging models are views
  re-scanning every parquet partition on each downstream query. This is the
  trigger condition recorded in DECISIONS 006.

**Open questions**
- `pct_change_7d` still uses `lag(..., 7)` and carries the rows-versus-days flaw.
- Whether to lower the materiality floor to $0.50 or retain $1.00. Retained for
  now with corrected documentation.