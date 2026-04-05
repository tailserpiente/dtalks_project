#!/usr/bin/env python3
import subprocess
import os
import sys
import json

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
    
        # Указываем дату загрузки (можно передать как аргумент или использовать текущую)
    if len(sys.argv) > 1:
        load_date = sys.argv[1]
    else:
        # По умолчанию загружаем данные за 2015-01-01
        load_date = "2015-01-01"
    print(f"Processing data for date: {load_date}")
    
    # Создаем правильный JSON для --vars
    vars_json = json.dumps({"load_date": load_date})
    # Запуск трансформаций
    commands = [
        "clean",
        "deps",  # Установка зависимостей
        "run --target raw --models raw",  # Raw слой
        "run --target datavault --models datavault",  # Data Vault слой
        f"run --target pre_marts --models marts --vars '{vars_json}'",
        #"run --target clickhouse --models marts",
        #"run --target clickhouse --models marts",  # Витрины данных
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