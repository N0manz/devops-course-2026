#!/usr/bin/env bash
set -uo pipefail
PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

: "${TLS_CERTIFICATE:?Укажите путь в TLS_CERTIFICATE}"
: "${SITE_ROOT:?Укажите каталог сайта в SITE_ROOT}"
: "${TLS_KEY:?Укажите путь к закрытому ключу в TLS_KEY}"

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
check "Порт SSH отличен от 22" "yes" "$([[ "$(sudo sshd -T | awk '/^port/{print $2}')" != "22" ]] && echo yes || echo no)"
check "MaxAuthTries равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика по умолчанию для входящего трафика: deny" "deny" "$(sudo ufw status verbose | grep Default | sed -E 's/^Default: ([a-z]+) \(incoming\).*/\1/')"
echo "[3] Веб-сервер"
check "Служба Nginx активна" "active" "$(systemctl is-active nginx)"
check "Конфигурация Nginx корректна" "0" "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действителен не менее заданного срока" "0" "$(openssl x509 -checkend $(( ${CERT_DAYS:-30} * 24 * 3600 )) -noout -in "$TLS_CERTIFICATE" >/dev/null; echo $?)"
check "В каталоге сайта нет файлов, доступных всем для записи" "0" "$(find "$SITE_ROOT" -perm -o+w | wc -l)"
check "Права закрытого ключа равны 600" "600" "$(sudo stat -c '%a' "$TLS_KEY")"
echo "[5] Контейнеризация"
: "${APP_DIRECTORY:?Укажите каталог проекта Compose в APP_DIRECTORY}"
APP_ENV_FILE="${APP_ENV_FILE:-$APP_DIRECTORY/.env}"
check "Служба Docker активна" "active" "$(systemctl is-active docker)"
DB_CONTAINER="$(docker compose --project-directory "$APP_DIRECTORY" ps -q db)"
check "Контейнер СУБД находится в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER" 2>/dev/null)"
check "Порты 5000 и 5432 не прослушиваются вне 127.0.0.1" "0" "$(ss -tln | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\\.0\\.0\\.1:/ {n++} END {print n+0}')"
check "Права файла окружения равны 600" "600" "$(stat -c '%a' "$APP_ENV_FILE")"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
