#!/bin/bash
set -e
set -u
set -o errtrace
set -o pipefail
# set -x

log_info() {
    # Вывод зеленым цветом
    echo -e "\033[1;32m$1\033[0m"
}

log_info_block() {
    echo "================================================="
    # Вывод зеленым цветом
    echo -e "\033[1;32m$1\033[0m"
    echo "================================================="
}

exit_on_error() {
    # Вывод красным цветом
    echo -e "\033[1;31m$1\033[0m" >&2
    exit 1
}

check_file_exists() {
    if [ ! -f "$1" ]; then
        exit_on_error "Файл $1 не найден."
    fi
}

check_directory_exists() {
    if [ ! -d "$1" ]; then
        exit_on_error "Директория $1 не найдена."
    fi
}

# Validate LDAP DN format
# Returns 0 if valid, 1 if invalid (with warnings printed to stderr)
validate_dn() {
  local dn="$1"
  local issues=()

  # Empty check
  if [[ -z "$dn" ]]; then
    return 1
  fi

  # Basic format check: should contain at least one "="
  if [[ ! "$dn" =~ = ]]; then
    issues+=("Missing '=' character - DN should contain attribute=value pairs")
  fi

  # Check for common LDAP attribute prefixes (case insensitive)
  # Valid examples: dc=, ou=, cn=, uid=, o=, l=, st=, c=
  if ! echo "$dn" | grep -qiE '(dc|ou|cn|uid|o|l|st|c)='; then
    issues+=("No recognized LDAP attributes found (dc, ou, cn, uid, etc.)")
  fi

  # Check for spaces around equals (common mistake)
  if [[ "$dn" =~ [[:space:]]=[[:space:]] ]] || [[ "$dn" =~ =[[:space:]] ]] || [[ "$dn" =~ [[:space:]]= ]]; then
    issues+=("Spaces around '=' detected - should be attribute=value without spaces")
  fi

  # Check for missing commas between components
  if [[ "$dn" =~ [a-zA-Z][a-zA-Z][[:space:]][a-zA-Z][a-zA-Z]= ]]; then
    issues+=("Missing comma between DN components")
  fi

  # Check for double commas
  if [[ "$dn" =~ ,, ]]; then
    issues+=("Double comma detected")
  fi

  # Check for trailing/leading commas
  if [[ "$dn" =~ ^, ]] || [[ "$dn" =~ ,$ ]]; then
    issues+=("Leading or trailing comma detected")
  fi

  # If there are issues, print them
  if [[ ${#issues[@]} -gt 0 ]]; then
    echo "DN validation issues:" >&2
    for issue in "${issues[@]}"; do
      echo "  - $issue" >&2
    done
    echo "Example formats: cn=admin,dc=example,dc=com  ou=groups,dc=company,dc=local" >&2
    return 1
  fi

  return 0
}

# Read and validate LDAP DN with user confirmation
read_and_validate_dn() {
  local var_name="$1"
  local prompt="$2"
  local value

  while true; do
    read -rp "$prompt: " value
    if [[ -z "$value" ]]; then
      echo "Value is required." >&2
      continue
    fi

    # Validate the DN
    if validate_dn "$value"; then
      # Valid DN, accept it
      echo "  [OK] DN format looks valid"
      eval "$var_name='$value'"
      return 0
    else
      # Invalid DN, ask if they want to retry or proceed anyway
      local choice
      read -rp "DN validation failed. (r)etry or (p)roceed anyway? [r/p]: " choice
      case "${choice,,}" in
        ''|r|retry)
          echo "Please re-enter the value..."
          continue
          ;;
        p|proceed)
          echo "Proceeding with current value..."
          eval "$var_name='$value'"
          return 0
          ;;
      esac
    fi
  done
}

configure_gitlab() {
    log_info_block "Настройка репозиториев в Gitlab"
    if [ "$LDAP_USE" == "y" ]; then
        app_settings="{\"ci_delete_pipelines_in_seconds_limit_human_readable\":\"1 year\",\"default_artifacts_expire_in\":\"14 days\",\"first_day_of_week\":\"1\",\"session_expire_delay\":\"15\",\"suggest_pipeline_enabled\": false,\"whats_new_variant\":\"current_tier\",\"version_check_enabled\":false,\"user_show_add_ssh_key_message\": false,\"usage_ping_enabled\":false,\"update_runner_versions_enabled\":false,\"auto_devops_enabled\": false,\"archive_builds_in_human_readable\":\"1 month\",\"default_branch_protection_defaults\":{\"allowed_to_push\":[{\"access_level\":60}],\"allow_force_push\":false,\"allowed_to_merge\":[{\"access_level\":40}],\"developer_can_initial_push\":false}}"
        curl -ks -L -X PUT -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$app_settings" \
            "https://$GITLAB_FQDN/api/v4/application/settings"
        curl -ks -L -X PUT -H "Authorization: Bearer $token" \
            -F "value=true" \
            "https://$GITLAB_FQDN/api/v4/admin/ci/variables/MERGE_REQUEST_APPROVE"
    fi
    ids=$(curl -ks -L -H "Authorization: Bearer $token" \
        "https://$GITLAB_FQDN/api/v4/projects" | jq -r '.[].id')
    for id in $ids; do
        name=$(curl -ks -L -H "Authorization: Bearer $token" \
            "https://$GITLAB_FQDN/api/v4/projects/$id" | jq -r '.name')
        log_info "Настройка репозитория $name"
        curl -ks -L -X POST -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            "https://$GITLAB_FQDN/api/v4/projects/$id/job_token_scope/groups_allowlist" \
            -d "$target_group" | jq
        if [ "$LDAP_USE" == "y" ]; then
            curl -ks -X PUT -H "Authorization: Bearer $token" \
            "https://$GITLAB_FQDN/api/v4/projects/$id" \
            -d "only_allow_merge_if_pipeline_succeeds=true" \
            -d "only_allow_merge_if_all_discussions_are_resolved=true" \
            -d "container_registry_access_level=disabled" \
            -d "monitor_access_level=disabled" \
            -d "wiki_access_level=disabled" \
            -d "security_and_compliance_access_level=disabled" \
            -d "releases_access_level=disabled" \
            -d "model_registry_access_level=disabled" \
            -d "feature_flags_access_level=disabled" \
            -d "snippets_access_level=disabled" \
            -d "model_experiments_access_level=disabled" \
            -d "analytics_access_level=disabled" \
            -d "issues_access_level=disabled" \
            -d "forking_access_level=disabled" \
            -d "environments_access_level=disabled" | jq
            if [ "$name" == "region1" ]; then
                curl -ks -X PUT -H "Authorization: Bearer $token" \
                    "https://$GITLAB_FQDN/api/v4/projects/$id" \
                    -d "forking_access_level=enabled" | jq
            fi
            if [ "$name" == "ci" ] || [ "$name" == "keystack" ]; then
                curl -ks -X PUT -H "Authorization: Bearer $token" \
                    "https://$GITLAB_FQDN/api/v4/projects/$id" \
                    -d "builds_access_level=disabled" \
                    -d "merge_requests_access_level=disabled" | jq
            fi
            if [[ $name == "gitlab-ldap-sync" ]]; then
                curl -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_URL" -F "value=ldaps://${LDAP_SERVER_URI}:${LDAP_SERVER_PORT}"
                curl -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_DN" -F "value=${LDAP_BIND_DN}"
                curl -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_BASE_DN" -F "value=${LDAP_USER_SEARCH_BASEDN}"
                curl -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_GROUP_BASE_DN" -F "value=${LDAP_GROUP_SEARCH_BASEDN}"
                curl -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=GITLAB_MAINTENANCE_LDAP_GROUP" -F "value=${LDAP_ADMIN_GROUP_DN}"
                LDAP_USER_FILTER="(|(memberof=$LDAP_ADMIN_GROUP_DN)(memberof=$LDAP_AUDITOR_GROUP_DN)(memberof=$LDAP_READER_GROUP_DN))"
                curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -d "{\"key\":\"LDAP_USER_FILTER\",\"value\":\"${LDAP_USER_FILTER}\"}"
                GITLAB_GROUPS="[{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_AUDITOR_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_READER_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k/deployments\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 40},{\"gitlab\": \"project_k/services\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 20}]"
                curl -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=GITLAB_GROUPS" -F "value=${GITLAB_GROUPS}"
            fi
        fi
    done
}

add_ks_admin_to_groups() {
  local user_id=$1
  # Add ks-admin to project_k group and all subgroups as Owner
  member_result=$(curl -ks -X POST -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "{\"user_id\":\"$user_id\",\"access_level\":50}" \
    "https://$GITLAB_FQDN/api/v4/groups/$group_id_project_k/members")
  member_id=$(echo "$member_result" | jq -r '.id // empty')
  if [ -n "$member_id" ]; then
      log_info "ks-admin added to group $group_id_project_k successfully"
  else
      log_info "Warning: Could not add ks-admin to group $group_id_project_k: $(echo "$member_result" | jq -r '.message // "Unknown error"')"
  fi
}

create_ks_admin_user() {
  ks_admin_password=$(openssl rand -hex 16)

  # Check if user already exists via API
  existing_user=$(curl -s -H "Authorization: Bearer $token" "https://$GITLAB_FQDN/api/v4/users?username=ks-admin" | jq -r '.[0].id // empty')

  if [ -n "$existing_user" ]; then
    add_ks_admin_to_groups "$existing_user"
  else
    # Create new user via API
    user_data="{\"name\":\"KS Admin\",\"username\":\"ks-admin\",\"email\":\"ks-admin@example.com\",\"password\":\"$ks_admin_password\",\"admin\":true,\"skip_confirmation\":true}"
    create_result=$(curl -s -X POST -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$user_data" \
      "https://$GITLAB_FQDN/api/v4/users")

    user_id=$(echo "$create_result" | jq -r '.id // empty')
    if [ -n "$user_id" ]; then
      log_info "User ks-admin created successfully"
      add_ks_admin_to_groups "$user_id"
      docker compose -f $CFG_HOME/compose.yaml exec vault /bin/sh -c "vault kv patch -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/secrets/accounts gitlab_ks_admin_password="$ks_admin_password""
    else
      exit_on_error "Error creating user ks-admin: $(echo "$create_result" | jq -r '.message // "Unknown error"')"
    fi
  fi
}

prompt_var() {
  local VAR_NAME="$1" KS_ENV="$2" PROMPT="$3" DEFAULT="$4" FLAGS="${5:-}"
  local REQUIRED="" SECRET="" MINLEN=0
  local tmp ans

  # Parse flags
  IFS=',' read -r -a _flags <<<"$FLAGS"
  for f in "${_flags[@]}"; do
    case "$f" in
      required) REQUIRED=1 ;;
      secret)   SECRET=1 ;;
      minlen=*) MINLEN="${f#minlen=}" ;;
    esac
  done

  # If KS_ env provided, use it
  if [[ -n "${!KS_ENV-}" ]]; then
    printf -v "$VAR_NAME" '%s' "${!KS_ENV}"
    return
  fi

  # Otherwise, prompt interactively
  while :; do
    if [[ -n "$SECRET" ]]; then
      # secret prompt (no echo)
      read -r -s -p "${PROMPT} [hidden]: " ans; printf '\n'
      # apply default only if empty and default provided
      if [[ -z "$ans" && -n "$DEFAULT" ]]; then ans="$DEFAULT"; fi
    else
      read -r -p "${PROMPT} ${DEFAULT:+[$DEFAULT]}: " ans
      if [[ -z "$ans" && -n "$DEFAULT" ]]; then ans="$DEFAULT"; fi
    fi

    # Required check
    if [[ -n "$REQUIRED" && -z "$ans" ]]; then
      echo "Value is required." >&2; continue
    fi

    # Min length check
    if (( MINLEN > 0 )) && (( ${#ans} < MINLEN )); then
      echo "Value must be at least ${MINLEN} characters." >&2; continue
    fi

    break
  done

  printf -v "$VAR_NAME" '%s' "$ans"
}

# Validate LDAP DN format
# Returns 0 if valid, 1 if invalid (with warnings printed to stderr)
validate_dn() {
  local dn="$1"
  local issues=()

  # Empty check
  if [[ -z "$dn" ]]; then
    return 1  # Will be caught by required flag
  fi

  # Basic format check: should contain at least one "="
  if [[ ! "$dn" =~ = ]]; then
    issues+=("Missing '=' character - DN should contain attribute=value pairs")
  fi

  # Check for common LDAP attribute prefixes (case insensitive)
  # Valid examples: dc=, ou=, cn=, uid=, o=, l=, st=, c=
  if ! echo "$dn" | grep -qiE '(dc|ou|cn|uid|o|l|st|c)='; then
    issues+=("No recognized LDAP attributes found (dc, ou, cn, uid, etc.)")
  fi

  # Check for spaces around equals (common mistake)
  if [[ "$dn" =~ [[:space:]]=[[:space:]] ]] || [[ "$dn" =~ =[[:space:]] ]] || [[ "$dn" =~ [[:space:]]= ]]; then
    issues+=("Spaces around '=' detected - should be attribute=value without spaces")
  fi

  # Check for missing commas between components
  if [[ "$dn" =~ [a-zA-Z][a-zA-Z][[:space:]][a-zA-Z][a-zA-Z]= ]]; then
    issues+=("Missing comma between DN components")
  fi

  # Check for double commas
  if [[ "$dn" =~ ,, ]]; then
    issues+=("Double comma detected")
  fi

  # Check for trailing/leading commas
  if [[ "$dn" =~ ^, ]] || [[ "$dn" =~ ,$ ]]; then
    issues+=("Leading or trailing comma detected")
  fi

  # If there are issues, print them
  if [[ ${#issues[@]} -gt 0 ]]; then
    echo "DN validation issues:" >&2
    for issue in "${issues[@]}"; do
      echo "  - $issue" >&2
    done
    echo "Example formats: cn=admin,dc=example,dc=com  ou=groups,dc=company,dc=local" >&2
    return 1
  fi

  return 0
}

# Prompt for LDAP DN with validation
# prompt_dn VAR_NAME KS_ENV_NAME "Prompt text" "default" flags
prompt_dn() {
  local VAR_NAME="$1" KS_ENV="$2" PROMPT="$3" DEFAULT="$4" FLAGS="${5:-}"
  local ans

  # If KS_ env provided, use it without validation
  if [[ -n "${!KS_ENV-}" ]]; then
    printf -v "$VAR_NAME" '%s' "${!KS_ENV}"
    return
  fi

  # Interactive prompt with validation loop
  while :; do
    # Use prompt_var to get the input (handles required, etc.)
    prompt_var "$VAR_NAME" "$KS_ENV" "$PROMPT" "$DEFAULT" "$FLAGS"
    ans="${!VAR_NAME}"

    # Validate the DN
    if validate_dn "$ans"; then
      # Valid DN, accept it
      echo "  [OK] DN format looks valid"
      return 0
    else
      # Invalid DN, ask if they want to retry or proceed anyway
      local choice
      read -r -p "DN validation failed. (r)etry or (p)roceed anyway? [r/p]: " choice
      case "${choice,,}" in
        ''|r|retry)
          echo "Please re-enter the value..."
          continue
          ;;
        p|proceed)
          echo "Proceeding with current value..."
          return 0
          ;;
        *)
          echo "Please answer 'r' (retry) or 'p' (proceed)." >&2
          continue
          ;;
      esac
    fi
  done
}

# Normalize yes/no with default (n/Y), returns var set to y or n
prompt_yn() {
  local VAR_NAME="$1" KS_ENV="$2" PROMPT="$3" DEFAULT="${4:-n}" ans
  if [[ -n "${!KS_ENV-}" ]]; then
    ans="${!KS_ENV}"
  else
    read -r -p "$PROMPT [${DEFAULT}]: " ans
    ans="${ans:-$DEFAULT}"
  fi
  case "${ans,,}" in
    y|yes)  printf -v "$VAR_NAME" 'y' ;;
    n|no|'') printf -v "$VAR_NAME" 'n' ;;
    *) echo "Please answer y or n." >&2; prompt_yn "$@"; return ;;
  esac
}

dialog_rbac() {
# LDAP use (y/n)
prompt_yn LDAP_USE KS_LDAP_USE "Enable auth LDAP for Gitlab and Netbox y/n" "n"
export LDAP_USE

if [[ "$LDAP_USE" == "y" ]]; then
  # LDAP configuration with validation
  # Non-DN fields
  prompt_var LDAP_SERVER_URI        KS_LDAP_SERVER_URI        "Enter the LDAP Server URI"                    ""    required
  prompt_var LDAP_SERVER_PORT       KS_LDAP_SERVER_PORT       "Enter the LDAP Server Port"                   "636" ""

  # DN fields with validation
  prompt_dn  LDAP_BIND_DN           KS_LDAP_BIND_DN           "Enter the LDAP BIND DN"                       ""    required
  prompt_var LDAP_BIND_PASSWORD     KS_LDAP_BIND_PASSWORD     "Enter the LDAP BIND Password"                 ""    "required,secret"
  prompt_dn  LDAP_USER_SEARCH_BASEDN KS_LDAP_USER_SEARCH_BASEDN "Enter the LDAP USER SEARCH BASEDN"          ""    required
  prompt_dn  LDAP_GROUP_SEARCH_BASEDN KS_LDAP_GROUP_SEARCH_BASEDN "Enter the LDAP GROUP SEARCH BASEDN"       ""    required
  prompt_dn  LDAP_READER_GROUP_DN   KS_LDAP_READER_GROUP_DN   "Enter the LDAP GROUP for reader role"         ""    required
  prompt_dn  LDAP_AUDITOR_GROUP_DN  KS_LDAP_AUDITOR_GROUP_DN  "Enter the LDAP GROUP for auditor role"        ""    required
  prompt_dn  LDAP_ADMIN_GROUP_DN    KS_LDAP_ADMIN_GROUP_DN    "Enter the LDAP GROUP for admin role"          ""    required
fi
}

gitlab_rbac() {
    log_info_block "Настройка Gitlab"
    if [ "$LDAP_USE" == "y" ]; then
        [ ! -f certs/ldaps.pem ] && echo "Chain certificates for LDAPs not found in certs" && exit 1
        cp certs/ldaps.pem $CA_HOME/cert/ldaps.pem
        cp certs/ldaps.pem /$GITLAB_HOME/config/trusted-certs/ldaps.pem
        cat certs/ldaps.pem >> $GITLAB_RUNNER_HOME/certs/ca.crt
        sed -i "s/gitlab_rails\['ldap_enabled'\] = false/gitlab_rails['ldap_enabled'] = true/" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-SERVER-PORT|$LDAP_SERVER_PORT|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-BIND-PASSWORD|$LDAP_BIND_PASSWORD|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-READER-GROUP-DN|$LDAP_READER_GROUP_DN|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-AUDITOR-GROUP-DN|$LDAP_AUDITOR_GROUP_DN|" $CFG_HOME/compose.yaml
        sed -i "s|LDAP-ADMIN-GROUP-DN|$LDAP_ADMIN_GROUP_DN|" $CFG_HOME/compose.yaml
docker exec -i \
  -e LDAP_BIND_PASSWORD="$LDAP_BIND_PASSWORD" \
  -e LDAP_BIND_DN="$LDAP_BIND_DN" \
  gitlab /bin/bash <<'EOF'
cat <<YAML | gitlab-rake gitlab:ldap:secret:write
main:
  password: "$LDAP_BIND_PASSWORD"
  bind_dn: "$LDAP_BIND_DN"
YAML
EOF
        sed -i "/bind_dn/d" $CFG_HOME/compose.yaml
        sed -i "/password/d" $CFG_HOME/compose.yaml
        docker exec gitlab gitlab-rails runner 'ApplicationSetting.last.update(signup_enabled: false)'
        docker exec gitlab gitlab-rails runner 'ApplicationSetting.last.update(remember_me_enabled: false)'
        docker compose -f $CFG_HOME/compose.yaml up -d --force-recreate gitlab
        # check for gitlab readiness
        echo -n Waiting for GitLab readiness
        while [ "$(curl -sf https://$GITLAB_FQDN/-/readiness | jq -r .status)"  != "ok" ];
        do
          echo -n .; sleep 5
        done
        echo .
        echo GitLab is Ready!
    fi
    # get gitlab root user token & create a new group
    if [ -n "${GITLAB_PASSWORD:-}" ]; then
        pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$GITLAB_PASSWORD\"}"
        token=$(curl -ks -X POST -H "Content-Type: application/json" -d "$pwd_data" "https://$GITLAB_FQDN/oauth/token"  | jq -r .access_token)
    else
        token=$GITLAB_TOKEN
    fi
    group_id_project_k=$(curl -ks -H "Authorization: Bearer $token" "https://$GITLAB_FQDN/api/v4/groups?search=project_k" | jq ".[] | select(.name == \"project_k\") | .id")
    target_group="{\"target_group_id\":\"$group_id_project_k\"}"
    configure_gitlab
    create_ks_admin_user

    if [ "$LDAP_USE" == "y" ]; then
        generate_pat() {
            local existing_pat=$(docker exec gitlab gitlab-rails runner "
                user = User.find_by(username: 'ks-admin')
                token = user.personal_access_tokens.find_by(name: 'PAT')
                if token
                  puts token.id
                end
              ")
            if [ -n "$existing_pat" ]; then
                docker exec gitlab gitlab-rails runner "
                    user = User.find_by(username: 'ks-admin')
                    token = user.personal_access_tokens.find_by(id: $existing_pat)
                    token.destroy if token"
            fi
            PAT=$(docker exec gitlab gitlab-rails runner "
                require 'securerandom'
                user = User.find_by(username: 'ks-admin')
                token_plain = SecureRandom.hex(20)
                token = user.personal_access_tokens.create!(
                  name: 'PAT',
                  scopes: ['api', 'sudo'],
                  expires_at: Time.current + 1.year
                )
                token.set_token(token_plain)
                token.save!
                puts token.token"
            )
            if [ -z "$PAT" ]; then
                echo "PAT creation error" && exit 1
            fi
        }
        generate_pat
        disable_root_user() {
            docker exec gitlab gitlab-rails runner "
                root_user = User.find_by(username: 'root')
                if root_user
                    root_user.update!(state: 'blocked')
                    puts 'Root user has been disabled successfully'
                else
                    puts 'Root user not found'
                end
            "
        }
        disable_root_user
        docker compose -f "$CFG_HOME/compose.yaml" exec \
          -e GITLAB_TOKEN="$PAT" \
          -e LDAP_PASSWORD="$LDAP_BIND_PASSWORD" \
          vault /bin/sh -c 'vault kv patch -mount=secret_v2 deployments/'"$GITLAB_FQDN"'/secrets/accounts GITLAB_TOKEN="$GITLAB_TOKEN" LDAP_PASSWORD="$LDAP_PASSWORD"'
        get_project_id() {
            PROJECT_ID=$(curl -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects" | jq ".[] | select(.name == \"gitlab-ldap-sync\") | .id")
            if [ -z "$PROJECT_ID" ]; then
                echo "Project services/gitlab-ldap-sync not found" && exit 1
            fi
        }
        get_project_id
        create_schedule_ldap() {
            local existing_schedule=$(curl -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every day at 12AM\") | .id")
            if [ -n "$existing_schedule" ]; then
                curl -ks -X DELETE -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule"
            fi
            local schedule_id=$(curl -ks -X POST -H "PRIVATE-TOKEN: $PAT" \
                --form description="Sync every day at 12AM" \
                --form ref="master" \
                --form cron="0 0 * * *" \
                --form cron_timezone="UTC" \
                --form active="true" \
                "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq .id)
            curl -ks -X POST -H "PRIVATE-TOKEN: $PAT" --form "key=ldap" --form "value=true" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$schedule_id/variables"
        }

        create_schedule_gitlab() {
            local existing_schedule=$(curl -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every 10 minute\") | .id")
            if [ -n "$existing_schedule" ]; then
                curl -ks -X DELETE -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule"
            fi
            local schedule_id=$(curl -ks -X POST -H "PRIVATE-TOKEN: $PAT" \
                --form description="Sync every 10 minute" \
                --form ref="master" \
                --form cron="*/10 * * * *" \
                --form cron_timezone="UTC" \
                --form active="true" \
                "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq .id)
            curl -ks -X POST -H "PRIVATE-TOKEN: $PAT" --form "key=gitlab" --form "value=true" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$schedule_id/variables"
        }
        create_schedule_ldap
        create_schedule_gitlab
        trigger_pipeline() {
            local existing_trigger=$(curl -ks -H "PRIVATE-TOKEN: $PAT" \
                "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/triggers" | jq -r '.[] | select(.description == "Automated Trigger") | .token')
            if [ -z "$existing_trigger" ]; then
                existing_trigger=$(curl --silent --request POST "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/triggers" \
                    --header "PRIVATE-TOKEN: $PAT" \
                    --form description="Automated Trigger" | jq -r '.token')
            fi
            curl -ks -X POST "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/trigger/pipeline" \
                --form token="$existing_trigger" \
                --form ref="master"
        }
        trigger_pipeline
    fi
}

netbox_rbac() {
    log_info_block "Настройка Netbox"
    if [ "$LDAP_USE" == "y" ]; then
        sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI|" $NETBOX_HOME/env/netbox.env
        sed -i "s|LDAP-SERVER-PORT|$LDAP_SERVER_PORT|" $NETBOX_HOME/env/netbox.env
        sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN|" $NETBOX_HOME/env/netbox.env
        sed -i "s|LDAP-BIND-PASSWORD|$LDAP_BIND_PASSWORD|" $NETBOX_HOME/env/netbox.env
        sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN|" $NETBOX_HOME/env/netbox.env
        sed -i "s|LDAP-GROUP-SEARCH-BASEDN|$LDAP_GROUP_SEARCH_BASEDN|" $NETBOX_HOME/env/netbox.env
        sed -i "s|LDAP-READER-GROUP-DN|$LDAP_READER_GROUP_DN|g" $NETBOX_HOME/netbox/configuration/ldap/extra.py
        sed -i "s|LDAP-AUDITOR-GROUP-DN|$LDAP_AUDITOR_GROUP_DN|" $NETBOX_HOME/netbox/configuration/ldap/extra.py
        sed -i "s|LDAP-ADMIN-GROUP-DN|$LDAP_ADMIN_GROUP_DN|" $NETBOX_HOME/netbox/configuration/ldap/extra.py
        cp certs/ldaps.pem $NETBOX_HOME/netbox/configuration/ldaps.pem
        docker compose -f $CFG_HOME/netbox-compose.yml up -d
    fi
}

main() {
    log_info_block $'\n\n'"*** KeyStack enable RBAC ***"$'\n\n'
    required_vars=("GITLAB_NAME" "NEXUS_NAME" "DOMAIN" "CFG_HOME" "CA_HOME" "NETBOX_HOME" "GITLAB_RUNNER_HOME")
    for var in "${required_vars[@]}"; do
      if [ -z "${!var:-}" ]; then
        exit_on_error "Переменная окружения $var не задана"
      fi
    done
    for cmd in curl jq git docker openssl; do
      command -v $cmd >/dev/null 2>&1 || exit_on_error "Не установлена зависимость: $cmd"
    done
    NEXUS_FQDN=$NEXUS_NAME.$DOMAIN
    DOCKER_FQDN=$NEXUS_FQDN
    NEXUS_USER=admin
    GITLAB_FQDN=$GITLAB_NAME.$DOMAIN
    dialog_rbac
    gitlab_rbac
    netbox_rbac
}

main "$@"