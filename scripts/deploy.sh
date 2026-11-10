#!/usr/bin/env bash
# Синхронизация статического сайта на целевой веб-сервер
# Настройте DEPLOY_REMOTE, DEPLOY_DIR, SITE_URL и CA_CERT перед запуском.
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="${DEPLOY_REMOTE:?Укажите SSH-цель в DEPLOY_REMOTE}"
REMOTE_DIR="${DEPLOY_DIR:?Укажите каталог назначения в DEPLOY_DIR}"
SITE_URL="${SITE_URL:?Укажите HTTPS-адрес в SITE_URL}"
CA_CERT="${CA_CERT:?Укажите доверенный сертификат в CA_CERT}"
REPO_DIR="$(git rev-parse --show-toplevel)"
cd "$REPO_DIR"

DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

if [[ ! -f "site/index.html" ]]; then
    echo "Ошибка: site/index.html отсутствует, доставка отменена" >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена" >&2
    exit 1
fi

RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ $DRY_RUN -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
fi
rsync "${RSYNC_OPTS[@]}" "site/" "${REMOTE}:${REMOTE_DIR%/}/"

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Пробный запуск: состояние сервера не изменено"
    exit 0
fi

if ! curl -fsS --cacert "$CA_CERT" -o /dev/null "$SITE_URL/"; then
    echo "Ошибка: HTTPS-ресурс недоступен после доставки" >&2
    exit 1
fi
echo "Доставка выполнена, коммит $(git rev-parse --short HEAD)"
