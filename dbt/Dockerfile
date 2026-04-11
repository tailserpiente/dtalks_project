FROM python:3.12-slim

USER root

# Установка системных зависимостей
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    wget \
    git \
    && rm -rf /var/lib/apt/lists/*

# Установка dbt-postgres, dbt-clickhouse и других пакетов
RUN pip install --no-cache-dir \
    dbt-postgres==1.9.0 \
    dbt-clickhouse==1.8.0 \
    requests==2.31.0 \
    boto3==1.34.0 \
    psycopg2-binary==2.9.9 \
    clickhouse-driver==0.2.9

# Создаем директории
RUN mkdir -p /dbt /root/.dbt

WORKDIR /dbt

# Держим контейнер активным
CMD ["tail", "-f", "/dev/null"]