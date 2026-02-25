if [ -n "${GITLAB_PASSWORD:-}" ]; then
  pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$GITLAB_PASSWORD\"}"
  token=$(curl --insecure -ks -X POST -H "Content-Type: application/json" -d "$pwd_data" "https://$GITLAB_FQDN/oauth/token"  | jq -r .access_token)
else
  token=$GITLAB_TOKEN
fi
group_id_project_k=$(curl --insecure -ks -H "Authorization: Bearer $token" "https://$GITLAB_FQDN/api/v4/groups?search=project_k" | jq ".[] | select(.name == \"project_k\") | .id")
target_group="{\"target_group_id\":\"$group_id_project_k\"}"

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

add_ks_admin_to_groups() {
  local user_id=$1
  # Add ks-admin to project_k group and all subgroups as Owner
  member_result=$(curl --insecure -ks -X POST -H "Authorization: Bearer $token" \
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
  ks_admin_password="965db88ebd65b6b5881b88d5ff6ed11e"

  # Check if user already exists via API
  existing_user=$(curl --insecure -s -H "Authorization: Bearer $token" "https://$GITLAB_FQDN/api/v4/users?username=ks-admin" | jq -r '.[0].id // empty')

  if [ -n "$existing_user" ]; then
    add_ks_admin_to_groups "$existing_user"
  else
    # Create new user via API
    user_data="{\"name\":\"KS Admin\",\"username\":\"ks-admin\",\"email\":\"ks-admin@example.com\",\"password\":\"$ks_admin_password\",\"admin\":true,\"skip_confirmation\":true}"
    create_result=$(curl --insecure -s -X POST -H "Authorization: Bearer $token" \
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

configure_gitlab() {
    log_info_block "Настройка репозиториев в Gitlab"
    sleep 30
    if [ "$LDAP_USE" == "y" ]; then
        app_settings="{\"ci_delete_pipelines_in_seconds_limit_human_readable\":\"1 year\",\"default_artifacts_expire_in\":\"14 days\",\"first_day_of_week\":\"1\",\"session_expire_delay\":\"15\",\"suggest_pipeline_enabled\": false,\"whats_new_variant\":\"current_tier\",\"version_check_enabled\":false,\"user_show_add_ssh_key_message\": false,\"usage_ping_enabled\":false,\"update_runner_versions_enabled\":false,\"auto_devops_enabled\": false,\"archive_builds_in_human_readable\":\"1 month\",\"default_branch_protection_defaults\":{\"allowed_to_push\":[{\"access_level\":60}],\"allow_force_push\":false,\"allowed_to_merge\":[{\"access_level\":40}],\"developer_can_initial_push\":false}}"
        curl --insecure -ks -L -X PUT -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$app_settings" \
            "https://$GITLAB_FQDN/api/v4/application/settings"
        curl --insecure -ks -L -X PUT -H "Authorization: Bearer $token" \
            -F "value=true" \
            "https://$GITLAB_FQDN/api/v4/admin/ci/variables/MERGE_REQUEST_APPROVE"
    fi
    ids=$(curl --insecure -ks -L -H "Authorization: Bearer $token" \
        "https://$GITLAB_FQDN/api/v4/projects" | jq -r '.[].id')
    for id in $ids; do
        name=$(curl --insecure -ks -L -H "Authorization: Bearer $token" \
            "https://$GITLAB_FQDN/api/v4/projects/$id" | jq -r '.name')
        log_info "Настройка репозитория $name"
        curl --insecure -ks -L -X POST -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            "https://$GITLAB_FQDN/api/v4/projects/$id/job_token_scope/groups_allowlist" \
            -d "$target_group" | jq
        if [ "$LDAP_USE" == "y" ]; then
            curl --insecure -ks -X PUT -H "Authorization: Bearer $token" \
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
                curl --insecure -ks -X PUT -H "Authorization: Bearer $token" \
                    "https://$GITLAB_FQDN/api/v4/projects/$id" \
                    -d "forking_access_level=enabled" | jq
            fi
            if [ "$name" == "ci" ] || [ "$name" == "keystack" ]; then
                curl --insecure -ks -X PUT -H "Authorization: Bearer $token" \
                    "https://$GITLAB_FQDN/api/v4/projects/$id" \
                    -d "builds_access_level=disabled" \
                    -d "merge_requests_access_level=disabled" | jq
            fi
            if [[ $name == "gitlab-ldap-sync" ]]; then
                curl --insecure -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_URL" -F "value=ldaps://${LDAP_SERVER_URI}:${LDAP_SERVER_PORT}"
                curl --insecure -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_DN" -F "value=${LDAP_BIND_DN}"
                curl --insecure -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_BASE_DN" -F "value=${LDAP_USER_SEARCH_BASEDN}"
                curl --insecure -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=LDAP_GROUP_BASE_DN" -F "value=${LDAP_GROUP_SEARCH_BASEDN}"
                curl --insecure -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=GITLAB_MAINTENANCE_LDAP_GROUP" -F "value=${LDAP_ADMIN_GROUP_DN}"
                LDAP_USER_FILTER="(|(memberof=$LDAP_ADMIN_GROUP_DN)(memberof=$LDAP_AUDITOR_GROUP_DN)(memberof=$LDAP_READER_GROUP_DN))"
                curl --insecure -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -d "{\"key\":\"LDAP_USER_FILTER\",\"value\":\"${LDAP_USER_FILTER}\"}"
                GITLAB_GROUPS="[{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_AUDITOR_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_READER_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k/deployments\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 40},{\"gitlab\": \"project_k/services\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 20}]"
                curl --insecure -X POST -H "Authorization: Bearer $token" \
                "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$id/variables" \
                -F "key=GITLAB_GROUPS" -F "value=${GITLAB_GROUPS}"
            fi
        fi
    done
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
        docker compose -p installer -f $CFG_HOME/compose.yaml up -d --force-recreate gitlab
        # check for gitlab readiness
        echo -n Waiting for GitLab readiness
        while [ "$(curl --insecure -sf https://$GITLAB_FQDN/-/readiness | jq -r .status)"  != "ok" ];
        do
          echo -n .; sleep 5
        done
        echo .
        echo GitLab is Ready!
    fi
    # get gitlab root user token & create a new group
    if [ -n "${GITLAB_PASSWORD:-}" ]; then
        pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$GITLAB_PASSWORD\"}"
        token=$(curl --insecure -ks -X POST -H "Content-Type: application/json" -d "$pwd_data" "https://$GITLAB_FQDN/oauth/token"  | jq -r .access_token)
    else
        token=$GITLAB_TOKEN
    fi
    group_id_project_k=$(curl --insecure -ks -H "Authorization: Bearer $token" "https://$GITLAB_FQDN/api/v4/groups?search=project_k" | jq ".[] | select(.name == \"project_k\") | .id")
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
            PROJECT_ID=$(curl --insecure -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects" | jq ".[] | select(.name == \"gitlab-ldap-sync\") | .id")
            if [ -z "$PROJECT_ID" ]; then
                echo "Project services/gitlab-ldap-sync not found" && exit 1
            fi
        }
        get_project_id
        create_schedule_ldap() {
            local existing_schedule=$(curl --insecure -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every day at 12AM\") | .id")
            if [ -n "$existing_schedule" ]; then
                curl --insecure -ks -X DELETE -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule"
            fi
            local schedule_id=$(curl --insecure -ks -X POST -H "PRIVATE-TOKEN: $PAT" \
                --form description="Sync every day at 12AM" \
                --form ref="master" \
                --form cron="0 0 * * *" \
                --form cron_timezone="UTC" \
                --form active="true" \
                "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq .id)
            curl --insecure -ks -X POST -H "PRIVATE-TOKEN: $PAT" --form "key=ldap" --form "value=true" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$schedule_id/variables"
        }

        create_schedule_gitlab() {
            local existing_schedule=$(curl --insecure -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every 10 minute\") | .id")
            if [ -n "$existing_schedule" ]; then
                curl --insecure -ks -X DELETE -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule"
            fi
            local schedule_id=$(curl --insecure -ks -X POST -H "PRIVATE-TOKEN: $PAT" \
                --form description="Sync every 10 minute" \
                --form ref="master" \
                --form cron="*/10 * * * *" \
                --form cron_timezone="UTC" \
                --form active="true" \
                "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq .id)
            curl --insecure -ks -X POST -H "PRIVATE-TOKEN: $PAT" --form "key=gitlab" --form "value=true" "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$schedule_id/variables"
        }
        create_schedule_ldap
        create_schedule_gitlab
        trigger_pipeline() {
            local existing_trigger=$(curl --insecure -ks -H "PRIVATE-TOKEN: $PAT" \
                "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/triggers" | jq -r '.[] | select(.description == "Automated Trigger") | .token')
            if [ -z "$existing_trigger" ]; then
                existing_trigger=$(curl --insecure --silent --request POST "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/triggers" \
                    --header "PRIVATE-TOKEN: $PAT" \
                    --form description="Automated Trigger" | jq -r '.token')
            fi
            curl --insecure -ks -X POST "https://$GITLAB_FQDN/api/v4/projects/$PROJECT_ID/trigger/pipeline" \
                --form token="$existing_trigger" \
                --form ref="master"
        }
        trigger_pipeline
    fi
}

gitlab_rbac