-- Fails when the price feed is missing calendar days between its earliest and
-- latest date. A partial backfill looks identical to complete data unless
-- something checks, and the gap silently corrupts any day-over-day metric.

with dates as (

    select distinct price_date
    from {{ ref('fct_card_price_daily') }}

),

gaps as (

    select
        lag(price_date) over (order by price_date) as prev_date,
        price_date,
        date_diff('day', lag(price_date) over (order by price_date), price_date) as gap_days
    from dates

)

select *
from gaps
where gap_days > 1