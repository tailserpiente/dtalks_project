
      
        
        
        delete from "github_analytics"."datavault"."link_events" as DBT_INTERNAL_DEST
        where (event_hash_key) in (
            select distinct event_hash_key
            from "link_events__dbt_tmp184052693135" as DBT_INTERNAL_SOURCE
        );

    

    insert into "github_analytics"."datavault"."link_events" ("event_type", "event_date", "load_date", "event_hash_key", "user_hash_key", "repo_hash_key", "record_source")
    (
        select "event_type", "event_date", "load_date", "event_hash_key", "user_hash_key", "repo_hash_key", "record_source"
        from "link_events__dbt_tmp184052693135"
    )
  