#!/bin/bash
#----------------------------------------#
#    * KeyStack Installation Script *    #
# Originally written by Sergey Igoshkin  #
#             - = 2024 =-                #
#----------------------------------------#

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

check_retrieved_value() {
    local checked_var_name="$1"
    local checked_var_value="$2"

    if [[ "$checked_var_value" == 'null' || -z "$checked_var_value" ]]; then
        exit_on_error "Ошибка при получении значения переменной: ${checked_var_name} = ${checked_var_value}"
    fi
}

get_kubectl_secret_data() {
    local secret_name="$1"
    local secret_key="$2"
    local namespace="$3"
    local kubectl_output

    secret_key=$(echo "$secret_key" | sed 's/\./\\./g')
    kubectl_output=$(kubectl get secret "${secret_name}" -n "${namespace}" -o jsonpath="{.data.${secret_key}}")

    if [[ $? -ne 0 ]]; then
        exit_on_error "Не удалось получить секрет ${secret_name} или ключ ${secret_key} отсутствует"
    fi
    echo "$kubectl_output" | base64 --decode
}

get_secret() {
    # Имя секрета жёстко задано как "ca-tls",
    # поэтому не требует получения из "charts-config.yaml"
    # Получаю из Kubernetes, проверяю, присваиваю значения переменным
    from_k8s_ca_crt=$(get_kubectl_secret_data "ca-tls" "ca.crt" "lcm-root-ca")
    from_k8s_ca_key=$(get_kubectl_secret_data "ca-tls" "ca.key" "lcm-root-ca")
    ca_pem=$(echo -en "${from_k8s_ca_key}\n${from_k8s_ca_crt}")

    # Получаем секреты для Нексус
    local nexus_chart_name='nexus3'
    local nexus_secret_namespace=$(yq -r ".charts[] | select(.name == \"${nexus_chart_name}\") | .namespace" "$config_file")
    local nexus_chart_chart_values=$(yq ".charts[] | select(.name == \"${nexus_chart_name}\") | .chart_values" "$config_file")
    local nexus_chart_custom_values=$(yq ".charts[] | select(.name == \"${nexus_chart_name}\") | .custom_values" "$config_file")
    local nexus_chart_k8s_secret=$(echo "$nexus_chart_custom_values" | yq '.apt-hosted-repos.k8s-secret')
    local nexus_chart_gpg_public_key=$(echo "$nexus_chart_custom_values" | yq '.apt-hosted-repos.gpg-public-key')
    local nexus_chart_root_password_secret_name=$(echo "$nexus_chart_chart_values" | yq '.rootPassword.secret')
    local nexus_chart_root_password_key=$(echo "$nexus_chart_chart_values" | yq '.rootPassword.key')
    nexus_chart_fqdn=$(echo "$nexus_chart_chart_values" | yq '.ingress.hosts[0]')
      nexus_chart_fqdn_docker_registry=$(echo "$nexus_chart_chart_values" | yq '.ingress.tls[] | select(.secretName == "docker-tls") | .hosts[0]')
    nexus_from_k8s_admin_password=$(get_kubectl_secret_data "${nexus_chart_root_password_secret_name}" "${nexus_chart_root_password_key}" "${nexus_secret_namespace}")
    nexus_from_k8s_gpg_public_key=$(get_kubectl_secret_data "${nexus_chart_k8s_secret}" "${nexus_chart_gpg_public_key}" "${nexus_secret_namespace}")

    # Получаем секреты для Нетбокс
    local netbox_chart_name='netbox'
    local netbox_namespace=$(yq ".charts[] | select(.name == \"${netbox_chart_name}\") | .namespace" "$config_file")
    local netbox_from_k8s_secret_name='netbox-superuser'
    local netbox_chart_chart_values=$(yq ".charts[] | select(.name == \"${netbox_chart_name}\") | .chart_values" "$config_file")
    netbox_chart_fqdn_arr=($(echo "$netbox_chart_chart_values" | yq '.. | select(has("ingress")).ingress.tls[].hosts[]'))
    netbox_from_k8s_api_token=$(get_kubectl_secret_data "$netbox_from_k8s_secret_name" "api_token" "${netbox_namespace}")
    netbox_from_k8s_password=$(get_kubectl_secret_data "$netbox_from_k8s_secret_name" "password" "${netbox_namespace}")
    netbox_from_k8s_username=$(get_kubectl_secret_data "$netbox_from_k8s_secret_name" "username" "${netbox_namespace}")

    # Получаем секреты для Гитлаб
    local gitlab_chart_name='gitlab'
    local gitlab_namespace=$(yq ".charts[] | select(.name == \"${gitlab_chart_name}\") | .namespace" "$config_file")
    local gitlab_from_k8_initial_root_password='gitlab-gitlab-initial-root-password'
    local gitlab_from_k8_initial_root_password_key='password'
    local gitlab_chart_chart_values=$(yq ".charts[] | select(.name == \"${gitlab_chart_name}\") | .chart_values" "$config_file")
    gitlab_chart_domain_name=$(echo "$gitlab_chart_chart_values" | yq '.global.hosts.domain')
    gitlab_fqdn="gitlab.${gitlab_chart_domain_name}"
    gitlab_from_k8_root_password=$(get_kubectl_secret_data "${gitlab_from_k8_initial_root_password}" "${gitlab_from_k8_initial_root_password_key}" "${gitlab_namespace}")

    # Получаем секреты для Волт
    local vault_chart_name='vault'
    local vault_namespace=$(yq ".charts[] | select(.name == \"${vault_chart_name}\") | .namespace" "$config_file")
    local vault_chart_chart_values=$(yq ".charts[] | select(.name == \"${vault_chart_name}\") | .chart_values" "$config_file")
    local vault_chart_custom_values=$(yq ".charts[] | select(.name == \"${vault_chart_name}\") | .custom_values" "$config_file")
    local vault_chart_secret_name=$(echo "${vault_chart_custom_values}" | yq '.vault-unseal-secret.name')
    local vault_chart_root_token=$(echo "${vault_chart_custom_values}" | yq '.vault-unseal-secret.initial-root-token')
    vault_chart_fqdn_arr=($(echo "$vault_chart_chart_values" | yq '.. | select(has("ingress")).ingress.tls[].hosts[]'))
    vault_root_token=$(get_kubectl_secret_data "${vault_chart_secret_name}" "${vault_chart_root_token}" "${vault_namespace}")


    # Ниже пишем свой код
    echo "nexus_chart_fqdn=\"${nexus_chart_fqdn}\""
    echo "nexus_chart_fqdn_docker_registry=\"${nexus_chart_fqdn_docker_registry}\""
    echo "nexus_from_k8s_admin_password=\"$nexus_from_k8s_admin_password\""
    echo "nexus_from_k8s_gpg_public_key: " "${nexus_from_k8s_gpg_public_key}"

    echo "netbox_chart_fqdn_arr"=$"\"${netbox_chart_fqdn_arr}\""
    echo "netbox_from_k8s_api_token"=$"\"${netbox_from_k8s_api_token}\""
    echo "netbox_from_k8s_password"=$"\"${netbox_from_k8s_password}\""
    echo "netbox_from_k8s_username"=$"\"${netbox_from_k8s_username}\""

    echo "gitlab_chart_domain_name"=\"${gitlab_chart_domain_name}\"
    echo "gitlab_fqdn"=\"${gitlab_fqdn}\"
    echo "gitlab_from_k8_root_password"=\"${gitlab_from_k8_root_password}\"

    echo "vault_chart_fqdn_arr=${vault_chart_fqdn_arr[@]}"
    echo "vault_root_token=\"$vault_root_token\""
}

upload_nexus() {
    NEXUS_USER=admin
    NEXUS_PASSWORD=$nexus_from_k8s_admin_password
    NEXUS_FQDN=$nexus_chart_fqdn
    DOCKER_FQDN=$nexus_chart_fqdn_docker_registry
    docker login $DOCKER_FQDN -u $NEXUS_USER -p $NEXUS_PASSWORD

    upload_data_nexus
    upload_docker_nexus
}

upload_data_nexus() {
    local ARCHIVE="keystack-$RELEASE-$BASE-nexus-data.tar.gz"
    check_file_exists $ARCHIVE
    log_info_block "Распаковка данных и их загрузка в Nexus"
    tar -xf $ARCHIVE --checkpoint=10000 --checkpoint-action="ttyout=\b->"
    echo
    echo -en "${nexus_from_k8s_gpg_public_key}" > nexus-$BASE/k-add/keystack.gpg
    pip install twine -q --no-index --find-links file:///$INSTALL_DIR/nexus-$BASE/k-pip
    function upload_files_to_nexus {
        local directory="$1"
        for file in "$directory"/*; do
            echo "Загрузка $file"
            set +e
            case "${file##*.}" in
                "deb")
                    response=$(curl -ks -L -w "%{http_code}" -u "$NEXUS_USER:$NEXUS_PASSWORD" -H "Content-Type: multipart/form-data" --data-binary "@./$file" "https://$NEXUS_FQDN/repository/$directory/")
                    ;;
                *)
                    response=$(curl -ks -L -w "%{http_code}" -u "$NEXUS_USER:$NEXUS_PASSWORD" --upload-file ./$file "https://$NEXUS_FQDN/repository/$file")
                    ;;
            esac
            set -e
            if [[ "$response" =~ ^2 ]]; then
                log_info "$file успешно загружен"
            elif [[ "$response" = 400 ]]; then
                log_info "Файл $file уже есть в Nexus."
            else
                exit_on_error "Ошибка загрузки $file. HTTP Response: $response. Check Nexus server logs for details."
            fi
        done
    }

    cd nexus-$BASE
    for directory in *; do
        case $directory in
            "docker-$BASE")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "images")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "k-add")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "$BASE")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "k-pip")
                python3 -m twine upload -u $NEXUS_USER -p $NEXUS_PASSWORD --skip-existing --disable-progress-bar --repository-url https://$NEXUS_FQDN/repository/$directory/ $directory/* || true
                ;;
            *)
                echo -e "\033[1;31mWARNING: \033[0m Неизвестная $directory, пропускаем..."
                ;;
        esac
    done
    cd -
}

upload_docker_nexus() {
    local ARCHIVE="keystack-$RELEASE-$BASE-docker-images.tar"
    local DOCKER_IMAGE_LIST="keystack-$RELEASE-$BASE-docker-images.txt"
    check_file_exists $ARCHIVE
    check_file_exists $DOCKER_IMAGE_LIST
    log_info_block "Загрузка образов Docker в Nexus."
    docker load -q -i $ARCHIVE
    while read -r image; do
        if [[ $image =~ "kolla-ansible" ]]; then
            new_image=$(echo "$image" | sed "s/repo.itkey.com/$DOCKER_FQDN/" | sed "s/\-$BASE$//")
        else
            new_image=$(echo "$image" | sed "s/repo.itkey.com/$DOCKER_FQDN/")
        fi
        set +e
        docker tag "$image" "$new_image"
        if [ $? -ne 0 ]; then
            echo -e "\033[1;31mОшибка\033[0m при тегировании $image -> $new_image"
        fi
        docker push -q "$new_image"
        if [ $? -ne 0 ]; then
            echo -e "\033[1;31mОшибка\033[0m при загрузке $new_image"
        fi
        docker image rm -f "$image"
        if [ $? -ne 0 ]; then
            echo -e "\033[1;31mОшибка\033[0m при удалении $image"
        fi
        docker image rm -f "$new_image"
        if [ $? -ne 0 ]; then
            echo -e "\033[1;31mОшибка\033[0m при удалении $new_image"
        fi
        set -e
    done < $DOCKER_IMAGE_LIST
}

upload_netbox() {
    NETBOX_API_URL="https://$netbox_chart_fqdn_arr/api/"
    log_info_block "Загрузка данных в Netbox"
    upload_data_netbox
}

curl_netbox() {
    local data_file=$1
    local endpoint=$2

    check_file_exists $data_file
    local data_json=$(cat "$data_file")

    echo "Загрузка файла $data_file в $NETBOX_API_URL$endpoint/"

    response=$(curl -ks -L -X POST "${NETBOX_API_URL}${endpoint}/" \
        -H "Authorization: Token $netbox_from_k8s_api_token" \
        -H "Content-Type: application/json" \
        -d "$data_json" \
        --connect-timeout 10)

    # Проверка на успешность загрузки
    if [[ -z "$response" ]]; then
        exit_on_error "Error: Нет ответа от NetBox. Проверьте конечную точку API или данные."
    fi

    # Проверка формата ответа (массив или объект)
    if [[ $(echo "$response" | jq -e 'type == "array"') ]]; then
        # Обработка случая, когда в ответе массив
        if [[ "$(echo "$response" | jq length)" -gt 0 ]]; then
            echo "Success: Данные загружены в ${endpoint} из ${data_file}."
        else
            echo "Success: Данные загружены в ${endpoint}, but response is an empty array."
        fi
    elif [[ $(echo "$response" | jq -e 'type == "object"') ]]; then
        # Обработка случая, когда в ответе объект
        error_message=$(echo "$response" | jq -r '.detail // empty')
        if [[ -n "$error_message" ]]; then
            echo "Error: $error_message"
        else
            id=$(echo "$response" | jq -r '.id // empty')
            if [[ -n "$id" ]]; then
                echo "Success: Данные загружены в ${endpoint} из ${data_file} с ID $id."
            else
                echo "Success: Данные загружены в ${endpoint}, но не вернули ID."
            fi
        fi
    else
        echo "Error: Неожиданный формат ответа: $response"
    fi
}

upload_data_netbox() {
    # Массив json файлов
    declare -a endpoints_and_files=(
        "tenancy/tenants netbox_jsons/tenants.json"
        "extras/tags netbox_jsons/tags.json"
        "dcim/site-groups netbox_jsons/site_groups.json"
        "dcim/regions netbox_jsons/regions.json"
        "dcim/manufacturers netbox_jsons/device_manufacturers.json"
        "dcim/device-types netbox_jsons/device_types.json"
        "dcim/device-roles netbox_jsons/device_roles.json"
        "dcim/sites netbox_jsons/sites.json"
        "extras/custom-field-choice-sets netbox_jsons/custom_fields_choice_sets.json"
        "extras/custom-fields netbox_jsons/custom_fields.json"
        "dcim/devices netbox_jsons/devices.json"
        "ipam/vlans netbox_jsons/vlans.json"
        "ipam/prefixes netbox_jsons/prefixes.json"
        "dcim/interfaces netbox_jsons/interfaces_bond.json"
        "dcim/interfaces netbox_jsons/interfaces.json"
        "ipam/ip-addresses netbox_jsons/ip_addresses.json"
        "extras/config-contexts netbox_jsons/config_contexts.json"
        "users/permissions netbox_jsons/permissions.json"
    )

    for entry in "${endpoints_and_files[@]}"; do
        endpoint=$(echo "$entry" | awk '{print $1}')
        file=$(echo "$entry" | awk '{print $2}')
        curl_netbox "$file" "$endpoint"
    done
}

upload_vault() {
    log_info_block "Загрузка данных в Vault"
    # Данные для внесения в Vault
    local headers=("X-Vault-Token: $vault_root_token")
    local secret_v2='{ "type": "kv-v2" }'
    local installer='{ "type": "pki" }'
    local approle='{ "type": "approle" }'
    local role_keystack='{ "token_policies": ["secret_v2/deployments"] }'
    local job_key_json='{ "data": {"value": "'$(cat ~/.ssh/id_rsa | awk '{printf "%s\\n",$0}')'"} }'
    local ca_crt='{ "data": {"value": "'$(echo  $from_k8s_ca_crt | awk '{printf "%s\\n",$0}')'"} }'
    local bifrost_rmi='{ "data": {"user": "ipmi_user", "password": "ipmi_password"} }'
    local accounts='{ "data": {"gitlab_root_password": "'$gitlab_from_k8_root_password'", "nexus_admin_password": "'$nexus_from_k8s_admin_password'", "netbox_admin_password": "'$netbox_from_k8s_password'", "NETBOX_TOKEN": "'$netbox_from_k8s_api_token'"} }'
    local from_k8s_ca_pem=$(echo -en "${from_k8s_ca_key}\n${from_k8s_ca_crt}")
    local pem_bundle='{ "pem_bundle": "'$(echo -en "$from_k8s_ca_pem" | awk '{printf "%s\\n",$0}')'" }'
    local roles_certs='{ "allowed_domains": "'$gitlab_chart_domain_name'", "allow_subdomains": "true", "max_ttl": "17520h", "ttl": "17520h" }'
    local config_urls='{ "issuing_certificates": "https://'$vault_chart_fqdn_arr'/v1/pki/ca", "crl_distribution_points": "https://'$vault_chart_fqdn_arr'/v1/pki/crl"}'
    # Команды для внесения данных в Vault
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/sys/policy/secret_v2/deployments" "headers" "@policy.json"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/sys/mounts/secret_v2" "headers" "$secret_v2"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/sys/mounts/installer" "headers" "$installer"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/sys/auth/approle" "headers" "$approle"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/auth/approle/role/keystack" "headers" "$role_keystack"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/installer/config/ca" "headers" "$pem_bundle"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/installer/roles/certs" "headers" "$roles_certs"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/installer/config/urls" "headers" "$config_urls"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/secret_v2/data/deployments/$gitlab_fqdn/secrets/job_key" "headers" "$job_key_json"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/secret_v2/data/deployments/$gitlab_fqdn/secrets/ca.crt" "headers" "$ca_crt"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/secret_v2/data/deployments/$gitlab_fqdn/bifrost/rmi" "headers" "$bifrost_rmi"
    curl_vault "POST" "https://$vault_chart_fqdn_arr/v1/secret_v2/data/deployments/$gitlab_fqdn/secrets/accounts" "headers" "$accounts"

    # Данные approle для дальнейшего использования
    # Данные approle для дальнейшего использования
    role_id=$(curl -ks -L -X "GET" "https://$vault_chart_fqdn_arr/v1/auth/approle/role/keystack/role-id" -H "X-Vault-Token: $vault_root_token" | jq -r ".data.role_id")
    secret_id=$(curl -ks -L -X "POST" "https://$vault_chart_fqdn_arr/v1/auth/approle/role/keystack/secret-id" -H "X-Vault-Token: $vault_root_token" | jq -r ".data.secret_id")
}

curl_vault() {
    local metod="$1"
    local url="$2"
    local -n headers_array="$3"
    local json="${4:-}"

    local curl_headers=()
    for header in "${headers_array[@]}"; do
        curl_headers+=("-H" "$header")
    done

    local http_code
    local response

    if [[ ${metod^^} == "PUT" || ${metod^^} == "POST" ]]; then
        response=$(curl -ks -L -w "%{http_code}" -X "$metod" "$url" "${curl_headers[@]}" -d "$json")
    else
        response=$(curl -ks -L -w "%{http_code}" -X "$metod" "$url" "${curl_headers[@]}")
    fi

    http_code=${response: -3}
    response_body=${response::-3}

    if [[ $http_code -eq 200 ]]; then
        echo "Добавляем переменную. Код: $http_code" >&2
    elif [[ $http_code -eq 204 ]]; then
        echo "Обновляем переменную. Код: $http_code" >&2
    elif [[ $http_code -eq 400 ]]; then
        echo "Такая переменная уже есть и не может быть обновлена. Код: $http_code " $response_body
    else
        echo "Ошибка: Код $http_code Содержимое: $response_body"
    fi
}


upload_gitlab() {
    log_info_block "Загрузка данных в Gitlab"

    # Данные для Gitlab
    local pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$gitlab_from_k8_root_password\"}"
    local token=$(curl -ks -L -X POST -H "Content-Type: application/json" -d "$pwd_data" "https://$gitlab_fqdn/oauth/token" | jq -r .access_token)
    local headers=("Authorization: Bearer $token" "Content-Type: application/json")

    # Создание групп и подгрупп
    local grp_data_project_k="{\"name\":\"project_k\",\"path\":\"project_k\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
    group_id_project_k=$(curl_gitlab_group "POST" "https://$gitlab_fqdn/api/v4/groups" "headers" "$grp_data_project_k")
    local grp_data_deployments="{\"name\":\"deployments\",\"parent_id\":\"${group_id_project_k}\",\"path\":\"deployments\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
    group_id_deployments=$(curl_gitlab_group "POST" "https://$gitlab_fqdn/api/v4/groups" "headers" "$grp_data_deployments")
    local grp_data_services="{\"name\":\"services\",\"parent_id\":\"${group_id_project_k}\",\"path\":\"services\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
    group_id_services=$(curl_gitlab_group "POST" "https://$gitlab_fqdn/api/v4/groups" "headers" "$grp_data_services")

    # Загрузка репозиториев в Gitlab
    while IFS="=" read -r repo branch; do
        cd "$INSTALL_DIR/repo/project_k/$repo" || exit
        git remote add origin "https://git:${token}@$gitlab_fqdn/project_k/${repo}.git"
        log_info "Загрузка репозитория $repo в GitLab..."
        git push -u origin --all -o ci.skip
        git push -u origin --tags -o ci.skip
        git remote remove origin
    done < "./keystack"

    #new changes in gitlab - need to disable scope job token access
    repo_id_ci=$(curl_gitlab_group "GET" "https://$gitlab_fqdn/api/v4/projects?search=ci&simple=true" "headers")
    curl -ks -L -X PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$gitlab_fqdn/api/v4/projects/${repo_id_ci}/job_token_scope"
    repo_id_keystack=$(curl_gitlab_group "GET" "https://$gitlab_fqdn/api/v4/projects?search=keystack&simple=true" "headers")
    curl -ks -L -X PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$gitlab_fqdn/api/v4/projects/${repo_id_keystack}/job_token_scope"
    repo_id_bifrost=$(curl_gitlab_group "GET" "https://$gitlab_fqdn/api/v4/projects?search=bifrost&simple=true" "headers")
    curl -ks -L -X PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$gitlab_fqdn/api/v4/projects/${repo_id_bifrost}/job_token_scope"
    repo_id_region1=$(curl_gitlab_group "GET" "https://$gitlab_fqdn/api/v4/projects?search=region1&simple=true" "headers")
    curl -ks -L -X PATCH -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d '{"enabled":false}'  "https://$gitlab_fqdn/api/v4/projects/${repo_id_region1}/job_token_scope"

    # Переменные в Gitlab CI/CD Variables
    ci_cd_vars=(
        GIT_SSL_NO_VERIFY=true=false
        KEYSTACK_REGISTRY_USER=$NEXUS_USER=false
        KEYSTACK_REGISTRY=$DOCKER_FQDN=false
        NETBOX_URI=https://$netbox_chart_fqdn_arr=false
        CI_REGISTRY='$KEYSTACK_REGISTRY'=false
        NEXUS_FQDN=$NEXUS_FQDN=false
        KEYSTACK_NEXUS=https://$NEXUS_FQDN=false
        NEXUS_USER=$NEXUS_USER=false
        LCM_IP=$LCM_IP=false
        DOMAIN=$gitlab_chart_domain_name=false
        INSTALL_HOME=$INSTALL_DIR=false
        BASE=$BASE=false
        ANSIBLE_FORCE_COLOR=true=false
        ANSIBLE_STDOUT_CALLBACK=yaml=false
        vault_addr=https://$vault_chart_fqdn_arr=false
        vault_engine=secret_v2=false
        vault_method=approle=false
        vault_username=$role_id=true
        vault_password=$secret_id=true
        vault_prefix=deployments/$gitlab_fqdn=false
        vault_role=keystack=false
        vault_pki=installer=false
        vault_role_pki=certs=false
        vault_secman=false=false
    )

    # Создание или обновление переменных в Gitlab CI/CD Variables
    log_info "Gitlab CI/CD Variables"
    for line in ${ci_cd_vars[@]}; do
        IFS="="
        read key value masked <<< "$line"
        curl_gitlab_put_vars $key $value $masked
    done
}

curl_gitlab_group() {
    local metod="$1"
    local url="$2"
    local -n headers_array="$3"
    local json="${4:-}"

    local curl_headers=()
    for header in "${headers_array[@]}"; do
        curl_headers+=("-H" "$header")
    done

    local http_code
    local response

    if [[ ${metod^^} == "PUT" || ${metod^^} == "POST" ]]; then
        response=$(curl -ks -L -w "%{http_code}" -X "$metod" "$url" "${curl_headers[@]}" -d "$json")
    else
        response=$(curl -ks -L -w "%{http_code}" -X "$metod" "$url" "${curl_headers[@]}")
    fi

    http_code=${response: -3}
    response_body=${response::-3}

    if [[ $http_code -eq 201 ]]; then
        echo $(echo ${response_body} | jq '.id')
    elif [[ $http_code -eq 200 ]]; then
        echo $(echo ${response_body} | jq '.[].id')
    elif [[ $http_code -eq 400 ]]; then
        echo $(curl -ks -L -X "GET" "$url" "${curl_headers[@]}" | jq '.[] | select(.name=='$(echo $json | jq .name)').id')
    else
        exit_on_error "Ошибка: Код $http_code"
    fi

}

curl_gitlab_put_vars () {
    local key=$1
    local value=$2
    local masked=$3

    response=$(curl -ks -L -w "%{http_code}" -X GET -H "Authorization: Bearer $token" https://$gitlab_fqdn/api/v4/groups/${group_id_project_k}/variables/$key)

    http_code=${response: -3}
    response_body=${response::-3}

    if [[ $http_code -eq 404 ]]; then
        response=$(curl -ks -L -w "%{http_code}" -X POST -H "Authorization: Bearer $token" -F "key=$key" -F "value=$value" -F "masked=$masked" "https://$gitlab_fqdn/api/v4/groups/${group_id_project_k}/variables")
        if [[ ${response: -3} -eq 201 ]]; then
            echo -e "Добавляем переменную \033[1;32m$key\033[0m"
        fi
    elif [[ $http_code -eq 200 ]]; then
        response=$(curl -ks -L -w "%{http_code}" -X PUT -H "Authorization: Bearer $token" -F "value=$value" -F "masked=$masked"  "https://$gitlab_fqdn/api/v4/groups/${group_id_project_k}/variables/$key")
        if [[ ${response: -3} -eq 200 ]]; then
            echo -e "Обновляем переменную \033[1;32m$key\033[0m"
        fi
    else
        exit_on_error "Ошибка: Код $http_code"
    fi
}


main() {
    local log_file="${PWD}/upload_$(date +"%d-%m-%Y_%H-%M").log"
    exec > >(tee "$log_file") 2>&1

    IFS="-"; read -r RELEASE < version; unset IFS
    IFS="-"; read -r BASE < version-base; unset IFS
    log_info_block $'\n\n'"*** KeyStack Installer v3.0 ($RELEASE-$BASE) ***"$'\n\n'
    # check os release
    os=unknown
    [[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo ${ID,,}; })

    ip=$(hostname -I | { read -r ip _; echo $ip; })
    lcm_ip=${lcm_ip:-${ip}}
    export LCM_IP=$lcm_ip
    INSTALL_DIR=`pwd`
    export TWINE_DISABLE_CERTIFICATE_VERIFICATION=1
    export CURL_CA_BUNDLE="$INSTALL_DIR/mutiple-node/certs/ca.crt"
    export GIT_SSL_NO_VERIFY=true
    git config --global user.email "root@gitlab"
    git config --global user.name "ITKey KeyStack"
    git config --global --add safe.directory '*'

    log_info_block "Начальная проверка"
    local config_file="$1"
    echo "Проверяю передан ли конфиг файл как аргумент"
    check_retrieved_value "config_file" "${config_file}"
    check_file_exists "$config_file"

    # # Получаю ключи CA
    log_info_block "Получаю ключи CA сертификаты пароли FQDNs"
    get_secret

    upload_nexus

    upload_netbox

    upload_vault

    upload_gitlab
}

main "$@"