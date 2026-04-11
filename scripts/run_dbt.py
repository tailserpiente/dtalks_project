#!/usr/bin/env python3
"""
Orchestrates the full dbt pipeline and exports marts to ClickHouse.

Pipeline:
  1. dbt clean + deps
  2. dbt run --target raw          (raw view over raw.github_events)
  3. dbt run --target datavault    (hub_users, link_events)
  4. dbt run --target pre_marts    (user_activity_daily, repo_metrics as tables)
  5. Python export: pre_marts → ClickHouse (psycopg2 → clickhouse-driver)
  6. dbt test
"""

import os
import sys
import json
import subprocess
import psycopg2
from clickhouse_driver import Client as ClickhouseClient

POSTGRES_HOST     = os.getenv('POSTGRES_HOST', 'postgres')
POSTGRES_USER     = os.getenv('POSTGRES_USER', 'analytics_user')
POSTGRES_PASSWORD = os.getenv('POSTGRES_PASSWORD', 'analytics_pass')
POSTGRES_DB       = os.getenv('POSTGRES_DB', 'github_analytics')

CLICKHOUSE_HOST     = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
CLICKHOUSE_PORT     = int(os.getenv('CLICKHOUSE_PORT', '9000'))  # native protocol
CLICKHOUSE_USER     = os.getenv('CLICKHOUSE_USER', 'clickhouse_user')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', 'clickhouse_pass')
CLICKHOUSE_DB       = os.getenv('CLICKHOUSE_DB', 'github_marts')


def run_dbt_command(command: str) -> bool:
    result = subprocess.run(
        f"cd /dbt && dbt {command}",
        shell=True,
        capture_output=False,  # stream output directly
        text=True,
    )
    return result.returncode == 0


def export_marts_to_clickhouse():
    """
    Reads mart tables from PostgreSQL pre_marts schema and bulk-inserts
    them into the corresponding ClickHouse tables (TRUNCATE + INSERT).

    Mapping:
        pre_marts.user_activity_daily  → github_marts.user_activity_daily
        pre_marts.repo_metrics         → github_marts.repo_metrics
    """
    pg_conn = psycopg2.connect(
        host=POSTGRES_HOST,
        database=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )

    ch_client = ClickhouseClient(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        user=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD,
        database=CLICKHOUSE_DB,
    )

    # (pg_schema, pg_table, ch_table)
    tables = [
        ('pre_marts', 'user_activity_daily', 'user_activity_daily'),
        ('pre_marts', 'repo_metrics',        'repo_metrics'),
    ]

    for pg_schema, pg_table, ch_table in tables:
        print(f"\n  → Exporting {pg_schema}.{pg_table} → {CLICKHOUSE_DB}.{ch_table}")

        cursor = pg_conn.cursor()
        cursor.execute(f'SELECT * FROM {pg_schema}.{pg_table}')
        rows = cursor.fetchall()
        col_names = [desc[0] for desc in cursor.description]
        cursor.close()

        if not rows:
            print(f"    ⚠ No rows found in {pg_schema}.{pg_table}, skipping")
            continue

        ch_client.execute(f'TRUNCATE TABLE {CLICKHOUSE_DB}.{ch_table}')

        ch_client.execute(
            f'INSERT INTO {CLICKHOUSE_DB}.{ch_table} ({", ".join(col_names)}) VALUES',
            rows,
        )
        print(f"    ✓ Inserted {len(rows):,} rows into {ch_table}")

    pg_conn.close()


def main():
    load_date = sys.argv[1] if len(sys.argv) > 1 else "2015-01-01"
    vars_json = json.dumps({"load_date": load_date})

    print(f"=== dbt pipeline for date: {load_date} ===\n")

    dbt_steps = [
        ("clean",                                                   "Clean stale artifacts"),
        ("deps",                                                    "Install dbt packages"),
        ("run --target raw --select raw.*",                         "Build raw layer"),
        ("run --target datavault --select datavault.*",             "Build Data Vault"),
        (f"run --target pre_marts --select marts.* --vars '{vars_json}'", "Build marts (PostgreSQL)"),
    ]

    for cmd, description in dbt_steps:
        print(f"--- {description} ---")
        if not run_dbt_command(cmd):
            print(f"✗ Failed: dbt {cmd}")
            sys.exit(1)
        print(f"✓ Done\n")

    print("--- Export marts to ClickHouse (Python) ---")
    try:
        export_marts_to_clickhouse()
        print("✓ ClickHouse export complete\n")
    except Exception as e:
        print(f"✗ ClickHouse export failed: {e}")
        sys.exit(1)

    print("--- Run dbt tests ---")
    if not run_dbt_command("test --target pre_marts --select marts.*"):
        print("⚠ Some dbt tests failed (check output above)")
    else:
        print("✓ All tests passed\n")

    print("=== Pipeline completed successfully ===")


if __name__ == '__main__':
    main()
