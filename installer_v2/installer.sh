#!/bin/bash

set -e
set -u
set -o errtrace
set -o pipefail
# set -x

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

exit_with_help() {
  # Вывод красным цветом
  echo -e "\033[1;31m$1\033[0m" >&2
  show_help
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

show_help() {
  echo "Использование: $0 --config <файл> --order <1|2> [--upgrade] [--install-charts chart1 chart2] [--create-secrets --order 2] [--upgrade --no-drain]"
  echo ""
  echo "Параметры:"
  echo "  --order            Укажите порядок выполнения (1 или 2). Обязательно. Не может использоваться с --upgrade или --install-charts"
  echo "  --upgrade          Установка обновлений. Не может использоваться с --order или --install-charts"
  echo "  --install-charts   Принудительная установка списка чартов. Не может использоваться с --order или --upgrade"
  echo "  --create-secrets   Создать self-signed сертификаты и kubernetes secrets из chart_values. Используется только с --order 2"
  echo "  --no-drain         Требуется при обновлении K8s в архитектуре одного узла. Используется только с --upgrade"
  echo "  --help             Показать справочную информацию."
  exit 0
}

process_arguments() {

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    --order)
      shift
      if [[ -z "${1:-}" || "$1" =~ ^- ]]; then
        exit_with_help "Ошибка: --order требует указания значения (1 или 2)."
      fi
      order_value="$1"
      shift
      ;;
    --upgrade)
      upgrade_flag=true
      shift
      ;;
    --install-charts)
      shift
      if [[ -z "${1:-}" || "$1" =~ ^- ]]; then
        exit_with_help "Ошибка: --install-charts требует указания хотя бы одного chart."
      fi
      while [[ "${1:-}" && ! "$1" =~ ^- ]]; do
        charts_to_install+=("$1")
        shift
      done
      ;;
    --create-secrets)
      create_secrets_flag=true
      shift
      ;;
    --no-drain)
      no_drain_flag=true
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      exit_on_error "Неизвестный параметр: $1. Используйте --help для справки."
      ;;
    esac
  done

  if [[ -z "$config_file" ]]; then
    exit_with_help "Ошибка: Укажите путь к файлу конфигурации с помощью --config."
  fi

  if [[ ($order_value == 1 || $order_value == 2) && (${#charts_to_install[@]} -gt 0 || "$upgrade_flag" == true || "$no_drain_flag" == true) ]]; then
    exit_with_help "Ошибка: --order не может использоваться вместе с --install-charts, --upgrade или --no-drain"
  elif [[ $order_value == 0 && (${#charts_to_install[@]} -eq 0 && "$upgrade_flag" == false) ]]; then
    exit_with_help "Ошибка: должен быть установлен один из параметров --order, --install-charts или --upgrade"
  elif [[ $order_value != 1 && $order_value != 2 && $order_value != 0 ]]; then
    exit_with_help "Ошибка: --order должен принимать значение 1 или 2"
  fi

  if [[ $upgrade_flag == true && (${#charts_to_install[@]} -gt 0 || $create_secrets_flag == true) ]]; then
    exit_with_help "Ошибка: --upgrade не может использоваться вместе с --order <1|2>, --install-charts или --create-secrets"
  fi

  if [[ ${#charts_to_install[@]} -gt 0 && ($create_secrets_flag == true || "$no_drain_flag" == true) ]]; then
    exit_with_help "Ошибка: --install-charts не может использоваться вместе с --order <1|2>, --create-secrets или --no-drain"
  fi

  if [[ $create_secrets_flag == true && ($order_value != 1 || "$no_drain_flag" == true) ]]; then
    exit_with_help "Ошибка: --create-secrets должен запускаться с --order 1"
  fi
}

install_tools() {
  local tool_name=$1

  echo "Устанавливаю $tool_name"

  check_file_exists "$tool_name"

  if ! sudo chmod +x "$tool_name"; then
    exit_on_error "Ошибка установки прав на выполнение для $tool_name"
  fi

  if ! sudo cp "$tool_name" /usr/bin/; then
    exit_on_error "Ошибка перемещения $tool_name в /usr/bin/"
  fi

  if [[ "$tool_name" == "kubectl" ]]; then
    if ! /usr/bin/"$tool_name" version --client >/dev/null 2>&1; then
      exit_on_error "Ошибка: не удалось выполнить ${tool_name} version --client. Проверьте установку."
    fi
  elif [[ "$tool_name" == "velero" ]]; then
    return
  else
    if ! /usr/bin/"$tool_name" version >/dev/null 2>&1; then
      exit_on_error "Ошибка: не удалось выполнить ${tool_name} version. Проверьте установку."
    fi
  fi
}

create_k0s_config() {
  local config_file="$1"
  log_info_block "Создаю конфигурационный файл k0sctl"
  check_file_exists "k0sctl.j2"

  if ! jinja -D bundle_images_file "$bundle_images_file" -d "$config_file" "k0sctl.j2" >"k0sctl.yaml"; then
    exit_on_error "Ошибка создания k0sctl.yaml"
  fi
  echo "Файл конфигурации: k0sctl.yaml создан успешно"
}

apply_k0s_config() {
  log_info_block "Устанавливаю Kubernetes"
  check_file_exists "k0sctl.yaml"

  if ! k0sctl apply --config k0sctl.yaml --timeout 15m; then
    exit_on_error "Ошибка применения обновления K0s"
  fi
}

apply_k0s_config_no_drain() {
  log_info_block "Устанавливаю Kubernetes"
  check_file_exists "k0sctl.yaml"

  if ! k0sctl apply --config k0sctl.yaml --no-drain --timeout 15m; then
    exit_on_error "Ошибка применения обновления K0s"
  fi
}

install_k8s_config() {
  log_info_block "Устанавливаю конфигурацию Kubernetes"

  echo "Создаю каталог: mkdir -p ~/.kube"
  mkdir -p ~/.kube || exit_on_error "Ошибка создания каталога ~/.kube"

  echo "Получаю конфигурацию Kubernetes: k0sctl kubeconfig > ~/.kube/config"
  k0sctl kubeconfig >~/.kube/config || echo "Ошибка получения конфигурации Kubernetes"

  echo "Устанавливаю права на файл конфигурации: sudo chmod 600 ~/.kube/config"
  sudo chmod 600 ~/.kube/config || echo "Ошибка установки прав на каталог  ~/.kube/config"

  if ! mkdir -p ~/.kube || ! k0sctl kubeconfig >~/.kube/config || ! sudo chmod 600 ~/.kube/config; then
    exit_on_error "Ошибка установки конфигурации кластера"
  fi

  local vip
  vip=$(yq '.cp_vip' "$config_file")

  if [[ $vip == 'null' ]]; then
    return
  fi

  local fqdn_cp1
  fqdn_cp1=$(yq '.fqdn_cp1' "$config_file")
  check_retrieved_value "fqdn_cp1" "$fqdn_cp1"

  echo "Устанавливаю VIP в ~/.kube/config"
  local ip_regex="^((25[0-5]|(2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\.){3}(25[0-5]|(2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))(\/(3[0-2]|[1-2]?[0-9]))?$"
  if [[ ! $vip =~ $ip_regex ]]; then
    exit_on_error "Неверный формат IP-адреса"
  fi

  vip=$(echo "$vip" | awk -F'/' '{print $1}')

  echo "VIP=\"${vip}\""
  sed -i "s|server: https://${fqdn_cp1}:6443|server: https://${vip}:6443|" ~/.kube/config
  local result
  result=$(grep 'server' ~/.kube/config | sed 's|^[[:space:]]*||')
  echo "Результат замены=\"${result}\""
}

check_cp_nodes_status() {
  local nodes="$1"

  while read -r node_name ready_status; do
    if [[ -n "$node_name" && "$ready_status" != "True" ]]; then
      return 1
    fi
  done <<<"$nodes"
  return 0
}

wait_for_cp_nodes_ready() {
  log_info_block "Ожидаю готовность нод control-plane"
  local max_attempts=60
  local interval=5
  local attempt=0
  local success_count=0
  local required_success_count=3
  local total_nodes_count
  total_nodes_count=$(yq 'keys | map(select(test("^fqdn_cp\\d+$"))) | length' "$config_file")
  local current_nodes_count=0
  local get_nodes_cmd=(kubectl get nodes --request-timeout=1s -l node-role.kubernetes.io/control-plane -o custom-columns=":metadata.name,:status.conditions[?(@.type=='Ready')].status" --no-headers)

  while [ $attempt -lt $max_attempts ]; do
    if "${get_nodes_cmd[@]}" >/dev/null 2>&1; then # Проверка доступности API k8s
      current_nodes_count="$("${get_nodes_cmd[@]}" | wc -l)"
      if [[ "$current_nodes_count" -eq "$total_nodes_count" ]]; then
        if check_cp_nodes_status "$("${get_nodes_cmd[@]}")"; then # Проверка Ready статуса control-plane узлов
          success_count=$((success_count + 1))
          printf "\r\033[KУспешных проверок готовности: (%d/%d)" "$success_count" "$required_success_count"
          if [ $success_count -ge $required_success_count ]; then
            echo -e "\nРесурс доступен"
            return 0
          fi
          attempt=$((attempt + 1))
          sleep $interval
          continue
        fi
      fi
    fi

    success_count=0
    printf "\r\033[KБезуспешных проверок готовности: %d/%d" "$((attempt + 1))" "$max_attempts"
    attempt=$((attempt + 1))
    sleep $interval
  done

  exit_on_error "\r\033[KПревышено количество безуспешных проверок $max_attempts"
}

check_vip_ready() {
  local vip
  vip=$(yq '.cp_vip' "$config_file")

  if [[ $vip == 'null' ]]; then
    return
  fi

  log_info_block "Ожидаю готовность VIP Kubernetes"
  if ! ping -c 1 -w 5 "$(echo "$vip" | awk -F'/' '{ print $1 }')" &>/dev/null; then
    exit_on_error "Ошибка: VIP не доступен"
  else
    echo "OK. VIP доступен"
  fi
}

helm_block_command() {
  if [ -n "$values_file" ]; then
    log_info_block "Устанавливаю чарт $chart_name с настройками из $values_file"
    helm_command="helm upgrade $chart_name ${charts_archive_dir}/${chart_file} --install --create-namespace --namespace $chart_namespace --version $chart_version -f $values_file"
  else
    log_info_block "Устанавливаю чарт $chart_name"
    helm_command="helm upgrade $chart_name ${charts_archive_dir}/${chart_file} --install --create-namespace --namespace $chart_namespace --version $chart_version"
  fi

  if ! $helm_command; then
    exit_on_error "Ошибка установки чарта $chart_name"
  fi
}

install_charts() {
  local config
  config=$(yq eval '.' "$config_file")
  local chart_count
  chart_count=$(echo "$config" | yq '.charts | length')

  for ((i = 0; i < chart_count; i++)); do
    local chart_name
    chart_name=$(echo "$config" | yq ".charts[$i].name")
    local chart_version
    chart_version=$(echo "$config" | yq ".charts[$i].version")
    local chart_values
    chart_values=$(echo "$config" | yq ".charts[$i].chart_values" 2>/dev/null)
    local chart_namespace
    chart_namespace=$(echo "$config" | yq ".charts[$i].namespace")
    local chart_order
    chart_order=$(echo "$config" | yq ".charts[$i].order")
    local chart_install_flag
    chart_install_flag=$(echo "$config" | yq ".charts[$i].install")
    local chart_file
    chart_file=$(echo "$config" | yq ".charts[$i].chart")

    local values_file=""
    if [ -n "$chart_values" ] && [ "$chart_values" != "null" ]; then
      values_file="$tmp_dir/${chart_name}_values.yaml"
      echo "$chart_values" >"$values_file"
    fi

    if [[ $chart_install_flag == true ]]; then
      if [[ "$chart_order" == "$order_value" ]] && [[ $upgrade_flag == false ]]; then
        if [[ $chart_name == 'nexus3' ]]; then
          nexus_create_admin_password "$values_file"
          nexus_create_gpg_secret_apt_repo "$config_file"
        fi
        helm_block_command
      else
        if [[ $upgrade_flag == true ]]; then
          local chart_installed_version
          chart_installed_version=$(get_installed_chart_version "$chart_name" "$chart_namespace")
          if [[ $(echo -e "$chart_installed_version\n$chart_version" | sort -V | head -n 1) == "$chart_installed_version" ]] &&
            [[ "$chart_installed_version" != "$chart_version" ]]; then
            helm_block_command
            if [[ $chart_name == "vault" ]]; then
              configure_vault "$config_file"
            fi
          else
            echo "Для $chart_name нет новой версии. Остаемся на $chart_version"
          fi
        fi
      fi
    fi
  done
}

get_installed_chart_version() {
  local release_name=$1
  local namespace=$2
  local version
  version=$(helm get metadata "$release_name" -n "$namespace" | awk '/^VERSION:/ {print $2}')
  echo "$version"
}

install_charts_force() {
  local config_file=$1
  local archive_dir=$2

  for chart in "${charts_to_install[@]}"; do

    local chart_exists
    chart_exists=$(yq ".charts[] | select(.name == \"$chart\")" "$config_file")

    if [ -z "$chart_exists" ]; then
      exit_on_error "Чарт $chart не определён в файле конфигурации $config_file"
    fi

    find "$archive_dir" -type f | grep -E "$chart" | while read -r archive_file; do
      log_info_block "Извлекаем чарт $chart из $archive_file"
      if ! tar -xzf "$archive_file" -C "$tmp_dir"; then
        exit_on_error "Ошибка извлечения $chart из $archive_file"
      fi
    done

    local chart_name
    chart_name=$(yq ".charts[] | select(.name == \"$chart\").name" "$config_file")
    local chart_version
    chart_version=$(yq ".charts[] | select(.name == \"$chart\").version" "$config_file")
    local chart_values
    chart_values=$(yq ".charts[] | select(.name == \"$chart\").chart_values" "$config_file" 2>/dev/null)
    local chart_namespace
    chart_namespace=$(yq ".charts[] | select(.name == \"$chart\").namespace" "$config_file")

    local values_file=""
    if [ -n "$chart_values" ] && [ "$chart_values" != "null" ]; then
      values_file="$tmp_dir/${chart_name}/${chart_name}_values.yaml"
      echo "$chart_values" >"$values_file"
    fi

    if [[ $chart_name == 'nexus3' ]]; then
      nexus_create_admin_password "$values_file"
      nexus_create_gpg_secret_apt_repo "$config_file"
      helm_block_command
      configure_nexus "$config_file"
    elif [[ $chart_name == 'vault' ]]; then
      helm_block_command
      configure_vault "$config_file"
    elif [[ $chart_name == 'kube-prometheus-stack' ]]; then
      helm_block_command
    else
      helm_block_command
    fi
  done
}

create_ca_cert() {
  local ca_key=${1:-"${certs_dir}/ca.key"}
  local ca_cert=${2:-"${certs_dir}/ca.crt"}
  local ca_days=${3:-3650}

  log_info_block "Создаю корневой сертификат CA"

  if [[ -f "$ca_key" && -f "$ca_cert" ]]; then
    echo "Сертификат $ca_cert и ключ $ca_key уже существуют. Пропускаю создание"
    return
  fi

  openssl genpkey -algorithm RSA -out "$ca_key" -pkeyopt rsa_keygen_bits:2048
  echo "Приватный ключ CA сохранен в: $ca_key"

  openssl req -x509 -new -nodes -key "$ca_key" -sha256 -days "$ca_days" -out "$ca_cert" \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=ITKey/OU=IT Department/CN=LCM Root CA"
  echo "Сертификат CA сохранен в: $ca_cert"
}

install_ca_cert() {
  local ca_cert="${certs_dir}/ca.crt"
  local ssh_username
  ssh_username=$(yq '.ssh_username' "${config_file}")

  log_info_block "Устанавливаю корневой сертификат на ноды кластера"
  check_retrieved_value "ssh_username" "$ssh_username"
  check_directory_exists "${certs_dir}"

  cat <<'EOF' >"${tmp_dir}"/install_ca_cert.sh
#!/bin/bash
os_id=$(awk -F '=' '/^ID=/ {gsub(/"/, "", $2); print $2}' /etc/os-release)
if [[ "$os_id" == 'sberlinux' ]]; then
sudo cp /tmp/ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
else
  sudo cp /tmp/ca.crt /usr/local/share/ca-certificates/
  sudo update-ca-certificates
fi
echo "Сертификат успешно установлен"
EOF

  for host in $(yq '. | with_entries(select(.key | test("^fqdn_cp"))) | .[]' "${config_file}"); do
    if [[ "$host" == "null" ]]; then
      exit_on_error "Ошибка: при извлечении значения ключей fqdn_cp* из ${config_file}"
    else
      echo "Копирую на хост ${host} файлы ${tmp_dir}/install_ca_cert.sh и ${ca_cert} в каталог /tmp"
      scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${tmp_dir}/install_ca_cert.sh" "${ca_cert}" "${ssh_username}@${host}:/tmp/"
      echo "Выполняю на хосте ${host} скрипт /tmp/install_ca_cert.sh"
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "${ssh_username}@${host}" 'bash /tmp/install_ca_cert.sh'
      echo "Удаляю на хосте ${host} файлы /tmp/install_ca_cert.sh и /tmp/ca.crt"
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "${ssh_username}@${host}" 'bash -c "rm -fr /tmp/install_ca_cert.sh /tmp/ca.crt"'
    fi
  done
}

generate_csr() {
  local cn=$1
  local alt_names=$2

  if [[ -f "${certs_dir}/${cn}.key" || -f "${certs_dir}/${cn}.csr" ]]; then
    echo "Ключ или CSR уже существуют для: $cn. Пропуск."
    return
  fi

  openssl req -new -newkey rsa:2048 -nodes -keyout "${certs_dir}/${cn}.key" -out "${certs_dir}/${cn}.csr" \
    -config <(
      cat <<EOF
[ req ]
default_bits = 2048
prompt = no
distinguished_name = req_distinguished_name
req_extensions = req_ext

[ req_distinguished_name ]
C = RU
ST = Moscow
L = Moscow
O = ITKey
OU = IT Department
CN = $cn

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
$(echo -e "$alt_names")
EOF
    )

  echo "${certs_dir}/${cn}.key"
}

sign_csr() {
  local cn=$1
  local ca_key=$2
  local ca_cert=$3
  local alt_names=$4
  local cert_days=${5:-3650}

  if [[ -f "${certs_dir}/${cn}.crt" ]]; then
    echo "Сертификат уже существует для: $cn. Пропуск."
    return
  fi

  openssl x509 -req -in "${certs_dir}/${cn}.csr" -CA "$ca_cert" -CAkey "$ca_key" -CAcreateserial \
    -out "${certs_dir}/${cn}.crt" -days "$cert_days" -sha256 -extfile <(
      cat <<EOF
subjectAltName = @alt_names

[ alt_names ]
$(echo -e "$alt_names")
EOF
    )

  echo "${certs_dir}/${cn}.crt"
}

create_secret() {
  local secret=$1
  local cn=$2
  local crt_file=$3
  local key_file=$4
  local namespace=$5

  echo "Создаю k8s secret $secret для $cn"

  if ! kubectl create secret tls "${secret}" --cert="${crt_file}" --key="${key_file}" -n "$namespace" -- 2>/dev/null; then
    echo "Kubernetes secret ${secret} для ${cn} уже существует. Пропускаю создание."
  fi
}

create_cert() {
  local secret=$1
  local cn=$2
  local ca_key=$3
  local ca_cert=$4
  local alt_names=${5:-"DNS.1 = $cn"}

  log_info_block "Создаю сертификат для $cn"
  echo "Создаю приватный ключ и запрос на подпись для $cn"
  local key_file
  key_file=$(generate_csr "$cn" "$alt_names")
  if [[ "$key_file" != "${certs_dir}/${cn}.key" ]]; then
    echo "$key_file"
    return
  fi
  echo "Подписываю сертификат для $cn"
  local crt_file
  crt_file=$(sign_csr "$cn" "$ca_key" "$ca_cert" "$alt_names" "3650")
  echo "Приватный ключ для $cn сохранен в: $key_file"
  echo "Сертификат для $cn сохранен в: $crt_file"
  echo "Изменяю сертификат домена $cn в fullchain"
  cat "$ca_cert" >>"$crt_file"
}

create_gitlab_certs_and_secrets() {
  local yaml_file=$1
  local ca_key=$2
  local ca_cert=$3
  local resource_name=${4:-certs} # certs or secrets
  local domain_name
  domain_name=$(yq -r '.global.hosts.domain' "$yaml_file")
  local gitlab_namespace
  gitlab_namespace=$(yq '.charts[] | select(.name == "gitlab") | .namespace' "$config_file")

  declare -A domain_map=(
    [webservice]="gitlab"
    [kas]="kas"
    [registry]="registry"
    [minio]="minio"
  )

  mapfile -t paths < <(yq '.. | select(has("secretName")) | path | join(".")' "$yaml_file")

  for path in "${paths[@]}"; do
    local secret_name
    secret_name=$(echo "$path" | yq ".$path.secretName" "$yaml_file")
    local service_name
    service_name=$(awk -F'.' 'NF>2 {print $(NF-2)}' <<<"$path")
    local service_fqdn
    service_fqdn="${domain_map[$service_name]}.${domain_name}"

    if [[ $resource_name == 'certs' ]]; then
      create_cert "$secret_name" "$service_fqdn" "$ca_key" "$ca_cert"
    else
      create_secret "$secret_name" "$service_fqdn" "${certs_dir}/${service_fqdn}.crt" "${certs_dir}/${service_fqdn}.key" "$gitlab_namespace"
    fi
  done
}

create_client_certs_and_secrets() {
  local resource_name=${1:-certs} # certs or secrets
  local ca_key=${2:-"${certs_dir}/ca.key"}
  local ca_cert=${3:-"${certs_dir}/ca.crt"}
  local domain_name
  domain_name=$(yq '.domain_name' "$config_file")
  check_retrieved_value "domain_name" "$domain_name"
  local cn="client.${domain_name}"

  if [[ "$resource_name" == 'certs' ]]; then
    create_cert "$resource_name" \
      "$cn" \
      "$ca_key" \
      "$ca_cert"
  elif [[ "$resource_name" == 'secrets' ]]; then
    mapfile -t namespaces < <(get_enabled_charts_namespaces)
    for namespace in "${namespaces[@]}"; do
      if ! kubectl get secret client-tls -n "$namespace" >/dev/null 2>&1; then
        echo "Создаю секрет client-tls в namespace: $namespace"
        kubectl create secret generic client-tls -n "$namespace" \
          --from-file=client.crt="${certs_dir}/${cn}.crt" \
          --from-file=client.key="${certs_dir}/${cn}.key"
      else
        echo "Kubernetes secret client-tls в namespace: $namespace уже существует. Пропускаю создание."
      fi
    done
  fi
}

create_certs_and_secrets() {
  local resource_name=${1:-certs} # certs or secrets
  local ca_key=${2:-"${certs_dir}/ca.key"}
  local ca_cert=${3:-"${certs_dir}/ca.crt"}
  local config
  config=$(yq '.' "$config_file")
  local charts_count
  charts_count=$(echo "$config" | yq '.charts | length')
  local gitlab_namespace
  gitlab_namespace=$(yq '.charts[] | select(.name == "gitlab") | .namespace' "$config_file")

  if [[ "$resource_name" == 'secrets' ]]; then
    log_info_block "Создаю секреты в Kubernetes"
  fi

  if [[ "$resource_name" == 'certs' ]]; then
    create_ca_cert "$ca_key" "$ca_cert"
  else
    mapfile -t namespaces < <(get_enabled_charts_namespaces)
    for namespace in "${namespaces[@]}"; do
      echo "Создаю секрет ca-tls в namespace: ${namespace}"
      if ! kubectl create secret generic ca-tls --from-file=ca.crt="$ca_cert" --from-file=ca.key="$ca_key" -n "$namespace" -- 2>/dev/null; then
        echo "Kubernetes secret ca-tls в namespace: \"$namespace\" уже существует. Пропускаю создание."
      fi
    done
  fi

  for chart_index in $(seq 0 $((charts_count - 1))); do
    local chart_name
    chart_name=$(echo "$config" | yq ".charts[$chart_index].name")
    local chart_namespace
    chart_namespace=$(echo "$config" | yq ".charts[$chart_index].namespace")
    local chart_values
    chart_values=$(echo "$config" | yq ".charts[$chart_index].chart_values" 2>/dev/null)
    local chart_order
    chart_order=$(echo "$config" | yq ".charts[$chart_index].order")
    local chart_install_flag
    chart_install_flag=$(echo "$config" | yq ".charts[$chart_index].install")
    if [[ $chart_install_flag == "true" && "$chart_values" != "null" ]]; then
      local values_file="$tmp_dir/${chart_name}_values.yaml"
      echo "$chart_values" >"$values_file"
      if [[ $chart_name == 'gitlab' ]]; then
        create_gitlab_certs_and_secrets "$values_file" "${certs_dir}/ca.key" "${certs_dir}/ca.crt" "$resource_name"
        if [[ "$resource_name" != 'certs' ]]; then
          local gitlab_domain_name
          gitlab_domain_name=$(yq '.global.hosts.domain' "$values_file")
          local gitlab_runner_secret_name
          gitlab_runner_secret_name=$(yq '.gitlab-runner.certsSecretName' "$values_file")

          echo "Создаю секрет ${gitlab_runner_secret_name} из ${certs_dir}/gitlab.${gitlab_domain_name}.crt"
          if ! kubectl create secret generic "${gitlab_runner_secret_name}" \
            --from-file="gitlab.${gitlab_domain_name}.crt"="${certs_dir}/gitlab.${gitlab_domain_name}.crt" \
            -n "$chart_namespace" -- 2>/dev/null; then
            echo "Kubernetes secret ${gitlab_runner_secret_name} уже существует. Пропускаю создание."
          fi
        fi
      else
        local ingress_tls_count
        ingress_tls_count=$(yq '.. | select(has("ingress")) | .ingress.tls | length' "$values_file")
        for ingress_charts_count in $(seq 0 $((ingress_tls_count - 1))); do
          secret=$(yq ".. | select(has(\"ingress\")) | .ingress.tls[$ingress_charts_count].secretName // \"default-secret\"" "$values_file")
          alt_names=$(yq ".. | select(has(\"ingress\")) | .ingress.tls[$ingress_charts_count].hosts | to_entries | map(\"DNS.\" + (.key + 1 | tostring) + \" = \" + .value) | join(\"\n\")" "$values_file")
          cn=$(yq ".. | select(has(\"ingress\")) | .ingress.tls[$ingress_charts_count].hosts[0]" "$values_file")
          if [[ "$resource_name" == 'certs' ]]; then
            create_cert "$secret" "$cn" "$ca_key" "$ca_cert"
          else
            create_secret "$secret" "$cn" "${certs_dir}/${cn}.crt" "${certs_dir}/${cn}.key" "$chart_namespace"
          fi
        done
      fi
    fi
  done
}

generate_random_password() {
  if ! python3 -c "import secrets; print(secrets.token_urlsafe(50))"; then
    exit_on_error "Ошибка генерации пароля"
  fi
}

create_secret_from_random_password() {
  local secret_name=$1
  local username=$2
  local secret_key=$3
  local username_key=$4
  local namespace=$5
  local password
  password="$(generate_random_password)"

  log_info_block "Создаю секрет $secret_name для чарта $chart_name"

  if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
    kubectl create secret generic "$secret_name" \
      --from-literal="$username_key"="$username" \
      --from-literal="$secret_key=$password" \
      -n "$namespace"
  else
    echo "Секрет $secret_name уже существует. Пропускаем создание."
  fi
}

nexus_create_admin_password() {
  local nexus_yaml_file=$1
  local nexus_secret_name
  nexus_secret_name=$(yq '.rootPassword.secret' "$nexus_yaml_file")
  local nexus_secret_key
  nexus_secret_key=$(yq '.rootPassword.key' "$nexus_yaml_file")
  local nexus_secret_namespace
  nexus_secret_namespace=$(yq '.charts[] | select(.name == "nexus3") | .namespace' "$config_file")

  if [[ "$nexus_secret_name" != "null" && "$nexus_secret_key" != "null" ]]; then
    create_secret_from_random_password "$nexus_secret_name" "admin" "$nexus_secret_key" "username" "$nexus_secret_namespace"
  fi
}

create_gpg_keypair() {
  local name_real=$1
  local name_email=$2
  local tmp_dir=$3
  local gpg_public_key=$4
  local gpg_private_key=$5

  gpg --homedir "$tmp_dir" --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: $name_real
Name-Email: $name_email
Expire-Date: 0
%no-protection
EOF

  local KEY_ID
  KEY_ID=$(gpg --homedir "$tmp_dir" --list-keys --with-colons | grep pub | head -n 1 | cut -d: -f5)

  if [ -z "$KEY_ID" ]; then
    exit_on_error "Ошибка при получении ID GPG ключа"
  fi

  gpg --homedir "$tmp_dir" --armor --output "${tmp_dir}/${gpg_public_key}" --export "$KEY_ID"
  gpg --homedir "$tmp_dir" --armor --output "${tmp_dir}/${gpg_private_key}" --export-secret-key "$KEY_ID"

  gpg_keys["public_key"]="${tmp_dir}/${gpg_public_key}"
  gpg_keys["private_key"]="${tmp_dir}/${gpg_private_key}"
}

nexus_create_gpg_secret_apt_repo() {
  declare -A gpg_keys

  local config_file=$1
  local nexus_custom_values
  nexus_custom_values=$(yq -r '.charts[] | select(.name == "nexus3") | .custom_values' "$config_file")
  local nexus_secret_namespace
  nexus_secret_namespace=$(yq -r '.charts[] | select(.name == "nexus3") | .namespace' "$config_file")

  if [[ $nexus_custom_values != "null" ]]; then
    local k8s_secret
    k8s_secret=$(echo "$nexus_custom_values" | yq -r '.apt-hosted-repos.k8s-secret')

    if kubectl get secret "$k8s_secret" -n "$nexus_secret_namespace" &>/dev/null; then
      log_info_block "Секрет '$k8s_secret' c gpg ключами для APT репозиториев в NEXUS уже существует. Пропускаем создание."
    else
      local gpg_public_key
      gpg_public_key=$(echo "$nexus_custom_values" | yq -r '.apt-hosted-repos.gpg-public-key')
      local gpg_private_key
      gpg_private_key=$(echo "$nexus_custom_values" | yq -r '.apt-hosted-repos.gpg-private-key')

      log_info_block "Создаю gpg ключи для APT репозиториев в NEXUS"
      create_gpg_keypair "AptRepository" "info@itkey.com" "$tmp_dir" "$gpg_public_key" "$gpg_private_key"

      log_info_block "Создаю kubernetes secret $k8s_secret с gpg ключами для APT репозиториев в NEXUS"
      kubectl create secret generic "$k8s_secret" \
        --from-file="$gpg_public_key=${gpg_keys[public_key]}" \
        --from-file="$gpg_private_key=${gpg_keys[private_key]}" \
        -n "$nexus_secret_namespace"
    fi
  fi
}

check_pod_running() {
  local pod_namespace=$1
  local pod_name=$2

  local running_status
  running_status=$(kubectl get pod -n "$pod_namespace" "$pod_name" -o jsonpath="{.status.phase}")

  if [[ $? -eq 0 && "$running_status" == "Running" ]]; then
    return 0
  else
    return 1
  fi
}

check_pod_ready() {
  local pod_namespace=$1
  local pod_name=$2

  local ready_status
  ready_status=$(kubectl get pod -n "$pod_namespace" "$pod_name" -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}")

  if [[ $? -eq 0 && "$ready_status" == "True" ]]; then
    return 0
  else
    return 1
  fi
}

wait_for_pod() {
  local attempt=0
  local pod_namespace=$1
  local pod_name=$2
  local check_type=$3 # "running" или "ready"
  local sleep_interval=${4:-5}
  local max_attempts=${5:-60}
  local success_count=0
  local required_success_count=3

  echo "Ожидаю появления пода \"$pod_name\""

  case "$check_type" in
  "running") local check_function="check_pod_running" ;;
  "ready") local check_function="check_pod_ready" ;;
  esac

  while [[ $attempt -lt $max_attempts ]]; do
    if [ -n "$pod_name" ]; then
      if $check_function "$pod_namespace" "$pod_name"; then
        success_count=$((success_count + 1))
        printf "\r\033[KПод \"$pod_name\" находится в состоянии \"${check_type^}\" (%d/%d)" "$success_count" "$required_success_count"
        if [ $success_count -ge $required_success_count ]; then
          echo -e "\nПод \"$pod_name\" стабилен. Состояние: \"${check_type^}\""
          return 0
        fi
      else
        success_count=0
        printf "\rОжидаю под \"$pod_name\" в состояние \"${check_type^}\". Попытка: (%d/%d)" "$((attempt + 1))" "$max_attempts"
      fi
    fi
    attempt=$((attempt + 1))
    sleep "$sleep_interval"
  done

  exit_on_error "Превышено максимальное количество попыток ожидания пода $pod_name в namespace $pod_namespace."
}

countdown() {
  local time_left="$1"
  while [ "$time_left" -gt 0 ]; do
    printf "\rОсталось %d секунд..." "$time_left"
    sleep 1
    time_left=$((time_left - 1))
  done
  printf "\n"
}

get_kubectl_secret_data() {
  local secret_name="$1"
  local secret_key="$2"
  local namespace="$3"
  local kubectl_output

  secret_key=$(echo "$secret_key" | sed 's/\./\\./g')
  kubectl_output=$(kubectl get secret "${secret_name}" -o jsonpath="{.data.${secret_key}}" -n "$namespace")

  if [[ $? -ne 0 ]]; then
    exit_on_error "Не удалось получить секрет ${secret_name} или ключ ${secret_key} отсутствует"
  fi
  echo "$kubectl_output" | base64 --decode
}

configure_vault() {
  local config_file="$1"
  local pod_index="0"
  local vault_namespace
  vault_namespace=$(yq '.charts[] | select(.name == "vault") | .namespace' "$config_file")
  local vault_init_output=""
  local chart_name="vault"
  local vault_install_flag
  vault_install_flag=$(yq -r ".charts[] | select(.name == \"${chart_name}\") | .install" "$config_file")

  check_retrieved_value "vault_install_flag" "$vault_install_flag"

  if [[ $vault_install_flag == false ]]; then
    return
  fi

  local vault_ha_flag
  vault_ha_flag=$(yq ".charts[] | select(.name == \"${chart_name}\") | .chart_values | from_yaml | .server.ha.enabled" "$config_file")
  check_retrieved_value "vault_ha_flag" "$vault_ha_flag"

  if [[ $upgrade_flag == true ]]; then
    log_info_block "Перезапускаю Vault"
    kubectl delete pod -l app.kubernetes.io/instance="${chart_name}" --grace-period 0 --force -n "$vault_namespace" -- 2>/dev/null
  fi

  log_info_block "Настраиваю Vault"

  local vault_chart_values
  vault_chart_values=$(yq -r ".charts[] | select(.name == \"${chart_name}\") | .chart_values" "$config_file")
  local vault_custom_values
  vault_custom_values=$(yq -r ".charts[] | select(.name == \"${chart_name}\") | .custom_values" "$config_file")
  local vault_secret_name
  vault_secret_name=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.name')
  local vault_secret_unseal_key1
  vault_secret_unseal_key1=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.key1')
  local vault_secret_unseal_key2
  vault_secret_unseal_key2=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.key2')
  local vault_secret_unseal_key3
  vault_secret_unseal_key3=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.key3')
  local vault_secret_unseal_key4
  vault_secret_unseal_key4=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.key4')
  local vault_secret_unseal_key5
  vault_secret_unseal_key5=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.key5')
  local vault_secret_initial_root_token
  vault_secret_initial_root_token=$(echo "$vault_custom_values" | yq -r '.vault-unseal-secret.initial-root-token')

  declare -A vault_vars=(
    [vault_chart_values]="$vault_chart_values"
    [vault_custom_values]="$vault_custom_values"
    [vault_secret_name]="$vault_secret_name"
    [vault_secret_unseal_key1]="$vault_secret_unseal_key1"
    [vault_secret_unseal_key2]="$vault_secret_unseal_key2"
    [vault_secret_unseal_key3]="$vault_secret_unseal_key3"
    [vault_secret_unseal_key4]="$vault_secret_unseal_key4"
    [vault_secret_unseal_key5]="$vault_secret_unseal_key5"
    [vault_secret_initial_root_token]="$vault_secret_initial_root_token"
  )

  for vault_var_name in "${!vault_vars[@]}"; do
    check_retrieved_value "$vault_var_name" "${vault_vars[$vault_var_name]}"
  done
  # Если есть секрет, получаем ключи из Kubernetes
  if kubectl get secret "$vault_secret_name" -n "$vault_namespace" &>/dev/null; then
    echo "Секрет ${vault_secret_name} уже существует. Пропускаю создание."
    local from_k8s_unseal_key1
    from_k8s_unseal_key1=$(get_kubectl_secret_data "${vault_secret_name}" "${vault_secret_unseal_key1}" "${vault_namespace}")
    local from_k8s_unseal_key2
    from_k8s_unseal_key2=$(get_kubectl_secret_data "${vault_secret_name}" "${vault_secret_unseal_key2}" "${vault_namespace}")
    local from_k8s_unseal_key3
    from_k8s_unseal_key3=$(get_kubectl_secret_data "${vault_secret_name}" "${vault_secret_unseal_key3}" "${vault_namespace}")

    declare -A vault_vars=(
      [from_k8s_unseal_key1]="$from_k8s_unseal_key1"
      [from_k8s_unseal_key2]="$from_k8s_unseal_key2"
      [from_k8s_unseal_key3]="$from_k8s_unseal_key3"
    )
    for vault_var_name in "${!vault_vars[@]}"; do
      check_retrieved_value "$vault_var_name" "${vault_vars[$vault_var_name]}"
    done
    local vault_init_output_unseal_keys=("$from_k8s_unseal_key1" "$from_k8s_unseal_key2" "$from_k8s_unseal_key3")
  else
    # Если нет секрета, то выполняем начальную инициализацию
    echo "Начальная инициализация хранилища пода vault-${pod_index} в namespace ${vault_namespace}"
    if wait_for_pod "$vault_namespace" "vault-${pod_index}" "running"; then
      vault_init_output=$(kubectl exec -i "vault-${pod_index}" -n "$vault_namespace" -- vault operator init) ||
        exit_on_error "Ошибка инициализации хранилища пода vault-${pod_index} в namespace ${vault_namespace}"
    fi

    check_retrieved_value "vault_init_output" "$vault_init_output"

    local vault_init_output_unseal_key_1
    vault_init_output_unseal_key_1=$(echo "$vault_init_output" | grep 'Unseal Key 1:' | awk '{print $4}')
    local vault_init_output_unseal_key_2
    vault_init_output_unseal_key_2=$(echo "$vault_init_output" | grep 'Unseal Key 2:' | awk '{print $4}')
    local vault_init_output_unseal_key_3
    vault_init_output_unseal_key_3=$(echo "$vault_init_output" | grep 'Unseal Key 3:' | awk '{print $4}')
    local vault_init_output_unseal_key_4
    vault_init_output_unseal_key_4=$(echo "$vault_init_output" | grep 'Unseal Key 4:' | awk '{print $4}')
    local vault_init_output_unseal_key_5
    vault_init_output_unseal_key_5=$(echo "$vault_init_output" | grep 'Unseal Key 5:' | awk '{print $4}')
    local vault_init_output_root_token
    vault_init_output_root_token=$(echo "$vault_init_output" | grep 'Initial Root Token:' | awk '{print $4}')

    declare -A vault_vars=(
      [vault_init_output]="$vault_init_output"
      [vault_init_output_unseal_key_1]="$vault_init_output_unseal_key_1"
      [vault_init_output_unseal_key_2]="$vault_init_output_unseal_key_2"
      [vault_init_output_unseal_key_3]="$vault_init_output_unseal_key_3"
      [vault_init_output_unseal_key_4]="$vault_init_output_unseal_key_4"
      [vault_init_output_unseal_key_5]="$vault_init_output_unseal_key_5"
      [vault_init_output_root_token]="$vault_init_output_root_token"
    )

    for vault_var_name in "${!vault_vars[@]}"; do
      check_retrieved_value "$vault_var_name" "${vault_vars[$vault_var_name]}"
    done

    log_info_block "Создаю секрет $vault_secret_name с ключами разблокировки хранилища"
    kubectl create secret generic "$vault_secret_name" \
      --from-literal="$vault_secret_unseal_key1=$vault_init_output_unseal_key_1" \
      --from-literal="$vault_secret_unseal_key2=$vault_init_output_unseal_key_2" \
      --from-literal="$vault_secret_unseal_key3=$vault_init_output_unseal_key_3" \
      --from-literal="$vault_secret_unseal_key4=$vault_init_output_unseal_key_4" \
      --from-literal="$vault_secret_unseal_key5=$vault_init_output_unseal_key_5" \
      --from-literal="$vault_secret_initial_root_token=$vault_init_output_root_token" \
      -n "$vault_namespace"

    local vault_init_output_unseal_keys=("$vault_init_output_unseal_key_1" "$vault_init_output_unseal_key_2" "$vault_init_output_unseal_key_3")
  fi
  # Процесс разблокировки
  if [[ $vault_ha_flag == true ]]; then
    local vault_ha_replicas
    vault_ha_replicas=$(echo "$vault_chart_values" | yq -r '.server.ha.replicas')
    check_retrieved_value "vault_ha_replicas" "$vault_ha_replicas"
  else
    vault_ha_replicas=1
  fi

  for pod_index in $(seq 0 $(($vault_ha_replicas - 1))); do
    log_info_block "Проверяю готовность vault-${pod_index} к разблокировке хранилища"
    if wait_for_pod "$vault_namespace" "vault-${pod_index}" "running"; then
      for key_index in "${!vault_init_output_unseal_keys[@]}"; do
        local unseal_key="${vault_init_output_unseal_keys[$key_index]}"
        log_info_block "Разблокирую vault-${pod_index} ключом unseal-key $((key_index + 1))"
        kubectl exec -i "vault-${pod_index}" -n "$vault_namespace" -- vault operator unseal "$unseal_key" ||
          exit_on_error "Ошибка разблокировки vault-${pod_index} ключом unseal-key $((key_index + 1))"
      done
    fi
  done
}

fix_path_in_sberlinux() {
  log_info_block "Применяю временное решение для \$PATH в SberLinux"

  cat <<'EOF' >"${tmp_dir}"/k0s-path-fix.sh
#!/bin/bash

  os_id=$(awk -F '=' '/^ID=/ {gsub(/"/, "", $2); print $2}' /etc/os-release)

  if [[ "$os_id" != 'sberlinux' ]]; then
    echo "ОС не SberLinux, пропускаем fix для \$PATH"
  else
    if [[ -L /usr/bin/k0s ]]; then
      echo "Символическая ссылка на бинарный файл k0s уже существует."
    else
      if ! sudo ln -sf /usr/local/bin/k0s /usr/bin/k0s; then
        echo "Ошибка при создании символической ссылки для k0s."
      else
        echo "Символическая ссылка на бинарный файл k0s успешно создана."
      fi
    fi
  fi
EOF

  local ssh_username
  ssh_username=$(yq '.ssh_username' "${config_file}")

  if [[ "$ssh_username" == "null" ]]; then
    exit_on_error "Ошибка: при извлечении значения ключа ssh_username из ${config_file}"
  fi

  for host in $(yq '. | with_entries(select(.key | test("^fqdn_cp"))) | .[]' "${config_file}"); do
    if [[ "$host" == "null" ]]; then
      exit_on_error "Ошибка: при извлечении значения ключей fqdn_cp* из ${config_file}"
    else
      echo "Копирую на хост ${host} скрипт ${tmp_dir}/k0s-path-fix.sh в каталог /tmp"
      scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${tmp_dir}/k0s-path-fix.sh" "${ssh_username}@${host}:/tmp/"
      echo "Выполняю на хосте ${host} скрипт /tmp/k0s-path-fix.sh"
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "${ssh_username}@${host}" 'bash /tmp/k0s-path-fix.sh'
      echo "Удаляю на хосте ${host} скрипт /tmp/k0s-path-fix.sh"
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=quiet "${ssh_username}@${host}" 'bash -c "rm -fr /tmp/k0s-path-fix.sh"'
    fi
  done
}

wait_for_resource_ready() {
  local resource_type="$1"
  local namespace="$2"
  local resource_name="$3"
  local attempts=0
  local sleep_interval=${4:-5}
  local max_attempts=${5:-60}

  while [[ $attempts -lt $max_attempts ]]; do
    if [[ "$resource_type" == "job" ]]; then
      local job_status
      job_status=$(kubectl get job "$resource_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')

      if [[ "$job_status" == "True" ]]; then
        printf "\033[2K\rjob %s завершена успешно\n" "$resource_name"
        break
      else
        printf "\rОжидаю завершения job $resource_name. Попытка: (%d/%d)" "$attempts" "$max_attempts"
      fi
    elif [[ "$resource_type" == "postgresql" ]]; then
      local postgresql_status
      postgresql_status=$(kubectl get "$resource_type" -n "$namespace" "$resource_name" -o jsonpath='{.status.PostgresClusterStatus}')

      if [[ "$postgresql_status" == "Running" ]]; then
        printf "\033[2K\rКластер PostgreSQL в namespace: %s в состоянии: %s\n" "$namespace" "$postgresql_status"
        break
      else
        printf "\rОжидаю готовности кластера PostgreSQL в namespace: %s. Попытка: (%d/%d)" "$namespace" "$attempts" "$max_attempts"
      fi
    else
      local current_ready_status
      current_ready_status=$(kubectl get "$resource_type" -n "$namespace" "$resource_name" -o jsonpath='{.status.readyReplicas}')

      if [[ $? -eq 0 && -z "$current_ready_status" ]]; then
        current_ready_status=0
      fi

      local expected_ready_status
      expected_ready_status=$(kubectl get "$resource_type" -n "$namespace" "$resource_name" -o jsonpath='{.status.replicas}')

      if [[ $? -eq 0 && -z "$expected_ready_status" ]]; then
        echo "Ошибка получения общего количества подов в $resource_type $resource_name"
        return 1
      fi

      if [[ "$current_ready_status" -eq "$expected_ready_status" ]]; then
        printf "\033[2K\r%s %s готов: %d/%d подов готовы\n" "$resource_type" "$resource_name" "$current_ready_status" "$expected_ready_status"
        break
      else
        printf "\rТекущий статус %s %s: (%d/%d). Попытка проверки: (%d/%d)" "$resource_type" "$resource_name" "$current_ready_status" "$expected_ready_status" "$attempts" "$max_attempts"
      fi
    fi
    sleep "$sleep_interval"
    let attempts=attempts+1
  done

  if [[ $attempts -eq $max_attempts ]]; then
    printf "\nПревышено максимальное количество попыток %d для %s %s. Ресурс не готов." "$max_attempts" "$resource_type" "$resource_name"
    exit 1
  fi
}

check_retrieved_value() {
  local checked_var_name="$1"
  local checked_var_value="$2"

  if [[ "$checked_var_value" == 'null' || -z "$checked_var_value" ]]; then
    exit_on_error "Ошибка при получении значения переменной: ${checked_var_name} = ${checked_var_value}"
  fi
}

curl_cmd() {
  local metod="$1"
  local url
  url="$(echo -n "$2" | tr -d '\r\n')"
  local json="${3:-}"

  local http_code
  local response

  local base_req
  base_req=(
    curl -s -L -w "%{http_code}"
    --cacert "${tmp_dir}/ca.crt"
    --cert "${tmp_dir}/client.crt"
    --key "${tmp_dir}/client.key"
    -u "admin:${nexus_from_k8s_admin_password}"
    -X "$metod" "$url"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
  )

  if [[ ${metod^^} == "PUT" || ${metod^^} == "POST" ]]; then
    response=$("${base_req[@]}" -d "$json")
  else
    response=$("${base_req[@]}")
  fi

  local http_code=${response: -3}
  local response_body=${response::-3}

  if [[ $http_code -eq 200 || $http_code -eq 204 ]]; then
    echo "Успешно. Код: $http_code" >&2

    if [[ "${metod^^}" != "DELETE" && $http_code -ne 204 ]]; then
      echo "$response_body"
    fi
  else
    exit_on_error "Ошибка: Код $http_code"
  fi
}

configure_nexus() {
  local config_file=$1
  local chart_name='nexus3'

  local nexus_chart_install_flag
  nexus_chart_install_flag=$(yq ".charts[] | select(.name == \"${chart_name}\") | .install" "$config_file")
  check_retrieved_value "nexus_chart_install_flag" "${nexus_chart_install_flag}"

  log_info_block "Настраиваю Nexus"
  local nexus_chart_namespace
  nexus_chart_namespace=$(yq ".charts[] | select(.name == \"${chart_name}\") | .namespace" "$config_file")
  local nexus_chart_custom_values
  nexus_chart_custom_values=$(yq ".charts[] | select(.name == \"${chart_name}\") | .custom_values" "$config_file")
  local nexus_chart_k8s_secret
  nexus_chart_k8s_secret=$(echo "$nexus_chart_custom_values" | yq '.apt-hosted-repos.k8s-secret')
  local nexus_chart_gpg_private_key
  nexus_chart_gpg_private_key=$(echo "$nexus_chart_custom_values" | yq '.apt-hosted-repos.gpg-private-key')
  local nexus_chart_chart_values
  nexus_chart_chart_values=$(yq ".charts[] | select(.name == \"${chart_name}\") | .chart_values" "$config_file")
  local nexus_chart_fqdn
  nexus_chart_fqdn=$(echo "$nexus_chart_chart_values" | yq '.ingress.hosts[0]')
  local nexus_chart_root_password_secret_name
  nexus_chart_root_password_secret_name=$(echo "$nexus_chart_chart_values" | yq '.rootPassword.secret')
  local nexus_chart_root_password_key
  nexus_chart_root_password_key=$(echo "$nexus_chart_chart_values" | yq '.rootPassword.key')
  local nexus_from_k8s_admin_password
  nexus_from_k8s_admin_password=$(kubectl get secret "${nexus_chart_root_password_secret_name}" -o jsonpath="{.data.${nexus_chart_root_password_key}}" -n "$nexus_chart_namespace" | base64 --decode)
  local nexus_from_k8s_gpg_private_key
  nexus_from_k8s_gpg_private_key=$(kubectl get secret "${nexus_chart_k8s_secret}" -o jsonpath="{.data.${nexus_chart_gpg_private_key}}" -n "$nexus_chart_namespace" | base64 --decode | tr -d '\n')
  local from_k8s_ca_cert
  from_k8s_ca_cert=$(kubectl get secrets ca-tls -o jsonpath='{.data.ca\.crt}' -n "$nexus_chart_namespace" | base64 -d)
  local from_k8s_client_cert
  from_k8s_client_cert=$(kubectl get secrets client-tls -o jsonpath='{.data.client\.crt}' -n "$nexus_chart_namespace" | base64 -d)
  local from_k8s_client_key
  from_k8s_client_key=$(kubectl get secrets client-tls -o jsonpath='{.data.client\.key}' -n "$nexus_chart_namespace" | base64 -d)

  mapfile -t nexus_chart_chart_docker_repo_names < <(echo "$nexus_chart_chart_values" | yq '.config.repos[] | select(.format == "docker" and .type == "hosted") | .name')

  declare -A nexus_vars=(
    [nexus_chart_namespace]="$nexus_chart_namespace"
    [nexus_chart_custom_values]="$nexus_chart_custom_values"
    [nexus_chart_k8s_secret]="$nexus_chart_k8s_secret"
    [nexus_chart_gpg_private_key]="$nexus_chart_gpg_private_key"
    [nexus_chart_chart_values]="$nexus_chart_chart_values"
    [nexus_chart_fqdn]="$nexus_chart_fqdn"
    [nexus_chart_root_password_secret_name]="$nexus_chart_root_password_secret_name"
    [nexus_chart_root_password_key]="$nexus_chart_root_password_key"
    [nexus_from_k8s_admin_password]="$nexus_from_k8s_admin_password"
    [nexus_from_k8s_gpg_private_key]="$nexus_from_k8s_gpg_private_key"
    [from_k8s_ca_cert]="$from_k8s_ca_cert"
    [from_k8s_client_cert]="$from_k8s_client_cert"
    [from_k8s_client_key]="$from_k8s_client_key"
    [nexus_chart_chart_docker_repo_names[0]]="${nexus_chart_chart_docker_repo_names[0]}"
  )

  for nexus_var_name in "${!nexus_vars[@]}"; do
    check_retrieved_value "$nexus_var_name" "${nexus_vars[$nexus_var_name]}"
  done

  wait_for_resource_ready "statefulset" "$nexus_chart_namespace" "$chart_name"

  local from_k8s_job_name
  from_k8s_job_name=$(kubectl get jobs -l app.kubernetes.io/instance="${chart_name}" -o jsonpath='{.items[0].metadata.name}' -n "$nexus_chart_namespace") ||
    exit_on_error "Ошибка не удалось получить имя job из Kubernetes"
  wait_for_resource_ready "job" "$nexus_chart_namespace" "$from_k8s_job_name"

  printf "%s\n" "$from_k8s_ca_cert" >"$tmp_dir"/ca.crt
  printf "%s\n" "$from_k8s_client_cert" >"$tmp_dir"/client.crt
  printf "%s\n" "$from_k8s_client_key" >"$tmp_dir"/client.key

  # Устанавливаю gpg ключи
  echo "Получаю список APT репозиториев"

  declare -A apt_repo_distributions
  while IFS= read -r line; do
    local name
    name=$(echo "$line" | awk '{print $1}')
    local distribution
    distribution=$(echo "$line" | awk '{print $2}')
    apt_repo_distributions["$name"]="$distribution"
  done < <(echo "$nexus_chart_chart_values" | yq '.config.repos[] | select(.format == "apt") | .name + " " + .apt.distribution')

  if [[ ${#apt_repo_distributions[@]} -eq 0 ]]; then
    exit_on_error "Ошибка получения APT репозиториев из chart_values"
  fi

  for apt_repo_name in "${!apt_repo_distributions[@]}"; do
    echo "Добавляю закрытый gpg ключ в apt репозиторий ${apt_repo_name}"
    local json_string
    json_string=$(
      cat <<EOF
{
  "name": "${apt_repo_name}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow_once"
  },
  "cleanup": {
    "policyNames": [
      "string"
    ]
  },
  "component": {
    "proprietaryComponents": true
  },
  "apt": {
    "distribution": "${apt_repo_distributions[$apt_repo_name]}"
  },
  "aptSigning": {
    "keypair": "${nexus_from_k8s_gpg_private_key}",
    "passphrase": ""
  }
}
EOF
    )
    curl_cmd "PUT" "https://${nexus_chart_fqdn}/service/rest/v1/repositories/apt/hosted/${apt_repo_name}" "$json_string"
  done

  # Удаляю maven и nuget репы
  echo "Получаю список репозиториев формата nuget, maven2"

  mapfile -t delete_repo_names < <(
    curl_cmd 'GET' "https://${nexus_chart_fqdn}/service/rest/v1/repositories" |
      jq -r '.[] | select(.format == "nuget" or .format == "maven2") | .name'
  )

  if [[ ${#delete_repo_names[@]} -eq 0 ]]; then
    echo "Не найдены репозитории формата 'nuget' или 'maven2'. Пропускаем..."
  fi

  for delete_repo_name in "${delete_repo_names[@]}"; do
    echo "Удаляю репозиторий ${delete_repo_name}"
    curl_cmd 'DELETE' "https://${nexus_chart_fqdn}/service/rest/v1/repositories/${delete_repo_name}"
  done
}

create_namespace_cmd() {
  local namespace="$1"

  if [[ "$namespace" != 'default' ]]; then
    if ! kubectl get namespace "${namespace}" >/dev/null 2>&1; then
      echo "Создаю \"namespace\": ${namespace}"
      kubectl create namespace "${namespace}"
    else
      echo "namespace: \"${namespace}\" уже существует. Пропускаю создание."
    fi
  fi
}

get_enabled_charts_namespaces() {
  #Возвращает список уникальных namespace строками
  #Для вызова функции в массив с помощью mapfile -t
  mapfile -t charts_mappings < <(yq -o=j -I=0 '.charts[]' "$config_file")
  local charts_namespaces=()
  for id_mapping in "${charts_mappings[@]}"; do
    local install_flag
    install_flag=$(echo "$id_mapping" | yq '.install' -)
    if [[ "${install_flag,,}" == "true" ]]; then
      local namespace
      namespace=$(echo "$id_mapping" | yq '.namespace' -)
      charts_namespaces+=("$namespace")
    fi
  done
  mapfile -t unique_namespaces < <(printf "%s\n" "${charts_namespaces[@]}" | sort -u)
  printf "%s\n" "${unique_namespaces[@]}"
}

create_namespaces() {
  log_info_block "Создаю namespaces"
  create_namespace_cmd "$root_ca_cert_namespace"
  mapfile -t namespaces < <(get_enabled_charts_namespaces)
  for namespace in "${namespaces[@]}"; do
    create_namespace_cmd "$namespace"
  done
}

create_cronjobs() {
  local config_file="$1"
  local vip
  vip=$(yq '.cp_vip' "$config_file")
  local nexus_template_file="cronjobs/nexus/cronjob.j2"
  local nexus_namespace
  nexus_namespace=$(yq '.charts[] | select(.name == "nexus3") | .namespace' "$config_file")
  local gitlab_template_file="cronjobs/gitlab/cronjob.j2"
  local gitlab_namespace
  gitlab_namespace=$(yq '.charts[] | select(.name == "gitlab") | .namespace' "$config_file")

  declare -A check_vars=(
    [nexus_namespace]="$nexus_namespace"
    [gitlab_namespace]="$gitlab_namespace"
  )

  for check_var_name in "${!check_vars[@]}"; do
    check_retrieved_value "$check_var_name" "${check_vars[$check_var_name]}"
  done

  if [[ $vip == 'null' ]]; then
    return
  fi

  log_info_block "Применяю WA для HA Gitlay и Nexus"

  declare -A cronjobs=(
    ["${nexus_template_file}"]="$nexus_namespace"
    ["${gitlab_template_file}"]="$gitlab_namespace"
  )

  for cronjob_template_file in "${!cronjobs[@]}"; do
    local cronjob_namespace="${cronjobs[$cronjob_template_file]}"
    if ! kubectl get cronjobs -n "$cronjob_namespace" -- 2>/dev/null | grep -q 'terminating-state-check'; then
      echo "Создаю манифест cronjobs для ${cronjob_namespace} из ${tmp_dir}/${cronjob_namespace}-cronjobs.yaml"
      if ! jinja -d "$config_file" "$cronjob_template_file" >"${tmp_dir}/${cronjob_namespace}-cronjobs.yaml"; then
        exit_on_error "Ошибка создания манифеста ${tmp_dir}/cronjobs.yaml"
      fi

      echo "Применяю манифест cronjobs для ${cronjob_namespace} из ${tmp_dir}/${cronjob_namespace}-cronjobs.yaml"
      if ! kubectl create -f "${tmp_dir}/${cronjob_namespace}-cronjobs.yaml"; then
        exit_on_error "Ошибка применения манифеста ${tmp_dir}/cronjobs.yaml"
      fi
    else
      echo "Cronjob уже существует в namespace: ${cronjob_namespace}. Пропускаю создание..."
    fi
  done
}

add_volume_group_snapshot_APIs() {
  if ! kubectl get deployments.apps snapshot-controller snapshot-controller -n kube-system >/dev/null 2>&1; then
    log_info_block "Добавляю Volume Group Snapshot APIs в Kubernetes"
    kubectl kustomize configs/external-snapshotter/crd | kubectl create -f -
    kubectl kustomize -n kube-system configs/external-snapshotter/snapshot-controller | kubectl create -f -
  fi
}

create_main_config_file() {
  log_info_block "Создаю основной конфигурационный файл"

  check_file_exists "$lcm_config_file"
  local ldap_enable_flag
  ldap_enable_flag=$(yq '.ldap_enable' "$lcm_config_file")

  if [[ "${ldap_enable_flag,,}" == "true" && $order_value != "1" ]]; then
    local ldap_ca_cert_file
    ldap_ca_cert_file=$(yq '.ldap_ca_cert_file' "$lcm_config_file")
    check_file_exists "$ldap_ca_cert_file"
    local ldap_ca_cert_file_data
    ldap_ca_cert_file_data=$(cat "$ldap_ca_cert_file")
    jinja -D ldap_ca_cert_data "$ldap_ca_cert_file_data" -d "$lcm_config_file" "$config_template_file" >"${tmp_dir}/main-config-tmp.yaml"
  else
    jinja -d "$lcm_config_file" "$config_template_file" >"${tmp_dir}/main-config-tmp.yaml"
  fi

  cat "$lcm_config_file" "${tmp_dir}/main-config-tmp.yaml" >"${tmp_dir}/$config_file"

  if [[ -f "$config_file" ]]; then
    if ! cmp -s "$config_file" "${tmp_dir}/$config_file"; then
      mv "${tmp_dir}/$config_file" "$config_file"
      echo "Файл конфигурации: $config_file обновлен"
    else
      echo "Файл конфигурации: $config_file не изменился"
    fi
  else
    mv "${tmp_dir}/$config_file" "$config_file"
    echo "Файл конфигурации: $config_file создан успешно"
  fi
}

create_gitlab_ad_ca_file_secret() {
  local ldap_enable_flag
  ldap_enable_flag=$(yq '.ldap_enable' "$lcm_config_file")
  if [[ "${ldap_enable_flag,,}" == "true" ]]; then
    log_info_block "Создаю секрет корневого сертификата Active Directory"
    local gitlab_namespace
    gitlab_namespace=$(yq '.charts[] | select(.name == "gitlab") | .namespace' "$config_file")
    check_retrieved_value "gitlab_namespace" "$gitlab_namespace"
    if ! kubectl get secret -n "$gitlab_namespace" gitlab-custom-ca -- 2>/dev/null; then
      local ldap_ca_cert_file
      ldap_ca_cert_file=$(yq '.ldap_ca_cert_file' "$lcm_config_file")
      check_retrieved_value "ldap_ca_cert_file" "$ldap_ca_cert_file"
      check_file_exists "$ldap_ca_cert_file"
      kubectl create -n "$gitlab_namespace" secret generic gitlab-custom-ca \
        --from-file=ldap-root-cert.crt="$ldap_ca_cert_file"
    else
      echo -e "Секрет корневого сертификата Active Directory уже существует.\nПропускаю создание."
    fi
  fi
}

apply_config_cmd() {
  local config_file=$1
  local namespace=$2

  echo "Применяем конфигурацию из $config_file"
  check_file_exists "$config_file"

  if ! kubectl apply -n "$namespace" -f "$config_file"; then
    exit_on_error "Ошибка применения конфигурации для $config_file"
  fi
}

create_postgresql_clusters() {
  log_info_block "Создаю кластеры PostgreSQL"
  local postgres_operator_labels="app.kubernetes.io/instance=postgres-operator,app.kubernetes.io/name=postgres-operator"
  local postgres_operator_namespace
  postgres_operator_namespace=$(yq '.charts[] | select(.name == "postgres-operator") | .namespace' "$config_file")
  local postgres_operator_deployment_name
  postgres_operator_deployment_name=$(kubectl get deployment -n "$postgres_operator_namespace" -l $postgres_operator_labels -o=jsonpath="{.items[0].metadata.name}")
  local netbox_namespace
  netbox_namespace=$(yq '.charts[] | select(.name == "netbox") | .namespace' "$config_file")
  local netbox_template_file
  netbox_template_file="configs/postgres-operator/netbox/netbox-cluster.j2"
  local gitlab_namespace
  gitlab_namespace=$(yq '.charts[] | select(.name == "gitlab") | .namespace' "$config_file")
  local gitlab_template_file="configs/postgres-operator/gitlab/gitlab-cluster.j2"
  local grafana_namespace
  grafana_namespace=$(yq '.charts[] | select(.name == "vmks") | .namespace' "$config_file")
  local grafana_template_file="configs/postgres-operator/grafana/grafana-cluster.j2"

  declare -A check_vars=(
    [postgres_operator_namespace]="$postgres_operator_namespace"
    [postgres_operator_deployment_name]="$postgres_operator_deployment_name"
    [netbox_namespace]="$netbox_namespace"
    [gitlab_namespace]="$gitlab_namespace"
    [grafana_namespace]="$grafana_namespace"
  )

  for check_var_name in "${!check_vars[@]}"; do
    check_retrieved_value "$check_var_name" "${check_vars[$check_var_name]}"
  done

  declare -A clusters=(
    ["${netbox_template_file}"]="$netbox_namespace"
    ["${gitlab_template_file}"]="$gitlab_namespace"
    ["${grafana_template_file}"]="$grafana_namespace"
  )

  wait_for_resource_ready "deployment" "$postgres_operator_namespace" "$postgres_operator_deployment_name"

  for cluster_conf_file in "${!clusters[@]}"; do
    local cluster_namespace="${clusters[$cluster_conf_file]}"
    echo "Создаю PostgreSQL кластер в namespace: $cluster_namespace"

    jinja -d "$config_file" "$cluster_conf_file" >"$tmp_dir/${cluster_namespace}-db.yaml"
    apply_config_cmd "$tmp_dir/${cluster_namespace}-db.yaml" "$cluster_namespace"
    wait_for_resource_ready postgresql "$cluster_namespace" postgresql-cluster
  done
}

apply_config_metallb_system() {
  log_info_block "Настраиваю LoadBalancer MetalLB"
  local metallb_system_labels="app.kubernetes.io/component=controller,app.kubernetes.io/instance=metallb"
  local metallb_system_config_file="${tmp_dir}/L2-pool-config.yaml"
  local metallb_system_namespace
  metallb_system_namespace=$(yq '.charts[] | select(.name == "metallb") | .namespace' "$config_file")
  local metallb_system_deployment_name
  metallb_system_deployment_name=$(kubectl get deployment -n "$metallb_system_namespace" -l $metallb_system_labels -o=jsonpath="{.items[0].metadata.name}")
  local metallb_system_template_file="configs/metallb/L2-pool-config.j2"
  check_retrieved_value "metallb_system_namespace" "$metallb_system_namespace"
  check_retrieved_value "metallb_system_deployment_name" "$metallb_system_deployment_name"

  jinja -d "$config_file" "$metallb_system_template_file" >"$metallb_system_config_file"
  wait_for_resource_ready "deployment" "$metallb_system_namespace" "$metallb_system_deployment_name"
  apply_config_cmd "$metallb_system_config_file" "$metallb_system_namespace"
}

apply_config_rook_volume_classes() {
  log_info_block "Создаю Rook VolumeSnapshotClasses"
  local rook_operator_labels="app.kubernetes.io/part-of=rook-ceph-operator"
  local rook_operator_namespace
  rook_operator_namespace=$(yq '.charts[] | select(.name == "rook-ceph") | .namespace' "$config_file")
  local rook_operator_deployment_name
  rook_operator_deployment_name=$(kubectl get deployment -n "$rook_operator_namespace" -l $rook_operator_labels -o=jsonpath="{.items[0].metadata.name}")
  local rook_template_file="configs/rook/volume-snapshot-classes.j2"
  local rook_config_file="${tmp_dir}/volume-snapshot-class.yaml"
  check_retrieved_value "rook_operator_namespace" "$rook_operator_namespace"
  check_retrieved_value "rook_operator_deployment_name" "$rook_operator_deployment_name"

  echo "Создаю конфиг Rook из $rook_template_file"
  jinja -d "$config_file" "$rook_template_file" >"$rook_config_file"
  apply_config_cmd "$rook_config_file" "default"
}

apply_config_csi_driver_nfs() {
  log_info_block "Настаиваю CSI Driver NFS"
  local csi_nfs_template_snapshotclass_file='configs/csi-driver-nfs/snapshotclass.j2'
  local csi_nfs_template_storageclass_file='configs/csi-driver-nfs/storageclass.j2'
  local csi_nfs_namespace
  csi_nfs_namespace=$(yq '.charts[] | select(.name == "csi-driver-nfs") | .namespace' "$config_file")
  check_retrieved_value "csi_nfs_namespace" "$csi_nfs_namespace"

  if ! kubectl get secret mount-options -n "$csi_nfs_namespace" >/dev/null 2>&1; then
    kubectl create secret generic mount-options --from-literal mountOptions="nfsvers=3,hard" -n "$csi_nfs_namespace"
  else
    echo "Секрет mount-options уже существует. Пропускаем создание."
  fi
  for cfg_file in $csi_nfs_template_snapshotclass_file $csi_nfs_template_storageclass_file; do
    local output_file="${tmp_dir}/output_file.yaml"
    echo "Создаю файл конфигурации из шаблона ${cfg_file}"
    jinja -d "$config_file" "${cfg_file}" >"$output_file"
    apply_config_cmd "$output_file" "$csi_nfs_namespace"
  done
}

configure_grafana() {
  log_info_block "Настраиваю Grafana"
  local namespace
  namespace=$(yq '.charts[] | select(.name == "vmks") | .namespace' "$config_file")

  check_retrieved_value "namespace" "$namespace"

  local grafana_deployment_name
  grafana_deployment_name=$(kubectl get deployment -n "$namespace" -l app.kubernetes.io/name=grafana -o=jsonpath="{.items[0].metadata.name}")

  check_retrieved_value "grafana_deployment_name" "$grafana_deployment_name"

  wait_for_resource_ready "deployment" "$namespace" "$grafana_deployment_name"

  mapfile -t configmaps < <(find configs/grafana/dashboards -type f -name "*.yaml")

  if [[ ${#configmaps[@]} -eq 0 ]]; then
    log_warn "Не найдено ни одного дашборда Grafana"
    return
  fi

  for configmap in "${configmaps[@]}"; do
    echo "Обноаляю dashboard: $configmap"
    kubectl apply -f "$configmap" -n "$namespace" ||
      exit_on_error "Ошибка обновления dashboard: ${configmap}"
  done
}

main() {
  local log_file
  log_file="${PWD}/installer_$(TZ='Europe/Moscow' date +"%d-%m-%Y_%H-%M-%S_MSK").log"
  exec > >(tee "$log_file") 2>&1

  local order_value=0
  local upgrade_flag=false
  local create_secrets_flag=false
  local no_drain_flag=false
  local charts_to_install=()
  local certs_dir="certs"
  local config_file="charts-config.yaml"
  local config_template_file="charts-config.j2"
  local lcm_config_file="lcm-config.yaml"
  local charts_archive_dir="charts"
  local bundle_images_file="bundle_file.tar"
  local root_ca_cert_namespace="lcm-root-ca"

  process_arguments "$@"

  tmp_dir=$(mktemp -d)
  trap 'rm -fr "$tmp_dir"' EXIT

  if [[ ($order_value -lt 2 && ${#charts_to_install[@]} -eq 0) || $upgrade_flag == true ]]; then
    log_info_block "Устанавливаю инструментарий"
    local tools_name=("k0sctl" "kubectl" "helm" "yq" "velero")

    for tool in "${tools_name[@]}"; do
      install_tools "$tool"
    done
    create_main_config_file
  fi

  if [[ $order_value == "1" ]] || [[ $upgrade_flag == true ]]; then

    if [[ "$create_secrets_flag" == true ]]; then

      if [[ ! -d "$certs_dir" ]]; then
        mkdir -p "$certs_dir"
        create_certs_and_secrets
        create_client_certs_and_secrets "certs"
        install_ca_cert
      else
        log_info_block "Каталог $certs_dir уже существует. Пропускаю создание сертификатов"
      fi
    fi
    create_k0s_config "$config_file"

    if [[ $no_drain_flag == true ]]; then
      apply_k0s_config_no_drain
    else
      apply_k0s_config
    fi

    if [[ $upgrade_flag != true ]]; then
      fix_path_in_sberlinux
      install_k8s_config
    fi

    check_vip_ready
    wait_for_cp_nodes_ready
    create_namespaces

    if [[ "$create_secrets_flag" == true ]]; then
      create_certs_and_secrets "secrets"
      create_client_certs_and_secrets "secrets"
    fi

  elif [[ ${#charts_to_install[@]} -gt 0 ]]; then
    create_main_config_file
    install_charts_force "$config_file" "$charts_archive_dir"
    exit 0

  elif [[ $order_value == "2" ]]; then
    create_main_config_file
    create_postgresql_clusters
    create_gitlab_ad_ca_file_secret
  fi

  install_charts "$config_file" "$order_value"

  if [[ $order_value == "1" ]]; then
    add_volume_group_snapshot_APIs
    local vip
    vip=$(yq '.cp_vip' "$config_file")
    if [[ $vip == 'null' ]]; then
      apply_config_csi_driver_nfs
    else
      apply_config_rook_volume_classes
    fi
    apply_config_metallb_system
  fi

  if [[ $order_value == "2" ]]; then
    configure_grafana
    configure_vault "$config_file"
    configure_nexus "$config_file"
    create_cronjobs "$config_file"
  fi
}

main "$@"
