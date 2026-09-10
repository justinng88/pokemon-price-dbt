# Pokémon TCG price analytics

A dbt warehouse over ~945 days of daily TCGplayer price snapshots, built to
analyze card prices against card-level attributes: rarity, printing, set, and
release recency.

**Stack:** dbt-core 1.12 · DuckDB · Python · ~35M price observations across
~43,500 card printings, 2024-02-08 to present.

---

## Finding: price decay after release scales with rarity tier

Median price by days since set release, indexed to 100 at the release window.

| Tier | 0–29d | 30–89d | 90–179d | 180–364d | Change |
|---|---|---|---|---|---|
| Chase | 100 | 83 | 64 | 61 | **−39%** |
| Ultra | 100 | 66 | 60 | 54 | **−46%** |
| Rare | 100 | 96 | 88 | 80 | −20% |
| Base | 100 | 92 | 92 | 92 | −8% |

*Chase = Illustration Rare, Special Illustration Rare, Secret Rare, Hyper Rare and
similar. Base = Common and Uncommon. Excludes presale rows, cohort-ineligible
sets, and non-tradeable products. Medians, not means — the distribution is
severely right-skewed.*

**The higher the tier, the harder the fall.** Ultra-rare cards lose about 46% of
median value within a year of release; commons lose 8%. Most of the decline
happens early — chase cards drop 36% in their first 90 days.

**Ultra decays more than chase**, which was not the expected result. The intuition
going in was that the scarcest cards would fall hardest as supply floods in during
peak pack-opening. Instead, ultra-rare cards — plentiful enough to be pulled
regularly but not scarce enough to be sought — decay furthest. Chase cards hold
proportionally more of their release value.

**Base-tier cards barely move because they cannot.** Their median sits at $0.11–
$0.12 across every window, which is effectively TCGplayer's listing floor. There
is no room to decay. This is a structural property of the marketplace, not a
market observation, and it is the kind of thing an unqualified "commons are
stable" claim would get wrong.

### What this analysis does not show

**Cards past 365 days are excluded from the table above, deliberately.** That
bucket shows *higher* medians than the 180–364 bucket for every tier, which looks
like recovery and is not. The dataset spans 2024 onward, so anything older than a
year is disproportionately drawn from vintage sets going back to 1999 — 22,265
base-tier printings versus roughly 4,000 in each younger bucket. It is a different
population, not a later life stage. Reading a rebound there would be a
composition artifact.

**This is a cross-section, not a cohort.** Each bucket contains different cards,
so the comparison assumes sets released at different times behave comparably. A
stronger version would follow the same printings through time. That is the next
piece of work.

---

## Grain: the decision everything else rests on

**Prices are per product per printing, not per card.** A card issued in Normal,
Holofoil and Reverse Holofoil has three independent price series. The fact grain
is `(product_id, printing_type, price_date)`, keyed by a surrogate
`card_printing_key`.

This was the first architectural decision in the project, and it turned out to be
the one with the largest measured consequence:

| Tier | Cards with both printings | Median Reverse Holofoil ÷ Normal |
|---|---|---|
| Base | 9,283 | **2.74x** |
| Rare | 1,946 | **2.01x** |

Reverse holofoils trade at roughly **two to three times** their normal
counterparts — the opposite of the intuition that the plain printing is the
baseline and the variant is a curiosity. Reverse holos are printed at about one
per pack against a far larger normal print run for commons, so relative scarcity
inverts the expected ordering.

The practical consequence: aggregating prices to the product level would blend two
populations differing by nearly threefold, and the blend ratio would shift set by
set depending on how many reverse holos exist in each. A "median price by rarity"
chart built on product-level data would move for reasons that have nothing to do
with the market.

Enforced by `unique_combination_of_columns` tests at both staging and mart, and by
an `accepted_values` test on `printing_type` so a new variant from upstream fails
the build rather than silently creating a new slice.

*Promo and ultra tiers are omitted from the table above: only two and one cards
respectively carry both printings, which is too few to report.*

---

## Data quality work

Three problems the pipeline found that a green build would not have surfaced:

**Release dates were wrong for 19 of 220 sets**, carrying the catalog extract date
instead. Every model built and every test passed while `days_since_set_release`
computed nonsense for those sets. The fix was not to research 19 dates: eight of
them are catch-all promo buckets that accumulate cards across decades and were
never released at all, and nine are POP Series sets distributed over 12-month
Organized Play windows. Cohort eligibility is about whether a release *event*
happened, not whether a timestamp exists. Corrected via a sourced seed with a
written reason per row.

**A bounds test on daily percent change fired on 580 rows.** The cause was not bad
data — `lag()` returns the previous *observation*, not the previous day, and
across a gap in the backfill, cards were being compared against prices up to eight
months old. Fixed by computing the real day interval and returning null where it
is not 1. Residual after the fix: 58 rows across 945 days, scattered, which is the
genuine tail of a heavy-tailed distribution.

**The first explanation for that test failure was wrong.** It was attributed to
penny-card relisting noise and a materiality floor was added on that basis.
Re-measured against complete data, cheap cards are only about three times noisier
than expensive ones — not the order of magnitude assumed. The original analysis
was internally consistent and incorrect, because it was measured against a dataset
with a known hole in it. Documented as a revision rather than an edit.

Full reasoning in [`docs/DECISIONS.md`](docs/DECISIONS.md).

---

## Sources

**[TCGCSV](https://tcgcsv.com)** — public daily mirror of TCGplayer categories,
groups, products and prices, with archives back to 2024-02-08. TCGplayer's own API
is closed to new developers, and the mirror carries the same data with usable
history.

Personal, non-commercial project. Not affiliated with or endorsed by TCGplayer,
eBay, or The Pokémon Company.

---

## Layout

```
extract/       Idempotent Python extraction into a parquet landing zone
landing/       Gitignored, rebuildable from extract/
analytics/     The dbt project
  models/staging/       Rename, type, pivot. One model per source table.
  models/intermediate/  Joins and reshaping.
  models/marts/         Dimensions, facts, metrics.
  seeds/                Hand-maintained corrections, versioned in git.
  tests/                Singular tests encoding domain expectations.
docs/          Decision log, changelog, per-table one-pagers
query.py       Read-only DuckDB query helper
```

## Setup

```bash
python -m venv .venv && .venv\Scripts\Activate.ps1   # Windows
pip install -r requirements.txt
mkdir "$env:USERPROFILE\.dbt"; cp analytics\profiles.yml "$env:USERPROFILE\.dbt\"

python extract\fetch_tcgcsv.py catalog
python extract\fetch_tcgcsv.py prices --start 2024-02-08 --end 2026-09-07

cd analytics && dbt deps && dbt build
```

Full instructions, troubleshooting and the build roadmap are in
[`docs/RUNBOOK.md`](docs/RUNBOOK.md).

## Documentation

- [`docs/DECISIONS.md`](docs/DECISIONS.md) — every non-obvious choice and why
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — session log, including what was
  surprising
- [`docs/one-pagers/`](docs/one-pagers/) — per-table grain, sourcing,
  dimensionality, limitations