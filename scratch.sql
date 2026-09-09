copy (
    select
        set_id,
        cast(null as date) as set_release_date,
        set_name in (
            'EX Trainer Kit 1: Latias & Latios',
            'EX Trainer Kit 2: Plusle & Minun'
        ) as is_cohort_eligible,
        set_name,
        case
            when set_name like 'POP Series%'
                then 'Distributed over a ~12 month window via Organized Play; no single release event'
            when set_name like 'EX Trainer Kit%'
                then 'Retail product with a street date'
            else 'Catch-all bucket spanning multiple eras; no release event'
        end as notes,
        '' as source_url
    from main_staging.stg_tcgcsv_groups
    where set_published_date = date '2026-09-08'
    order by set_name
) to 'seeds/set_release_date_overrides.csv' (header, delimiter ',');