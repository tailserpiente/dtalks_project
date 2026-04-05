{% macro export_to_clickhouse(mart) %}
    {% set target_name = 'clickhouse' %}
    {% set relation = adapter.get_relation(database=target.database, schema=target.schema, identifier=mart) %}
    
    {% if not relation %}
        {{ log("Creating table " ~ mart ~ " in ClickHouse", info=True) }}
        {% set create_sql %}
            CREATE TABLE {{ target.schema }}.{{ mart }} AS {{ ref(mart) }}
        {% endset %}
        {{ log("Executing SQL: " ~ create_sql, info=True) }}
        {% do run_query(create_sql) %}
    {% endif %}
    
    {{ log("Exporting " ~ mart ~ " to ClickHouse", info=True) }}
    
    {% set insert_sql %}
        INSERT INTO {{ target.schema }}.{{ mart }} 
        SELECT * FROM {{ ref(mart) }}
    {% endset %}
    {{ log("Executing SQL: " ~ insert_sql, info=True) }}
    {% do run_query(insert_sql) %}
    {{ log("✓ Exported " ~ mart, info=True) }}
{% endmacro %}
