# dtalks_project — GitHub Archive Analytics Pipeline

End-to-end data engineering pipeline: загружает события из [GH Archive](https://www.gharchive.org/), моделирует их через Data Vault, строит аналитические витрины и показывает дашборды в Apache Superset.

---

## Архитектура

```
GH Archive (HTTPS)
        │  wget  (pipeline.sh шаг 1)
        ▼
  ┌─────────────┐
  │  MinIO (S3) │  github-archive/YYYY/MM/DD/*.json.gz
  └──────┬──────┘
         │  load_to_postgres.py  (pipeline.sh шаг 2)
         ▼
  ┌──────────────────────────────────────────────┐
  │              PostgreSQL 18                   │
  │  raw        → raw.github_events             │
  │  datavault  → hub_users, link_events        │
  │  pre_marts  → user_activity_daily,          │
  │               repo_metrics (tables)          │
  └──────────────────────────────────────────────┘
         │  run_dbt.py  (pipeline.sh шаг 3)
         ▼
  ┌─────────────────┐
  │   ClickHouse    │  github_marts.*  (Python bulk insert)
  └────────┬────────┘
           ▼
  ┌─────────────────┐
  │ Apache Superset │  дашборды
  └─────────────────┘
```

---

## Стек

| Сервис | Образ | Порт(ы) | Роль |
|---|---|---|---|
| **MinIO** | `minio/minio:latest` | `9000` (API), `9001` (Console) | S3-хранилище сырых файлов |
| **PostgreSQL** | `postgres:18` | `5432` | Raw + Data Vault + Marts |
| **ClickHouse** | `clickhouse/clickhouse-server:latest` | `8123` (HTTP), `9010`→`9000` (native) | Аналитические витрины |
| **dbt** | custom (`dbt/Dockerfile`) | — | Трансформации + экспорт |
| **Superset** | custom (`superset/Dockerfile`) | `8088` | BI / дашборды |

> **Сеть внутри Docker:** ClickHouse native-порт внутри сети — `9000` (не `9010`).  
> `9010` — это только хост-маппинг. Все скрипты внутри контейнеров используют `clickhouse:9000`.

---

## Структура проекта

```
dtalks_project/
├── pipeline.sh                 # ← главный скрипт запуска пайплайна
├── docker-compose.yml
├── .env                        # секреты (не коммитится)
├── requirements.txt
│
├── dbt/
│   ├── Dockerfile              # python:3.12-slim + dbt-postgres + dbt-clickhouse + clickhouse-driver
│   ├── dbt_project.yml
│   ├── profiles.yml            # targets: raw | datavault | pre_marts | clickhouse
│   ├── macros/
│   │   ├── generate_hash.sql   # MD5(CONCAT(...)) для DV-ключей
│   │   └── export_to_clickhouse.sql
│   └── models/
│       ├── raw/                # raw_github_events (view)
│       ├── datavault/          # hub_users, link_events (incremental)
│       ├── marts/              # user_activity_daily, repo_metrics (table → pre_marts schema)
│       └── export_clickhouse/  # v_user_activity_daily (не используется, экспорт через Python)
│
├── scripts/
│   ├── load_to_postgres.py     # MinIO → raw.github_events (принимает DATE аргумент)
│   ├── run_dbt.py              # dbt raw→datavault→marts + Python экспорт в ClickHouse
│   └── download_to_s3.py       # альтернативный скрипт скачивания (не используется в pipeline.sh)
│
├── postgres/
│   └── init-datavault.sql      # схемы raw/datavault/dds, таблицы, индексы
├── clickhouse/
│   └── init.sql                # DB github_marts + таблицы витрин (выполняется один раз при пустом volume)
├── superset/
│   ├── Dockerfile              # apache/superset:latest + psycopg2-binary + clickhouse-connect (--target venv)
│   └── superset_config.py      # SECRET_KEY, SQLALCHEMY_DATABASE_URI, SimpleCache, TALISMAN_ENABLED=False
└── s3/
    └── init-s3.sh              # автосоздание bucket github-archive при старте MinIO
```

---

## Модель данных

### Raw (`raw.github_events`)
```
id, event_type, actor_id, actor_login, repo_id, repo_name,
created_at, payload (JSONB), raw_data (TEXT), loaded_at
```

### Data Vault (`datavault` schema)
| Таблица | Тип | Ключ |
|---|---|---|
| `hub_users` | Hub | `user_hash_key` MD5(actor_id) |
| `hub_repos` | Hub | `repo_hash_key` MD5(repo_id) |
| `sat_user_details` | Satellite | `(user_hash_key, load_date)` |
| `link_events` | Link | `event_hash_key` MD5(user+repo+type+date) |

### Marts (PostgreSQL `pre_marts` → ClickHouse `github_marts`)

**`user_activity_daily`** — дневная активность по пользователю:
`activity_date, actor_id, actor_login, total_events, unique_repos, push_events, pr_events, issue_events, star_events`

**`repo_metrics`** — метрики репозитория:
`repo_id, repo_name, unique_contributors, total_events, total_commits, total_prs, total_issues, total_stars, first_activity, last_activity`

---

## Быстрый старт (с нуля)

### 1. Предварительные требования

- Docker ≥ 24 с Compose v2
- WSL2 / Linux
- `mc` (MinIO Client):

```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/
```

### 2. Клонировать и настроить

```bash
git clone <repo-url>
cd dtalks_project
cp .env.example .env   # отредактируй пароли при необходимости
```

### 3. Собрать и запустить контейнеры

```bash
docker compose build --no-cache
docker compose up -d
```

Дождаться `(healthy)` у всех сервисов (~60 с):
```bash
docker compose ps
```

### 4. Инициализировать Superset (один раз)

```bash
docker compose exec superset superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname Admin \
  --email admin@example.com \
  --password admin123
```

> `db upgrade` и `init` выполняются автоматически при старте контейнера.

### 5. Настроить mc alias (один раз)

```bash
mc alias set myminio http://localhost:9000 \
  $(grep MINIO_ROOT_USER .env | cut -d= -f2) \
  $(grep MINIO_ROOT_PASSWORD .env | cut -d= -f2)
```

### 6. Запустить пайплайн

```bash
./pipeline.sh 2015-01-01
```

Для нескольких дней:
```bash
for d in 2015-01-01 2015-01-02 2015-01-03; do
    ./pipeline.sh $d
done
```

---

## Пайплайн (`pipeline.sh`)

Скрипт принимает дату в формате `YYYY-MM-DD` и выполняет 4 шага:

| Шаг | Действие | Идемпотентность |
|---|---|---|
| **1** | Скачивает 24 файла `YYYY-MM-DD-{0..23}.json.gz` с GH Archive | Пропускает уже скачанные |
| **2** | Загружает файлы в MinIO `s3://github-archive/YYYY/MM/DD/` | Пропускает уже загруженные |
| **3а** | `load_to_postgres.py DATE` → `raw.github_events` | `ON CONFLICT DO NOTHING` |
| **3б** | `run_dbt.py DATE` → datavault → pre_marts → ClickHouse | dbt incremental |
| **4** | Проверяет количество строк в ClickHouse | — |

Все учётные данные читаются из `.env`.

---

## Доступ к сервисам

> **WSL2 + VPN:** многие VPN-клиенты блокируют `localhost` в WSL2.  
> Используй IP интерфейса `eth1`:
> ```bash
> ip addr show eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
> ```

| Сервис | URL | Логин |
|---|---|---|
| **Superset** | `http://<WSL_IP>:8088` | admin / admin123 |
| **MinIO Console** | `http://<WSL_IP>:9001` | из `.env` MINIO_ROOT_USER |
| **ClickHouse HTTP** | `http://<WSL_IP>:8123` | из `.env` CLICKHOUSE_USER |

### Подключение ClickHouse в Superset

`Settings → Database Connections → + Database → ClickHouse Connect`

```
clickhousedb://clickhouse_user:ClickHouse2025!@clickhouse:8123/github_marts
```

---

## Управление контейнерами

```bash
# Запустить всё
docker compose up -d

# Пересобрать образы с нуля (без кэша)
docker compose build --no-cache
docker compose up -d

# Остановить (данные сохраняются)
docker compose down

# Полный сброс (УДАЛЯЕТ ВСЕ ДАННЫЕ)
docker compose down -v

# Логи конкретного сервиса
docker compose logs -f superset
docker compose logs -f dbt

# Подключиться к PostgreSQL
docker compose exec postgres psql -U analytics_user -d github_analytics

# Подключиться к ClickHouse
docker compose exec clickhouse clickhouse-client \
  --user clickhouse_user --password ClickHouse2025!
```

---

## Создать таблицы ClickHouse вручную

> Нужно только если контейнер стартовал с уже существующим volume (init.sql не запускается повторно).

```bash
docker compose exec clickhouse clickhouse-client \
  --user clickhouse_user --password ClickHouse2025! \
  --query "
CREATE DATABASE IF NOT EXISTS github_marts;

CREATE TABLE IF NOT EXISTS github_marts.user_activity_daily (
    activity_date Date, actor_id UInt64, actor_login String,
    total_events UInt32, unique_repos UInt32, push_events UInt32,
    pr_events UInt32, issue_events UInt32, star_events UInt32
) ENGINE = MergeTree() ORDER BY (activity_date, actor_id);

CREATE TABLE IF NOT EXISTS github_marts.repo_metrics (
    repo_id UInt64, repo_name String, unique_contributors UInt32,
    total_events UInt32, total_commits UInt32, total_prs UInt32,
    total_issues UInt32, total_stars UInt32,
    first_activity DateTime, last_activity DateTime
) ENGINE = MergeTree() ORDER BY (repo_id, total_events);
"
```

---

## Переменные окружения (`.env`)

| Переменная | Описание |
|---|---|
| `MINIO_ROOT_USER` | MinIO access key |
| `MINIO_ROOT_PASSWORD` | MinIO secret key |
| `POSTGRES_DB` | Имя БД PostgreSQL |
| `POSTGRES_USER` | PG пользователь |
| `POSTGRES_PASSWORD` | PG пароль |
| `CLICKHOUSE_DB` | ClickHouse база (`github_marts`) |
| `CLICKHOUSE_USER` | CH пользователь |
| `CLICKHOUSE_PASSWORD` | CH пароль |
| `SUPERSET_SECRET_KEY` | Flask secret key (сменить в prod!) |

---

## Известные особенности

| Ситуация | Причина | Решение |
|---|---|---|
| Superset не открывается по `localhost` | VPN блокирует WSL2 virtual adapter | Использовать IP `eth1` |
| ClickHouse `Connection refused` из dbt-контейнера | Старый контейнер с `CLICKHOUSE_PORT=9010` | `docker compose exec -e CLICKHOUSE_PORT=9000 dbt ...` или пересоздать контейнер |
| ClickHouse таблицы не существуют | `init.sql` не запускается при существующем volume | Создать таблицы вручную (команда выше) |
| Superset: `No module named psycopg2` | pip в образе устанавливает в системный Python, а не в venv | Исправлено в `superset/Dockerfile`: `pip3 install --target /app/.venv/lib/python3.10/site-packages` |
| `postgres:18` не находится | Образ ещё в beta | Заменить на `postgres:17` в `docker-compose.yml` если нужно |
