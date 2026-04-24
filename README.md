# dtalks_project — GitHub Archive Analytics Pipeline

End-to-end data engineering pipeline that ingests [GH Archive](https://www.gharchive.org/) events, models them through a Data Vault, builds analytics marts and serves dashboards in Apache Superset.

---

## Architecture

```
GH Archive (HTTPS)
        │  wget  (pipeline.sh step 1)
        ▼
  ┌─────────────┐
  │  MinIO (S3) │  github-archive/YYYY/MM/DD/*.json.gz
  └──────┬──────┘
         │  load_to_postgres.py  (pipeline.sh step 2)
         ▼
  ┌──────────────────────────────────────────────┐
  │              PostgreSQL 18                   │
  │  raw        → raw.github_events             │
  │  datavault  → hub_users, link_events        │
  │  pre_marts  → user_activity_daily,          │
  │               repo_metrics (tables)          │
  └──────────────────────────────────────────────┘
         │  run_dbt.py  (pipeline.sh step 3)
         ▼
  ┌─────────────────┐
  │   ClickHouse    │  github_marts.*  (Python bulk insert)
  └────────┬────────┘
           ▼
  ┌─────────────────┐
  │ Apache Superset │  dashboards
  └─────────────────┘
```

---

## Stack

| Service | Image | Port(s) | Role |
|---|---|---|---|
| **MinIO** | `minio/minio:latest` | `9000` (API), `9001` (Console) | S3-compatible object store |
| **PostgreSQL** | `postgres:18` | `5432` | Raw ingestion + Data Vault + Marts |
| **ClickHouse** | `clickhouse/clickhouse-server:latest` | `8123` (HTTP), `9010`→`9000` (native) | Analytics mart storage |
| **dbt** | custom (`dbt/Dockerfile`) | — | Transformations + ClickHouse export |
| **Superset** | custom (`superset/Dockerfile`) | `8088` | BI / dashboards |

> **Docker internal network:** ClickHouse native port inside the network is `9000` (not `9010`).
> `9010` is the host-side mapping only. All scripts inside containers use `clickhouse:9000`.

---

## Project Structure

```
dtalks_project/
├── pipeline.sh                 # ← main pipeline runner
├── docker-compose.yml
├── .env                        # secrets (not committed)
├── requirements.txt
│
├── dbt/
│   ├── Dockerfile              # python:3.12-slim + dbt-postgres + dbt-clickhouse + clickhouse-driver
│   ├── dbt_project.yml
│   ├── profiles.yml            # targets: raw | datavault | pre_marts | clickhouse
│   ├── macros/
│   │   ├── generate_hash.sql   # MD5(CONCAT(...)) for DV hash keys
│   │   └── export_to_clickhouse.sql
│   └── models/
│       ├── raw/                # raw_github_events (view)
│       ├── datavault/          # hub_users, link_events (incremental)
│       ├── marts/              # user_activity_daily, repo_metrics (table → pre_marts schema)
│       └── export_clickhouse/  # v_user_activity_daily (unused; export is done via Python)
│
├── scripts/
│   ├── load_to_postgres.py     # MinIO → raw.github_events  (accepts DATE argument)
│   ├── run_dbt.py              # dbt raw→datavault→marts + Python export to ClickHouse
│   └── download_to_s3.py       # alternative download script (not used by pipeline.sh)
│
├── postgres/
│   └── init-datavault.sql      # raw/datavault/dds schemas, tables, indexes
├── clickhouse/
│   └── init.sql                # DB github_marts + mart tables (runs once on empty volume)
├── superset/
│   ├── Dockerfile              # apache/superset:latest + psycopg2-binary + clickhouse-connect
│   └── superset_config.py      # SECRET_KEY, SQLALCHEMY_DATABASE_URI, SimpleCache
└── s3/
    └── init-s3.sh              # auto-creates github-archive bucket on MinIO startup
```

---

## Data Model

### Raw layer (`raw.github_events`)
```
id, event_type, actor_id, actor_login, repo_id, repo_name,
created_at, payload (JSONB), raw_data (TEXT), loaded_at
```

### Data Vault (`datavault` schema, PostgreSQL)

| Table | Type | Key |
|---|---|---|
| `hub_users` | Hub | `user_hash_key` MD5(actor_id) |
| `hub_repos` | Hub | `repo_hash_key` MD5(repo_id) |
| `sat_user_details` | Satellite | `(user_hash_key, load_date)` |
| `link_events` | Link | `event_hash_key` MD5(user+repo+type+date) |

### Marts (PostgreSQL `pre_marts` → ClickHouse `github_marts`)

**`user_activity_daily`** — daily activity per actor:

| Column | Description |
|---|---|
| `activity_date` | calendar date |
| `actor_id` / `actor_login` | GitHub user |
| `total_events` | all event types |
| `unique_repos` | distinct repos touched |
| `push_events` | PushEvent count |
| `pr_events` | PullRequestEvent count |
| `issue_events` | IssuesEvent count |
| `star_events` | WatchEvent count |

**`repo_metrics`** — per-repository aggregates:

| Column | Description |
|---|---|
| `repo_id` / `repo_name` | repository |
| `unique_contributors` | distinct actors |
| `total_events` | total activity |
| `total_commits` / `total_prs` / `total_issues` / `total_stars` | event type counts |
| `first_activity` / `last_activity` | activity window |

---

## Quick Start (from scratch)

### 1. Prerequisites

- Docker ≥ 24 with Compose v2
- WSL2 / Linux with internet access
- `mc` (MinIO Client):

```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/
```

### 2. Clone and configure

```bash
git clone <repo-url>
cd dtalks_project
cp .env.example .env   # edit passwords if needed
```

### 3. Build and start containers

```bash
docker compose build --no-cache
docker compose up -d
```

Wait for all services to become `(healthy)` (~60 s):
```bash
docker compose ps
```

### 4. Initialize Superset (one-time)

```bash
docker compose exec superset superset fab create-admin \
  --username admin \
  --firstname Admin \
  --lastname Admin \
  --email admin@example.com \
  --password admin123
```

> `db upgrade` and `init` run automatically on container start.

### 5. Configure mc alias (one-time)

```bash
mc alias set myminio http://localhost:9000 \
  $(grep MINIO_ROOT_USER .env | cut -d= -f2) \
  $(grep MINIO_ROOT_PASSWORD .env | cut -d= -f2)
```

### 6. Run the pipeline

```bash
./pipeline.sh 2015-01-01
```

Load multiple days:
```bash
for d in 2015-01-01 2015-01-02 2015-01-03; do
    ./pipeline.sh $d
done
```

---

## Pipeline (`pipeline.sh`)

Accepts a date in `YYYY-MM-DD` format and runs 4 steps:

| Step | Action | Idempotent |
|---|---|---|
| **1** | Downloads 24 hourly `.json.gz` files from GH Archive | Skips already downloaded |
| **2** | Uploads files to MinIO `s3://github-archive/YYYY/MM/DD/` | Skips already uploaded |
| **3a** | `load_to_postgres.py DATE` → `raw.github_events` | `ON CONFLICT DO NOTHING` |
| **3b** | `run_dbt.py DATE` → datavault → pre_marts → ClickHouse | dbt incremental models |
| **4** | Verifies row counts in ClickHouse | — |

All credentials are read from `.env`.

---

## Accessing Services

> **WSL2 + VPN:** many VPN clients break WSL2's virtual network adapter, making `localhost` unreachable.
> Use the `eth1` IP address instead:
> ```bash
> ip addr show eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
> ```

| Service | URL | Credentials |
|---|---|---|
| **Superset** | `http://<WSL_IP>:8088` | admin / admin123 |
| **MinIO Console** | `http://<WSL_IP>:9001` | `MINIO_ROOT_USER` from `.env` |
| **ClickHouse HTTP** | `http://<WSL_IP>:8123` | `CLICKHOUSE_USER` from `.env` |

### Add ClickHouse to Superset

`Settings → Database Connections → + Database → ClickHouse Connect`

```
clickhousedb://clickhouse_user:ClickHouse2025!@clickhouse:8123/github_marts
```

### Import bundled dashboard (GitHub marts)

A ready-made dashboard (KPIs, daily trend, event mix, top users and repos) ships as a Superset **v1** export ZIP. It creates its own ClickHouse database connection and datasets pointing at `github_marts.user_activity_daily` and `github_marts.repo_metrics` (defaults: host `clickhouse`, user `clickhouse_user`, password `clickhouse_pass` — align with your `.env` or edit `databases/ClickHouse_github_marts.yaml` in the bundle before zipping).

```bash
docker compose cp superset/dashboards/github_marts_bi_export.zip superset:/tmp/github_marts_bi_export.zip
docker compose exec superset superset import-dashboards -p /tmp/github_marts_bi_export.zip -u admin
```

Source YAMLs live under `superset/dashboards/github_marts_bundle/` if you need to adjust charts or credentials and rebuild the ZIP (same layout as inside the archive).

---

## Container Management

```bash
# Start all services
docker compose up -d

# Rebuild images from scratch (no cache)
docker compose build --no-cache && docker compose up -d

# Stop (data volumes preserved)
docker compose down

# Full reset — DELETES ALL DATA
docker compose down -v

# Tail logs for a service
docker compose logs -f superset
docker compose logs -f dbt

# Connect to PostgreSQL
docker compose exec postgres psql -U analytics_user -d github_analytics

# Connect to ClickHouse
docker compose exec clickhouse clickhouse-client \
  --user clickhouse_user --password ClickHouse2025!
```

---

## Create ClickHouse Tables Manually

> Only needed if the container started with an existing volume (init.sql does not re-run).

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

## Environment Variables (`.env`)

| Variable | Description |
|---|---|
| `MINIO_ROOT_USER` | MinIO access key |
| `MINIO_ROOT_PASSWORD` | MinIO secret key |
| `POSTGRES_DB` | PostgreSQL database name |
| `POSTGRES_USER` | PostgreSQL username |
| `POSTGRES_PASSWORD` | PostgreSQL password |
| `CLICKHOUSE_DB` | ClickHouse database (`github_marts`) |
| `CLICKHOUSE_USER` | ClickHouse username |
| `CLICKHOUSE_PASSWORD` | ClickHouse password |
| `SUPERSET_SECRET_KEY` | Flask secret key (change in production!) |

---

## Known Issues & Workarounds

| Issue | Cause | Fix |
|---|---|---|
| Superset unreachable via `localhost` | VPN blocks WSL2 virtual adapter | Use `eth1` IP address |
| ClickHouse `Connection refused` from dbt container | Container started with old `CLICKHOUSE_PORT=9010` | Use `docker compose exec -e CLICKHOUSE_PORT=9000 dbt ...` or recreate container |
| ClickHouse tables do not exist | `init.sql` skipped on existing volume | Create tables manually (command above) |
| Superset: `No module named psycopg2` | System `pip install` doesn't reach Superset's venv | Fixed in `superset/Dockerfile`: `pip3 install --target /app/.venv/lib/python3.10/site-packages` |
| `postgres:18` image not found | Image may still be in beta | Replace with `postgres:17` in `docker-compose.yml` if needed |


