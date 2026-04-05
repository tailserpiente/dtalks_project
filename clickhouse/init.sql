-- Создание базы данных
CREATE DATABASE IF NOT EXISTS github_marts;

-- Таблица для пользовательских витрин
CREATE TABLE IF NOT EXISTS github_marts.user_activity_daily (
    activity_date Date,
    actor_id UInt64,
    actor_login String,
    total_events UInt32,
    unique_repos UInt32,
    push_events UInt32,
    pr_events UInt32,
    issue_events UInt32,
    star_events UInt32
) ENGINE = MergeTree()
ORDER BY (activity_date, actor_id);

-- Таблица для репозиториев (исправленная версия - без DESC)
CREATE TABLE IF NOT EXISTS github_marts.repo_metrics (
    repo_id UInt64,
    repo_name String,
    unique_contributors UInt32,
    total_events UInt32,
    total_commits UInt32,
    total_prs UInt32,
    total_issues UInt32,
    total_stars UInt32,
    first_activity DateTime,
    last_activity DateTime
) ENGINE = MergeTree()
ORDER BY (repo_id, total_events);  -- Убрали DESC, изменили порядок

-- Альтернативная таблица с сортировкой по убыванию (если нужно)
-- Включаем экспериментальную поддержку обратной сортировки
CREATE TABLE IF NOT EXISTS github_marts.repo_metrics_desc (
    repo_id UInt64,
    repo_name String,
    unique_contributors UInt32,
    total_events UInt32,
    total_commits UInt32,
    total_prs UInt32,
    total_issues UInt32,
    total_stars UInt32,
    first_activity DateTime,
    last_activity DateTime
) ENGINE = MergeTree()
ORDER BY (total_events, repo_id)
SETTINGS allow_experimental_reverse_key = 1;  -- Включаем поддержку обратной сортировки

-- Материализованное представление для агрегации по часам
CREATE MATERIALIZED VIEW IF NOT EXISTS github_marts.hourly_events_stats
ENGINE = SummingMergeTree()
ORDER BY (event_hour, event_type)
AS SELECT
    toStartOfHour(now()) as event_hour,  -- Временное решение
    '' as event_type,
    0 as events_count,
    0 as unique_users,
    0 as unique_repos
WHERE 0;  -- Пустое представление, будет заполняться данными позже

-- Простая таблица для событий
CREATE TABLE IF NOT EXISTS github_marts.events (
    event_id UInt64,
    event_type String,
    actor_id UInt64,
    repo_id UInt64,
    created_at DateTime
) ENGINE = MergeTree()
ORDER BY (created_at, event_type);
