-- Создание схем
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS datavault;
CREATE SCHEMA IF NOT EXISTS dds;

-- Хранимые процедуры для Data Vault
CREATE OR REPLACE FUNCTION datavault.update_hub()
RETURNS TRIGGER AS $$
BEGIN
    NEW.load_date = CURRENT_TIMESTAMP;
    NEW.record_source = 'gh_archive';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Таблицы Raw слоя (для первичной загрузки)
CREATE TABLE IF NOT EXISTS raw.github_events (
    id BIGINT,
    event_type VARCHAR(100),
    actor_id BIGINT,
    actor_login VARCHAR(255),
    repo_id BIGINT,
    repo_name VARCHAR(255),
    created_at TIMESTAMP,
    payload JSONB,
    raw_data TEXT,
    loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- Таблицы Data Vault
-- Hub: Пользователи
CREATE TABLE IF NOT EXISTS datavault.hub_users (
    user_hash_key CHAR(32) PRIMARY KEY,
    user_id BIGINT NOT NULL,
    load_date TIMESTAMP NOT NULL,
    record_source VARCHAR(100)
);

-- Hub: Репозитории
CREATE TABLE IF NOT EXISTS datavault.hub_repos (
    repo_hash_key CHAR(32) PRIMARY KEY,
    repo_id BIGINT NOT NULL,
    load_date TIMESTAMP NOT NULL,
    record_source VARCHAR(100)
);

-- Satellite: Детали пользователей
CREATE TABLE IF NOT EXISTS datavault.sat_user_details (
    user_hash_key CHAR(32),
    login VARCHAR(255),
    user_type VARCHAR(50),
    load_date TIMESTAMP,
    record_source VARCHAR(100),
    PRIMARY KEY (user_hash_key, load_date)
);

-- Link: События (связи пользователь-репозиторий)
CREATE TABLE IF NOT EXISTS datavault.link_events (
    event_hash_key CHAR(32) PRIMARY KEY,
    user_hash_key CHAR(32),
    repo_hash_key CHAR(32),
    event_type VARCHAR(100),
    event_date DATE,
    load_date TIMESTAMP,
    record_source VARCHAR(100)
);

-- Индексы
CREATE INDEX idx_raw_created_at ON raw.github_events(created_at);
CREATE INDEX idx_datavault_user_id ON datavault.hub_users(user_id);
CREATE INDEX idx_datavault_repo_id ON datavault.hub_repos(repo_id);
CREATE INDEX idx_datavault_event_type ON datavault.link_events(event_type);

-- Комментарии
COMMENT ON SCHEMA raw IS 'Raw data layer - source data as loaded from S3';
COMMENT ON SCHEMA datavault IS 'Data Vault layer - hubs, satellites, links';
COMMENT ON SCHEMA dds IS 'Dimensional Data Store - ready for marts';

ALTER TABLE raw.github_events ADD PRIMARY KEY (id);

