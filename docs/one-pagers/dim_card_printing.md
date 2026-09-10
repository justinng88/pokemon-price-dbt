# dim_card_printing

*Numbers marked (as of 2026-09-09, pre-complete-backfill) were measured before the
backfill finished. Refresh after a full rebuild.*

## Purpose
The dimension for all card-level price analysis. Describes what a priced entity
*is* — which card, which printing, which set, what rarity — so facts can carry
only measures and keys.

## Grain
One row per **card per printing**.
Primary key: `card_printing_key`, a surrogate over (`product_id`, `printing_type`).
Enforced by: `unique` and `not_null` tests on `card_printing_key`.

Not one row per card. TCGplayer prices a Normal, Holofoil and Reverse Holofoil
version of the same card as three separate series that diverge substantially. See
DECISIONS 004.

## Input sourcing
| Upstream | What it contributes | Refresh |
|---|---|---|
| `int_card_printings` | The row set and all card/set attributes | Every build |
| `rarity_tiers` (seed) | `rarity_tier`, `is_analysis_eligible` | On seed change |
| `set_release_date_overrides` (seed) | Corrected `set_release_date`, `is_set_cohort_eligible` | On seed change |

The row set originates from **distinct printings observed in the price feed**, not
from the product catalog. The catalog does not record which printings a card was
issued in; that only appears as `subTypeName` on price rows.

## Dimensionality
Sliceable: `rarity`, `rarity_tier`, `printing_type`, `set_name`, `set_id`,
`set_release_date`, `card_type`, `evolution_stage`, `hp`, `is_supplemental`.

Deliberately absent: artist, subtypes, format legality, national dex number. These
require the pokemontcg.io enrichment (DECISIONS 003), not yet built.

Nullable and liable to silently shrink a filtered cut:
- `set_release_date` — null for sets with no release event (8 promo buckets)
- `rarity` — null on a small number of products; these get `rarity_tier =
  'unmapped'` and `is_analysis_eligible = false`
- `hp`, `card_type`, `evolution_stage` — absent on non-Pokemon cards (trainers,
  energy)

## Known limitations
- **Sealed product is excluded here**, not upstream. Booster boxes, ETBs and tins
  are identified by a heuristic — no card number and no rarity — which has not
  been validated against a known list. See DECISIONS 007.
- **Rarity tiers are a judgement call.** Six tiers over 29 raw values, informed by
  card-game convention rather than an official taxonomy. Visible and versioned in
  the seed; disagreement is a one-line change.
- **`is_analysis_eligible = false`** excludes Code Card (1,091), None (129) and
  Unconfirmed (66). Code cards are digital redemption codes and do not trade;
  the other two are missing-data markers. *(as of 2026-09-09)*
- **A new rarity from upstream defaults to excluded**, not included. Safer, but it
  means a new tier silently drops out of analysis until someone updates the seed.

## Retention and refresh
Full rebuild every run, materialized as a table. Currently ~43,500 rows
*(as of 2026-09-09)*. Grows only as TCGplayer catalogues new products. Cheap to
rebuild; no incremental logic needed or wanted.

## Tests
| Test | Protects against |
|---|---|
| `unique` + `not_null` on `card_printing_key` | Grain violation; duplicate dimension rows fanning out joins |
| `not_null` on `printing_type` | A price series with no identifiable printing |

## Owner and last reviewed
Justin Ng / 2026-09-09