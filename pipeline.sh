#!/usr/bin/env bash
# =============================================================================
# pipeline.sh — полный пайплайн GitHub Archive за один день
#
# Использование:
#   ./pipeline.sh [YYYY-MM-DD]
#
# Пример:
#   ./pipeline.sh 2015-01-02
#   ./pipeline.sh                  # по умолчанию 2015-01-01
# =============================================================================

set -euo pipefail

# ─── Цвета и функции логирования ──────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_step() { echo -e "\n${CYAN}${BOLD}══ $1 ══${NC}"; }
log_ok()   { echo -e "${GREEN}✓ $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_err()  { echo -e "${RED}✗ $1${NC}"; }

# ─── Параметры ────────────────────────────────────────────────────────────────
DATE="${1:-2015-01-01}"
YEAR=$(echo "$DATE" | cut -d- -f1)
MONTH=$(echo "$DATE" | cut -d- -f2)
DAY=$(echo "$DATE" | cut -d- -f3)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Загружаем переменные из .env
ENV_FILE="$SCRIPT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    log_err ".env файл не найден: $ENV_FILE"; exit 1
fi
# shellcheck disable=SC2046
export $(grep -v '^\s*#' "$ENV_FILE" | grep -v '^\s*$' | xargs)

# Алиасы из .env
MINIO_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_PASS="${MINIO_ROOT_PASSWORD:-minioadmin123}"

BUCKET="github-archive"
MINIO_ALIAS="myminio"
FILES_DIR="$SCRIPT_DIR/github_files"

COMPOSE="docker compose"
DBT_EXEC="$COMPOSE exec -e CLICKHOUSE_PORT=9000 -T dbt"

# ─── Проверки ────────────────────────────────────────────────────────────────
log_step "Проверка окружения"

if ! command -v docker &>/dev/null; then
    log_err "docker не найден"; exit 1
fi
if ! command -v mc &>/dev/null; then
    log_err "mc (MinIO Client) не найден. Установи: wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && sudo mv mc /usr/local/bin/"
    exit 1
fi

# Проверяем что все контейнеры живы
for svc in postgres clickhouse minio dbt; do
    if ! docker compose ps --status running "$svc" 2>/dev/null | grep -q "$svc"; then
        log_warn "Контейнер $svc не запущен. Запускаю docker compose up -d..."
        docker compose up -d
        sleep 10
        break
    fi
done

log_ok "Все контейнеры запущены"
echo "  Дата обработки: ${BOLD}$DATE${NC}"

# ─── Шаг 1: Скачивание файлов с GH Archive ───────────────────────────────────
log_step "Шаг 1/4 — Скачивание GH Archive ($DATE)"

mkdir -p "$FILES_DIR"
cd "$FILES_DIR"

DOWNLOADED=0
SKIPPED=0

for i in $(seq 0 23); do
    FILE="${DATE}-${i}.json.gz"
    if [[ -f "$FILE" ]]; then
        log_warn "  Уже скачан: $FILE"
        ((SKIPPED++)) || true
    else
        echo -n "  Скачиваю час $i... "
        if wget -q --timeout=60 --tries=3 \
            "https://data.gharchive.org/$FILE" -O "$FILE"; then
            echo -e "${GREEN}OK${NC}"
            ((DOWNLOADED++)) || true
        else
            log_err "Не удалось скачать $FILE (час $i), пропускаю"
            rm -f "$FILE"
        fi
    fi
done

log_ok "Скачано: $DOWNLOADED новых файлов, пропущено (уже есть): $SKIPPED"

# ─── Шаг 2: Загрузка в MinIO ─────────────────────────────────────────────────
log_step "Шаг 2/4 — Загрузка в MinIO (s3://$BUCKET/$YEAR/$MONTH/$DAY/)"

# Проверяем alias
if ! mc alias list "$MINIO_ALIAS" &>/dev/null; then
    echo "  Настраиваю mc alias..."
    mc alias set "$MINIO_ALIAS" http://localhost:9000 "$MINIO_USER" "$MINIO_PASS"
fi

# Создаём bucket если нет
mc mb --ignore-existing "$MINIO_ALIAS/$BUCKET" 2>/dev/null || true

UPLOADED=0
for i in $(seq 0 23); do
    FILE="${DATE}-${i}.json.gz"
    S3_PATH="$MINIO_ALIAS/$BUCKET/$YEAR/$MONTH/$DAY/$FILE"

    if [[ ! -f "$FILE" ]]; then
        continue
    fi

    # Проверяем, загружен ли уже файл
    if mc stat "$S3_PATH" &>/dev/null; then
        log_warn "  Уже в MinIO: $FILE"
    else
        echo -n "  Загружаю час $i → MinIO... "
        mc cp "$FILE" "$S3_PATH" --quiet
        echo -e "${GREEN}OK${NC}"
        ((UPLOADED++)) || true
    fi
done

log_ok "Загружено в MinIO: $UPLOADED файлов"

# ─── Шаг 3: PostgreSQL (raw → datavault → marts) ─────────────────────────────
log_step "Шаг 3/4 — Загрузка в PostgreSQL + dbt"

echo "  3а. Загрузка raw событий из MinIO → PostgreSQL..."
$DBT_EXEC python3 /scripts/load_to_postgres.py "$DATE"
log_ok "raw.github_events загружен"

echo ""
echo "  3б. Запуск dbt (raw → datavault → marts)..."
$DBT_EXEC python /scripts/run_dbt.py "$DATE"

# ─── Шаг 4: Экспорт в ClickHouse ─────────────────────────────────────────────
# run_dbt.py уже включает экспорт в ClickHouse — этот шаг для контроля
log_step "Шаг 4/4 — Проверка данных в ClickHouse"

$DBT_EXEC python3 - <<'PYEOF'
import os
from clickhouse_driver import Client

ch = Client(
    host=os.getenv('CLICKHOUSE_HOST', 'clickhouse'),
    port=int(os.getenv('CLICKHOUSE_PORT', '9000')),
    user=os.getenv('CLICKHOUSE_USER', 'clickhouse_user'),
    password=os.getenv('CLICKHOUSE_PASSWORD', 'clickhouse_pass'),
    database=os.getenv('CLICKHOUSE_DB', 'github_marts'),
)

tables = ['user_activity_daily', 'repo_metrics']
for t in tables:
    try:
        count = ch.execute(f'SELECT count() FROM github_marts.{t}')[0][0]
        print(f'  ✓ github_marts.{t}: {count:,} rows')
    except Exception as e:
        print(f'  ✗ github_marts.{t}: {e}')
PYEOF

# ─── Итог ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Пайплайн за $DATE завершён успешно!  ${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
# Определяем доступный адрес (WSL2 + VPN → нужен IP eth1, иначе localhost)
WSL_IP=$(ip addr show eth1 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
HOST="${WSL_IP:-localhost}"

echo -e "  Superset:  ${CYAN}http://$HOST:8088${NC}"
echo -e "  MinIO:     ${CYAN}http://$HOST:9001${NC}"
echo ""
