# fct_price_metrics

*Numbers marked (as of 2026-09-09, pre-complete-backfill) were measured before the
backfill finished. Refresh after a full rebuild.*

**Read this before using any column in this table.** Several columns are null by
design in cases where a computed value would be misleading, and two are gated on
flags rather than being universally valid.

## Purpose
Derived price movement per printing: day-over-day and week-over-week change,
moving averages, and distance below running peak. The analysis layer.

## Grain
One row per **card printing per day**, restricted to rows where a metric is
meaningful.
Primary key: (`card_printing_key`, `price_date`).
Enforced by: `dbt_utils.unique_combination_of_columns`.

Row count is lower than `fct_card_price_daily` because this model requires
`is_analysis_eligible`, `not is_presale`, and a non-null `market_price`.

## Input sourcing
| Upstream | What it contributes | Refresh |
|---|---|---|
| `fct_card_price_daily` | Price series and release-relative position | Every build |
| `dim_card_printing` | `is_analysis_eligible` filter | Every build |

## Dimensionality
No attributes. Join `dim_card_printing` for rarity, set, printing.

## Known limitations

**`pct_change_1d` is null across non-consecutive observations.** `lag()` returns
the previous *observation*, not the previous day. Where the gap is not exactly one
day the metric is undefined, and returning null is honest where a computed number
would be mislabeled. See DECISIONS 011 — this was found because a bounds test
fired on 191 rows, 169 of which shared a single date.

**`is_move_material` gates on prior price ≥ $1.00.** A card at $0.05 relisting at
$18 is a +36,000% change that is arithmetically correct and analytically
meaningless. Movement analysis should filter on this flag. *The $1.00 threshold
was chosen while the backfill seam was still open and should be re-derived from
complete data.*

**Moving averages are over observations, not calendar days.** `moving_avg_7d` is
the mean of the last 7 rows, which for a thinly-traded card could span more than
7 days. Measured impact is small: 99.4% of rows are consecutive, and genuine
mid-series gaps affect 0.015% *(as of 2026-09-09)*. The two definitions are
near-identical on this data, but the choice is a choice.

**`running_peak_price` is a running maximum, not an all-time high.** It looks only
backward from each row, so drawdown on a given date reflects the peak as of that
date. Correct for time-series analysis; wrong if you want current
distance-from-ATH, which needs a separate snapshot model.

**`pct_change_7d` is null where the 7-observation lag does not span exactly 7
days.** Same gating as `pct_change_1d`, applied for the same reason. Costs 1.06%
of rows to null versus 0.16% for the daily metric, since seven consecutive
observations are a stricter requirement than two.

**Prices are right-skewed.** Prefer median over mean for any aggregate.

## Retention and refresh
Matches `fct_card_price_daily`. Table materialization, full rebuild, ~9 seconds
over 12.2M rows *(as of 2026-09-09)*.

## Tests
| Test | Protects against |
|---|---|
| `unique_combination_of_columns` on the grain | Window functions fanning out rows |
| `dbt_expectations.expect_column_values_to_be_between` on `pct_change_1d`, -99 to 1000, scoped to material moves, severity `warn` | Implausible daily moves. **This test found a real bug** — see DECISIONS 011. It is warn rather than error because a heavy-tailed price distribution legitimately produces a handful of extreme moves. |
| `not_null` on `card_printing_key`, `price_date` | Broken keys from the upstream join |

**`is_move_material` gates on prior price ≥ $1.00.** A card at $0.05 relisting at
$18 is a +36,000% change that is arithmetically correct and analytically
meaningless, so movement analysis should filter on this flag.

Measured against the complete backfill, however, the effect is modest: extreme
daily moves occur at 1.16 per 100k rows below $0.50 versus 0.41 per 100k above
$5.00 — roughly threefold, not an order of magnitude. Do not assume this flag
removes most extreme moves. It removes some. The larger source of spurious
movement was the backfill seam, fixed separately. See DECISIONS 011, revised
2026-09-10.

## Owner and last reviewed
Justin Ng / 2026-09-09

