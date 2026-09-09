with printings as (

    select * from {{ ref('int_card_printings') }}

),

tiers as (

    select * from {{ ref('rarity_tiers') }}

)

select
    printings.card_printing_key,
    printings.product_id,
    printings.printing_type,

    printings.product_name,
    printings.product_name_clean,
    printings.card_number,
    printings.rarity,
    coalesce(tiers.rarity_tier, 'unmapped') as rarity_tier,
    coalesce(tiers.is_analysis_eligible, false) as is_analysis_eligible,
    printings.card_type,
    printings.evolution_stage,
    printings.hp,

    printings.set_id,
    printings.set_name,
    printings.set_abbreviation,
    printings.set_release_date,
    printings.is_set_cohort_eligible,
    printings.is_supplemental,

    printings.tcgplayer_url,
    printings.image_url

from printings

left join tiers
    on printings.rarity = tiers.rarity

where not printings.is_sealed_product