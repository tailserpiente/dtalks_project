{{
    config(
        materialized='incremental',
        unique_key='event_hash_key' 
    )
}}

SELECT 
    MD5(CONCAT(
        COALESCE(actor_id::VARCHAR, ''),
        COALESCE(repo_id::VARCHAR, ''),
        event_type,
        DATE(created_at)::VARCHAR
    )) as event_hash_key,
    MD5(CONCAT('user', CAST(actor_id AS VARCHAR))) as user_hash_key,
    MD5(CONCAT('repo', CAST(repo_id AS VARCHAR))) as repo_hash_key,
    event_type,
    DATE(created_at) as event_date,
    CURRENT_TIMESTAMP as load_date,
    'gh_archive' as record_source
FROM {{ source('raw', 'raw_github_events')  }}

{% if is_incremental() %}
WHERE DATE(created_at) >= (SELECT COALESCE(MAX(event_date), date'1900-01-01') FROM {{ this }})
{% endif %}
