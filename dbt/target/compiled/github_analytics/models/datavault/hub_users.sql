

SELECT 
    MD5(CONCAT('user', CAST(actor_id AS VARCHAR))) as user_hash_key,
    actor_id as user_id,
    CURRENT_TIMESTAMP as load_date,
    'gh_archive' as record_source
FROM "github_analytics"."raw"."raw_github_events"
WHERE actor_id IS NOT NULL


    AND NOT EXISTS (
        SELECT 1 FROM "github_analytics"."datavault"."hub_users" 
        WHERE user_id = actor_id
    )


GROUP BY actor_id