{{ config(materialized='table') }}

-- Per-printing daily price series with derived movement metrics.
-- Restricted to analysis-eligible cards and post-release rows, so every metric
-- below describes a card that actually trades on the open market.

with base as (

    select
        f.card_printing_key,
        f.price_date,
        f.market_price,
        f.days_since_set_release,
        f.is_set_cohort_eligible
    from {{ ref('fct_card_price_daily') }} f
    inner join {{ ref('dim_card_printing') }} d
        on f.card_printing_key = d.card_printing_key
    where d.is_analysis_eligible
      and not f.is_presale
      and f.market_price is not null

),

windowed as (

    select
        *,

        lag(market_price, 1) over w as prev_day_price,
        lag(market_price, 7) over w as prev_week_price,

        avg(market_price) over (
            partition by card_printing_key
            order by price_date
            rows between 6 preceding and current row
        ) as moving_avg_7d,

        avg(market_price) over (
            partition by card_printing_key
            order by price_date
            rows between 29 preceding and current row
        ) as moving_avg_30d,

        max(market_price) over (
            partition by card_printing_key
            order by price_date
            rows between unbounded preceding and current row
        ) as running_peak_price,

        count(*) over (
            partition by card_printing_key
            order by price_date
            rows between unbounded preceding and current row
        ) as observation_number,

        lag(price_date, 1) over w as prev_observation_date,
        lag(price_date, 7) over w as prev_week_observation_date,

    from base
    window w as (partition by card_printing_key order by price_date)

)

select
    card_printing_key,
    price_date,
    market_price,
    days_since_set_release,
    is_set_cohort_eligible,

    prev_day_price,
    prev_week_price,
    moving_avg_7d,
    moving_avg_30d,
    running_peak_price,
    observation_number,

    -- Null on the first observation of a series rather than zero: no prior price
    -- means no change, which is different from a change of nothing.
    case
        when prev_day_price is null or prev_day_price = 0 then null
        when date_diff('day', prev_observation_date, price_date) <> 1 then null
        else round(100.0 * (market_price - prev_day_price) / prev_day_price, 4)
    end as pct_change_1d,

    case
        when prev_week_price is null or prev_week_price = 0 then null
        when date_diff('day', prev_week_observation_date, price_date) <> 7 then null
        else round(100.0 * (market_price - prev_week_price) / prev_week_price, 4)
    end as pct_change_7d,

    case
        when running_peak_price is null or running_peak_price = 0 then null
        else round(100.0 * (market_price - running_peak_price) / running_peak_price, 4)
    end as pct_below_running_peak,

    -- A percent change on a sub-dollar card is arithmetically true and
    -- analytically useless: one relisting on an illiquid card produces
    -- four-digit percentages. Movement analysis should gate on this flag.
    coalesce(prev_day_price >= 1.00, false) as is_move_material,
    date_diff('day', prev_observation_date, price_date)
        as days_since_prev_observation,

    -- A "1 day" change computed across a multi-month gap is mislabeled, not
    -- merely noisy. Cards are not priced every day, so consecutive rows are not
    -- necessarily consecutive days.
    coalesce(date_diff('day', prev_observation_date, price_date) = 1, false)
        as is_consecutive_day,

from windowed