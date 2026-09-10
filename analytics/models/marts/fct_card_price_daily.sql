{{ config(
    materialized='incremental',
    unique_key=['card_printing_key', 'price_date'],
    incremental_strategy='delete+insert'
) }}

with snapshots as (

    select * from {{ ref('int_price_snapshots') }}

),

printings as (

    select card_printing_key from {{ ref('dim_card_printing') }}

)

select
    snapshots.card_printing_key,
    snapshots.price_date,

    snapshots.low_price,
    snapshots.mid_price,
    snapshots.high_price,
    snapshots.market_price,
    snapshots.direct_low_price,
    snapshots.has_market_price,

    snapshots.days_since_set_release,
    snapshots.is_set_cohort_eligible,

    -- Presale rows price a product that cannot yet be opened or graded, so they
    -- behave nothing like post-release prices and must not be averaged in.
    coalesce(snapshots.days_since_set_release < 0, false) as is_presale

from snapshots

inner join printings
    on snapshots.card_printing_key = printings.card_printing_key
{% if is_incremental() %}
where snapshots.price_date > (select max(price_date) from {{ this }})
{% endif %}