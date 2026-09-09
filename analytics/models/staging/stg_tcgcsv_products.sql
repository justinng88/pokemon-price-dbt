with products as (

    select * from {{ source('tcgcsv', 'products') }}

),

attributes as (

    select * from {{ source('tcgcsv', 'product_attributes') }}

),

attributes_pivoted as (

    select
        cast("productId" as integer) as product_id,

        max(case when "attributeName" = 'Number'    then "attributeValue" end) as card_number,
        max(case when "attributeName" = 'Rarity'    then "attributeValue" end) as rarity,
        max(case when "attributeName" = 'CardType'  then "attributeValue" end) as card_type,
        max(case when "attributeName" = 'Stage'     then "attributeValue" end) as evolution_stage,
        max(case when "attributeName" = 'HP'        then "attributeValue" end) as hp,
        max(case when "attributeName" = 'Card Text' then "attributeValue" end) as card_text

    from attributes
    group by 1

),

renamed as (

    select
        cast("productId" as integer)        as product_id,
        cast("groupId" as integer)          as group_id,
        "name"                              as product_name,
        "cleanName"                         as product_name_clean,
        "url"                               as tcgplayer_url,
        "imageUrl"                          as image_url,
        cast("modifiedOn" as timestamp)     as source_modified_at

    from products

)

select
    renamed.product_id,
    renamed.group_id,
    renamed.product_name,
    renamed.product_name_clean,
    renamed.tcgplayer_url,
    renamed.image_url,
    renamed.source_modified_at,

    attributes_pivoted.card_number,
    attributes_pivoted.rarity,
    attributes_pivoted.card_type,
    attributes_pivoted.evolution_stage,
    try_cast(attributes_pivoted.hp as integer) as hp,
    attributes_pivoted.card_text,

    -- Heuristic, not a source field: sealed product (booster boxes, ETBs, tins)
    -- carries no card number or rarity. Validated in docs/one-pagers.
    attributes_pivoted.card_number is null
        and attributes_pivoted.rarity is null as is_sealed_product

from renamed
left join attributes_pivoted
    on renamed.product_id = attributes_pivoted.product_id
