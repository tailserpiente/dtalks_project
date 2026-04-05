FROM apache/superset:latest

USER root

RUN apt-get update && apt-get install -y python3-pip && \
    pip install --no-cache-dir psycopg2-binary && \
    apt-get remove -y python3-pip && apt-get autoremove -y



USER superset
