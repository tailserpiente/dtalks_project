{{ config(
    materialized='view'  
) }}

SELECT 
    id,
    event_type,
    actor_id,
    actor_login,
    repo_id,
    repo_name,
    created_at,
    payload::jsonb as payload,
    loaded_at
FROM raw.github_events
WHERE created_at IS NOT NULL
{% if is_incremental() %}
    AND loaded_at > (SELECT MAX(loaded_at) FROM {{ this }})
{% endif %}
