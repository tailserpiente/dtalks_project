#!/usr/bin/env python3
import subprocess
import os
import sys

def run_dbt_command(command):
    """Запуск dbt команды"""
    result = subprocess.run(
        f"cd /dbt && dbt {command}",
        shell=True,
        capture_output=True,
        text=True
    )
    
    print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    
    return result.returncode == 0

def main():
    print("=== Running dbt transformations ===")
    
    # Запуск трансформаций
    commands = [
        "deps",  # Установка зависимостей
        "run --models raw",  # Raw слой
        "run --models datavault",  # Data Vault слой
        "run --models marts",  # Витрины данных
        "test"  # Тесты
    ]
    
    for cmd in commands:
        print(f"\n--- Executing: {cmd} ---")
        if not run_dbt_command(cmd):
            print(f"Failed at: {cmd}")
            sys.exit(1)
    
    print("\n=== dbt transformations completed successfully ===")
    
    # Экспорт витрин в ClickHouse
    print("\n=== Exporting marts to ClickHouse ===")
    export_cmd = """
    dbt run-operation export_to_clickhouse \
        --args '{mart: user_activity_daily}' && \
    dbt run-operation export_to_clickhouse \
        --args '{mart: repo_metrics}'
    """
    
    if run_dbt_command(export_cmd):
        print("✓ Exported to ClickHouse")
    else:
        print("✗ Export to ClickHouse failed")

if __name__ == '__main__':
    main()