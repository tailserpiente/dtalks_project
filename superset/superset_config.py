import os

SECRET_KEY = os.environ.get('SUPERSET_SECRET_KEY', 'your_secret_key_here')

SQLALCHEMY_DATABASE_URI = f"postgresql+psycopg2://{os.getenv('POSTGRES_USER')}:{os.getenv('POSTGRES_PASSWORD')}@postgres:5432/{os.getenv('POSTGRES_DB')}"

# ClickHouse подключение
CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
CLICKHOUSE_PORT = 8123
CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'clickhouse_user')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', 'clickhouse_pass')

# Настройка кэша
CACHE_CONFIG = {
    'CACHE_TYPE': 'RedisCache',
    'CACHE_DEFAULT_TIMEOUT': 300,
    'CACHE_KEY_PREFIX': 'superset_',
    'CACHE_REDIS_HOST': 'redis',
    'CACHE_REDIS_PORT': 6379,
    'CACHE_REDIS_DB': 1,
}

FEATURE_FLAGS = {
    'ENABLE_TEMPLATE_PROCESSING': True,
    'DASHBOARD_NATIVE_FILTERS': True,
    'DASHBOARD_CROSS_FILTERS': True,
}

TALISMAN_ENABLED = False