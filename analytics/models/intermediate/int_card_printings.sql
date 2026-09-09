{{ config(materialized='view') }}

with printings as (
    select distinct
        card_printing_key,
        product_id,
        printing_type
    from {{ ref('stg_tcgcsv_prices') }}
),

products as (
    select * from {{ ref('stg_tcgcsv_products') }}
),

sets as (
    select * from {{ ref('stg_tcgcsv_groups') }}
),

overrides as (

    select * from {{ ref('set_release_date_overrides') }}

)

select
    printings.card_printing_key,
    printings.product_id,
    printings.printing_type,
    products.product_name,
    products.product_name_clean,
    products.card_number,
    products.rarity,
    products.card_type,
    products.evolution_stage,
    products.hp,
    products.is_sealed_product,
    products.tcgplayer_url,
    products.image_url,
    sets.set_id,
    sets.set_name,
    sets.set_abbreviation,
    coalesce(overrides.set_release_date, sets.set_published_date) as set_release_date,
    coalesce(overrides.is_cohort_eligible, true) as is_set_cohort_eligible,
    sets.is_supplemental
from printings
inner join products
    on printings.product_id = products.product_id
left join sets
    on products.group_id = sets.set_id
left join overrides
    on sets.set_id = overrides.set_id
