
{% macro generate_hash(columns) %}
    MD5(CONCAT(
    {% for column in columns %}
        COALESCE(CAST({{ column }} AS VARCHAR), ''){% if not loop.last %},{% endif %}
    {% endfor %}
    ))
{% endmacro %}
