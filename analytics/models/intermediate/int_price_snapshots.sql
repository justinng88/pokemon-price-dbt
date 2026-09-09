{{ config(materialized='view') }}

with prices as (

    select * from {{ ref('stg_tcgcsv_prices') }}

),

printings as (

    select
        card_printing_key,
        is_sealed_product,
        set_release_date,
        is_set_cohort_eligible
    from {{ ref('int_card_printings') }}

)

select
    prices.card_printing_key,
    prices.price_date,
    prices.product_id,
    prices.printing_type,

    prices.low_price,
    prices.mid_price,
    prices.high_price,
    prices.market_price,
    prices.direct_low_price,

    printings.is_sealed_product,
    printings.is_set_cohort_eligible,

    date_diff('day', printings.set_release_date, prices.price_date)
        as days_since_set_release,

    prices.market_price is not null as has_market_price

from prices

inner join printings
    on prices.card_printing_key = printings.card_printing_key
