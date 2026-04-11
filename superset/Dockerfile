FROM apache/superset:latest

USER root

# The venv at /app/.venv has no pip bundled.
# Install system pip, then push packages directly into the venv's site-packages.
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends python3-pip && \
    pip3 install --no-cache-dir \
        --target /app/.venv/lib/python3.10/site-packages \
        psycopg2-binary \
        clickhouse-connect && \
    rm -rf /var/lib/apt/lists/*

USER superset
