
  
    

  create  table "github_analytics"."pre_marts"."repo_metrics__dbt_tmp"
  
  
    as
  
  (
    

SELECT 
    ge.repo_id,
    ge.repo_name,
    COUNT(DISTINCT ge.actor_id) as unique_contributors,
    COUNT(*) as total_events,
    SUM(CASE WHEN ge.event_type = 'PushEvent' THEN 1 ELSE 0 END) as total_commits,
    SUM(CASE WHEN ge.event_type = 'PullRequestEvent' THEN 1 ELSE 0 END) as total_prs,
    SUM(CASE WHEN ge.event_type = 'IssuesEvent' THEN 1 ELSE 0 END) as total_issues,
    SUM(CASE WHEN ge.event_type = 'WatchEvent' THEN 1 ELSE 0 END) as total_stars,
    MIN(ge.created_at) as first_activity,
    MAX(ge.created_at) as last_activity
FROM "github_analytics"."raw"."raw_github_events" ge
WHERE 1=1
    
        AND DATE(ge.created_at) = DATE('2015-01-03')
    
GROUP BY 1, 2
ORDER BY total_events DESC
  );
  