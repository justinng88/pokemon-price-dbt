with source as (

    select * from {{ source('tcgcsv', 'groups') }}

),

renamed as (

    select
        cast("groupId" as integer)          as set_id,
        "name"                              as set_name,
        "abbreviation"                      as set_abbreviation,
        cast("isSupplemental" as boolean)   as is_supplemental,
        cast("publishedOn" as date)         as set_published_date,
        cast("modifiedOn" as timestamp)     as source_modified_at

    from source

)

select * from renamed
