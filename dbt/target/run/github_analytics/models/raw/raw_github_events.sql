
  create view "github_analytics"."_raw"."raw_github_events__dbt_tmp"
    
    
  as (
    

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

  );