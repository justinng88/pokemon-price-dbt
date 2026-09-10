# Upstream layers: staging, intermediate, seeds

Short-form reference. The mart one-pagers carry the detail a consumer needs;
these models are internal and documented at the level a maintainer needs.

---

## Staging — `main_staging`

Rename, type, and reshape. One model per source table, no business logic, no
filtering.

### `stg_tcgcsv_prices`
Grain: product x printing x day. `price_date` from the hive partition path.
Adds `card_printing_key`. Preserves nulls in price columns rather than
zero-filling, so "no sales" stays distinguishable from "sold for nothing".

### `stg_tcgcsv_products`
Grain: one row per product. Pivots the long `product_attributes` landing table
into columns — `card_number`, `rarity`, `card_type`, `evolution_stage`, `hp`,
`card_text`. Attribute names confirmed stable across eras (2026-09-09).
Derives `is_sealed_product` heuristically: no card number and no rarity.

### `stg_tcgcsv_groups`
Grain: one row per set, 220 rows. `set_published_date` is a genuine release date
for 201 sets and the catalog extract date for 19. Corrected downstream via seed.

---

## Intermediate — `main`

Materialized as **views**, not ephemeral, so they can be queried directly during
development. Revisit once the project stops changing daily.

### `int_card_printings`
Grain: one row per printing. Row set derived from **distinct printings in the
price feed**, because the product catalog does not record which printings exist.
Joins product attributes, set attributes, and both seeds. Keeps sealed product,
flagged — intermediate models should not discard rows a mart might want.

### `int_price_snapshots`
Grain: printing x day. Computes `days_since_set_release` here so downstream cohort
analysis is a group-by rather than a join. Inner joins to `int_card_printings`,
dropping price rows for products absent from the catalog.

---

## Seeds

Hand-maintained data, versioned in git. Both exist because the source is wrong or
insufficient in a way no transformation can fix.

### `set_release_date_overrides` (19 rows)
Corrects the 19 sets whose `publishedOn` is the extract date. Every row carries a
written reason. Three categories: datable and cohort-eligible (2 EX Trainer Kits),
datable but not eligible (POP Series 1-9, distributed over 12-month Organized Play
windows), and neither (8 catch-all promo buckets that were never released).
See DECISIONS 009.

**Outstanding:** the two EX Trainer Kit dates are still blank.

### `rarity_tiers` (29 rows)
Maps free-text rarity to six tiers plus an `is_analysis_eligible` flag. Unmapped
values default to ineligible, so a new rarity from upstream is excluded until
reviewed. The `card_count` column is a snapshot from generation time,
informational only, and will drift. See DECISIONS 010.

---

## Owner and last reviewed
Justin Ng / 2026-09-09