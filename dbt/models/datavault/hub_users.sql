{{
    config(
        materialized='incremental',
        unique_key='user_hash_key',
        on_schema_change='append_new_columns'  
    )
}}

SELECT 
    MD5(CONCAT('user', CAST(actor_id AS VARCHAR))) as user_hash_key,
    actor_id as user_id,
    CURRENT_TIMESTAMP as load_date,
    'gh_archive' as record_source
FROM {{  source('raw', 'raw_github_events')  }}
WHERE actor_id IS NOT NULL

{% if is_incremental() %}
    AND NOT EXISTS (
        SELECT 1 FROM {{ this }} 
        WHERE user_id = actor_id
    )
{% endif %}

GROUP BY actor_id
