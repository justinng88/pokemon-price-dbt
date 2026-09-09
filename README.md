# Pokemon TCG price analytics

A dbt project that turns daily TCGplayer price snapshots into a modeled warehouse
for analyzing card prices against card-level attributes: rarity, printing, set,
release recency, card type, artist.

Personal, non-commercial project. Price and catalog data comes from
[TCGCSV](https://tcgcsv.com), a public mirror of TCGplayer data. Card attribute
enrichment comes from [pokemontcg.io](https://pokemontcg.io). Nothing here is
affiliated with or endorsed by TCGplayer, eBay, or The Pokemon Company.

## Grain

The single most important thing about this warehouse: **prices are per product per
printing, not per card.** A card with Normal, Holofoil and Reverse Holofoil
printings has three independent price series. The fact grain is
`(product_id, printing_type, price_date)`. See `docs/DECISIONS.md` entry 004.

## Layout

```
extract/       Python extraction into a parquet landing zone. Idempotent.
landing/       Gitignored. Rebuildable from extract/.
analytics/     The dbt project.
  models/staging/       Renaming, typing, pivoting. One model per source table.
  models/intermediate/  Joins and reshaping.
  models/marts/         Dimensions, facts, and metric tables.
docs/          Decision log, changelog, and per-table one-pagers.
```

## Setup

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# Tell dbt where the profile lives
export DBT_PROFILES_DIR="$(pwd)/analytics"

cd analytics
dbt deps
```

## Loading data

```bash
# From the repo root, with the venv active.
# Catalog: sets, products, and product attributes. Run monthly.
python extract/fetch_tcgcsv.py catalog

# Prices: start with a short window to get the pipeline green.
python extract/fetch_tcgcsv.py prices --start 2026-07-10 --end 2026-09-07

# Then backfill wider in the background. Archives begin 2024-02-08.
python extract/fetch_tcgcsv.py prices --start 2024-02-08 --end 2026-07-09
```

## Running

```bash
cd analytics
dbt build            # run + test everything
dbt source freshness # check the mirror is still publishing
dbt docs generate && dbt docs serve
```

## Documentation

- `docs/DECISIONS.md` — why the project is built the way it is. Read this first.
- `docs/CHANGELOG.md` — what changed each session, and what was surprising.
- `docs/one-pagers/` — per-table reference: grain, sourcing, dimensionality,
  limitations, retention.
