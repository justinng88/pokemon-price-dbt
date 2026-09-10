# fct_card_price_daily

*Numbers marked (as of 2026-09-09, pre-complete-backfill) were measured before the
backfill finished. Refresh after a full rebuild.*

## Purpose
The raw daily price record. One observation per printing per day, restricted to
single cards, with flags that let downstream models exclude classes of row
explicitly rather than by accident.

## Grain
One row per **card printing per day**.
Primary key: (`card_printing_key`, `price_date`).
Enforced by: `dbt_utils.unique_combination_of_columns`.

Confirmed against 12.2M rows: TCGCSV publishes exactly one row per product per
printing per day, with no duplicates. This was an assumption when the model was
designed and is now measured.

## Input sourcing
| Upstream | What it contributes | Refresh |
|---|---|---|
| `int_price_snapshots` | All measures, `days_since_set_release` | Every build |
| `dim_card_printing` | Restriction to single cards (inner join) | Every build |

Ultimately sourced from TCGCSV daily price archives, landed as hive-partitioned
parquet by `extract/fetch_tcgcsv.py`. `price_date` comes from the partition path,
not the payload — TCGCSV price records carry no date of their own.

## Dimensionality
No attributes of its own. Join to `dim_card_printing` on `card_printing_key` for
anything descriptive.

Carries three flags for filtering:
- `is_presale` — `days_since_set_release < 0`. Cards listed before release price
  a product that cannot yet be opened or graded and behave nothing like
  post-release prices. ~326k rows, ~3% *(as of 2026-09-09)*.
- `is_set_cohort_eligible` — false for the 19 sets with no single-day release
  event. See DECISIONS 009.
- `has_market_price` — whether `market_price` is populated.

## Known limitations
- **`market_price` is nullable and is not coalesced with `mid_price`.** Market
  price derives from completed sales; mid price is the midpoint of open listings.
  They measure different things, and coalescing would produce a column whose
  meaning silently changes with a card's liquidity. See DECISIONS 008.
- **Coverage is high and even**, so this is a smaller caveat than expected:
  97% base, 99.2% rare, 99.3% ultra, 99% chase, 95.4% promo
  *(as of 2026-09-09)*. Cross-tier comparisons carry no material selection
  effect. The excluded tier sits at 69.8%, confirming code cards do not trade.
- **Condition is not available.** TCGCSV exposes products, not SKUs, so Near Mint
  through Damaged pricing cannot be separated. All prices are printing-level.
- **Rows for cards with no listings are absent, not zero.** "Unavailable" and
  "cheap" are different states and only one of them appears in this table.

## Retention and refresh
2024-02-08 (earliest available archive) to present. Currently materialized as a
table and fully rebuilt each run.

**Should be converted to incremental** now the backfill is complete. It was
deliberately left as a table while the backfill ran: an incremental model
filtering on `price_date > max(price_date)` would have permanently skipped every
date landing behind the running maximum.

## Tests
| Test | Protects against |
|---|---|
| `unique_combination_of_columns` on the grain | Duplicate daily observations; the mirror changing its publishing behaviour |
| `relationships` to `dim_card_printing` | Orphan price rows for products missing from the catalog |
| `not_null` on `is_presale` | A row whose release-relative position is unknown being averaged in |

## Owner and last reviewed
Justin Ng / 2026-09-09