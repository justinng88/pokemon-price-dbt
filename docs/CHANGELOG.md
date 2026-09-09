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
