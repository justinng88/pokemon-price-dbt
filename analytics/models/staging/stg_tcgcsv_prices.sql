with source as (

    select * from {{ source('tcgcsv', 'prices') }}

),

renamed as (

    select
        cast(price_date as date)                    as price_date,
        cast("productId" as integer)                as product_id,
        cast("groupId" as integer)                  as group_id,
        "subTypeName"                               as printing_type,

        cast("lowPrice" as decimal(12, 2))          as low_price,
        cast("midPrice" as decimal(12, 2))          as mid_price,
        cast("highPrice" as decimal(12, 2))         as high_price,
        cast("marketPrice" as decimal(12, 2))       as market_price,
        cast("directLowPrice" as decimal(12, 2))    as direct_low_price

    from source
    where "productId" is not null
      and "subTypeName" is not null

)

select
    {{ dbt_utils.generate_surrogate_key(['product_id', 'printing_type']) }}
        as card_printing_key,
    *
from renamed
