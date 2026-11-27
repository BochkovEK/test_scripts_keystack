
#!/bin/bash

# ============================================================
# CONFIGURATION
# ============================================================

# Количество успешных цыклов после которых диагностика останавливается
SUCCESSFUL_CYCLES=10

# Обязательные переменные
if [ -z "${stand_name:-}" ]; then
    echo "ERROR: stand_name is not set"
    echo "Set it using: export stand_name=ebochkov-installer-v2"
    exit 1
fi

if [ -z "${GITLAB_TOKEN:-}" ]; then
    echo "ERROR: GITLAB_TOKEN is not set"
    echo "Set it using: export GITLAB_TOKEN=your_token"
    exit 1
fi

# Необязательные переменные
domain="${domain:-vm.lab.itkey.com}"
vault_address="${vault_address:-}"

# Адреса сервисов
gitlab_url="https://gitlab.${stand_name}.${domain}"
netbox_url="https://netbox.${stand_name}.${domain}"
nexus_url="https://nexus.${stand_name}.${domain}"
grafana_url="https://grafana.${stand_name}.${domain}"

# Vault: пользовательский адрес или стандартный FQDN стенда
if [ -n "$vault_address" ]; then
    vault_url="https://${vault_address}/v1/sys/health"
else
    vault_url="https://vault.${stand_name}.${domain}/v1/sys/health"
fi

# GitLab Repository API
gitlab_repo_url="${gitlab_url}/api/v4/projects/8/repository/branches?per_page=10"

# ============================================================
# LOGGING
# ============================================================

RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE="/tmp/lcm-monitor-${RUN_TS}-$$.log"

exec > >(tee -a "$LOG_FILE") 2>&1

echo "===== LCM MONITOR STARTED ====="
echo "START: $(date -u)"
echo "LOG: $LOG_FILE"

# ============================================================
# MONITORING STATE
# ============================================================

GITLAB_OK_STREAK=0
last_gitlab_check=0

# ============================================================
# MAIN MONITORING
# ============================================================

while true; do

    echo
    echo "===== $(date -u) ====="

    SERVICES_FAILED=0

    # --------------------------------------------------------
    # 1. HTTP CHECKS
    # --------------------------------------------------------

    for svc in \
        "gitlab-login|${gitlab_url}/users/sign_in|200" \
        "gitlab-root|${gitlab_url}/|302" \
        "netbox|${netbox_url}/login/|200" \
        "nexus|${nexus_url}/service/rest/v1/status|200" \
        "grafana|${grafana_url}/|302"; do

        NAME="${svc%%|*}"
        REST="${svc#*|}"
        URL="${REST%%|*}"
        EXPECT="${REST##*|}"

        HTTP=$(curl -sk --max-time 5 \
            -o /dev/null -w '%{http_code}' "$URL")

        if [ "$HTTP" = "$EXPECT" ]; then
            printf '[%-14s] (%-3s) OK\n' "$NAME" "$HTTP"
        else
            printf '[%-14s] NOT READY (got %s, expected %s)\n' \
                "$NAME" "$HTTP" "$EXPECT"
            SERVICES_FAILED=1
        fi
    done

    # --------------------------------------------------------
    # 2. VAULT CHECK
    # --------------------------------------------------------

    HTTP=$(curl -sk --max-time 5 \
        -o /dev/null -w '%{http_code}' "$vault_url")

    if [ "$HTTP" = "200" ]; then
        printf '[%-14s] (%-3s) OK\n' "vault" "$HTTP"
    else
        printf '[%-14s] NOT READY (got %s, expected 200)\n' \
            "vault" "$HTTP"
        SERVICES_FAILED=1
    fi

    # При ошибке любого сервиса сбрасываем серию успешных проверок
    if [ "$SERVICES_FAILED" = 1 ]; then
        GITLAB_OK_STREAK=0
    fi

    # --------------------------------------------------------
    # 3. GITLAB REPOSITORY
    # REST API: чтение списка веток через PAT
    # Интервал проверки: 5 секунд
    # --------------------------------------------------------

    NOW=$(date +%s)

    if (( NOW - last_gitlab_check >= 5 )); then

        last_gitlab_check=$NOW

        echo
        echo "===== GITLAB REPOSITORY ====="

        REPO_RESPONSE=$(curl -sk --max-time 10 \
            -w '\n%{http_code}' \
            -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
            "$gitlab_repo_url")

        REPO_HTTP="${REPO_RESPONSE##*$'\n'}"
        REPO_BODY="${REPO_RESPONSE%$'\n'*}"

        if [ "$REPO_HTTP" = "200" ]; then

            printf '[%-14s] (%-3s) OK\n' \
                "gitlab-repo" "$REPO_HTTP"

            if [ "$SERVICES_FAILED" = 0 ]; then
                GITLAB_OK_STREAK=$((GITLAB_OK_STREAK + 1))
            fi

        else

            printf '[%-14s] NOT READY (got %s, expected 200)\n' \
                "gitlab-repo" "$REPO_HTTP"

            echo "$REPO_BODY"
            GITLAB_OK_STREAK=0

        fi

        # ----------------------------------------------------
        # 4. FUNCTIONAL RECOVERY
        # $SUCCESSFUL_CYCLES последовательных успешных цикла
        # ----------------------------------------------------

        if [ "$SERVICES_FAILED" = 0 ] &&
           [ "$REPO_HTTP" = "200" ] &&
           [ "$GITLAB_OK_STREAK" -eq "$SUCCESSFUL_CYCLES" ]; then

           echo
           echo "===== ALL SERVICES AVAILABLE ====="
           echo "===== GITLAB FUNCTIONAL RECOVERY DETECTED ====="
           echo "TIME: $(date -u)"

        fi
    fi

    sleep 2

done
