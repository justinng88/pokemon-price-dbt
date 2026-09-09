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
    sets.set_published_date,
    sets.is_supplemental
from printings
inner join products
    on printings.product_id = products.product_id
left join sets
    on products.group_id = sets.set_id
