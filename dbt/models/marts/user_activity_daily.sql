{{
    config(
        materialized='table',
        schema='dds'
    )
}}

SELECT 
    DATE(ge.created_at) as activity_date,
    ge.actor_id,
    ge.actor_login,
    COUNT(*) as total_events,
    COUNT(DISTINCT ge.repo_id) as unique_repos,
    SUM(CASE WHEN ge.event_type = 'PushEvent' THEN 1 ELSE 0 END) as push_events,
    SUM(CASE WHEN ge.event_type = 'PullRequestEvent' THEN 1 ELSE 0 END) as pr_events,
    SUM(CASE WHEN ge.event_type = 'IssuesEvent' THEN 1 ELSE 0 END) as issue_events,
    SUM(CASE WHEN ge.event_type = 'WatchEvent' THEN 1 ELSE 0 END) as star_events
FROM {{ ref('raw_github_events') }} ge
GROUP BY 1,2,3
ORDER BY activity_date DESC, total_events DESC
