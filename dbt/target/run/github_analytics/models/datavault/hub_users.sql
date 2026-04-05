
      
        
        
        delete from "github_analytics"."_datavault"."hub_users" as DBT_INTERNAL_DEST
        where (user_hash_key) in (
            select distinct user_hash_key
            from "hub_users__dbt_tmp192322054023" as DBT_INTERNAL_SOURCE
        );

    

    insert into "github_analytics"."_datavault"."hub_users" ("user_hash_key", "user_id", "load_date", "record_source")
    (
        select "user_hash_key", "user_id", "load_date", "record_source"
        from "hub_users__dbt_tmp192322054023"
    )
  