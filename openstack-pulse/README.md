# OpenStack Pulse

Легковесный инструмент непрерывной (heartbeat) диагоностики ключевых сервисов OpenStack

## Диагностируемые сервисы
- **Nova**: nova compute, гипервизоры, виртуальные машины (Openstack SDK)
- **Cinder**: volume service (Openstack SDK)
- **Neutron**: neutron agents, connectivity (Openstack SDK)
- **Keystone**: валидация токенов, сервисный каталог (Openstack SDK)
- **RabbitMQ**: кластер, ноды, очереди, ресурсы (RabbitMQ API)
- **MariaDB**: кластер, репликация, синхронизация (SQL requests)

## Конфигурация

Конфигурация OpenStack Pulse осуществлятся в четыре этапа:
1. Установка зависимостей:
```bash
    pip install -r ~/test_scripts_keystack/openstack-pulse/requirements.txt
```
2. Подготовка переменных окружения:
    - openrc - переменные авторизации в регионе
        - export OS_AUTH_URL=https://<external_fqdn>:5000 # public endpoint
        - export OS_CACERT="<path_to>/ca-bundle.crt"
    - Переменные авторизации в RabbitMQ API
        - RABBIT_USER - пользователь
        - RABBIT_PASS - пароль
    - Переменные авторизации MySQL/MariaDB (Galera)
        - MYSQL_USER - пользователь
        - MYSQL_PASS - пароль
2. Подготовка файла **inventory**:
   <details><summary>📋 Пример inventory</summary>
     
     ```ini
     # inventory
     # description of the main node groups is enough
     # like output from vms stage
          
     [all:vars]
     ansible_become=true
     ansible_ssh_common_args="-o StrictHostKeyChecking=no"
     ansible_port="22"
     ansible_user="sberlinux"
     openrc_public=true
     kolla_internal_address=10.224.151.195
     external_floating=10.224.151.196
     [add_vm]
     qa-stable-sberlinux-add_vm-01 ansible_host=10.224.151.210
     [compute]
     qa-stable-sberlinux-comp-01 ansible_host=10.224.151.207
     qa-stable-sberlinux-comp-02 ansible_host=10.224.151.220
     [control]
     qa-stable-sberlinux-ctrl-01 ansible_host=10.224.151.206
     qa-stable-sberlinux-ctrl-02 ansible_host=10.224.151.209
     qa-stable-sberlinux-ctrl-03 ansible_host=10.224.151.201
     [storage]
     qa-stable-sberlinux-ctrl-01 ansible_host=10.224.151.206
     qa-stable-sberlinux-ctrl-02 ansible_host=10.224.151.209
     qa-stable-sberlinux-ctrl-03 ansible_host=10.224.151.201
     [ci]
     qa-stable-sberlinux-lcm-01 ansible_host=10.224.151.215
     [jump]
     qa-stable-sberlinux-lcm-01 ansible_host=10.224.151.215
     ```
</details>

3. Подготовка файла конфигурации **config.yml**
   <details><summary>⚙️Пример config.yml</summary>
        
   ```yaml
   # config/config.yml
   # Services list for diagnostics
   
   # logging
   log:
    enable_log: True                   
   #  path: "/var/log/openstack-pulse"  # /tmp by default
   
   # Check services
   check_services:
    - nova
    - cinder
    - neutron
    - keystone
    - rabbitmq
    - galera
   
   # Endpoints
   endpoints:
    rabbitmq_port: 15672
    mariadb_port: 3306
   
   # Single check services
   single_mode_checks:
    - placement
   
   # Timing parameters
   intervals:
    check_interval: 5   # Interval between checks (seconds)
    duration: 300       # Data collection window (seconds) - 5 minutes
   
   # Pulse settings
   heartbeat_requests_services: 4
   ```

## Запуск

### Ключи запуска
В Openstack pulse предусмотрены следующие ключи запуска:
```bash
--inventory, -i - путь к inventory
--config, -c - путь к config.yml
--output, -o - путь к файлу логов
--debug, -d - включение вывода данных отладки
--single - однократный вывод состояний диагностируемых сервисов (по умолчанию режим непрерывной диагностики в течении заданного времени)
--duration - длительность работы в секундах (только для непрерывного режима)
```

### Примеры запуска
```bash
# Указание inventory, config.yml файла 
python ~/test_scripts_keystack/openstack-pulse/pulse.py -i /path/to/inventory --config /path/to/config.yml 

# Запись логов в указанный файл/директорию с указанием времени непрерывной диагностики (сек)
python ~/test_scripts_keystack/openstack-pulse/pulse.py --output /path/to/logs --duration 600

# Однократный запуск (без непрерывного мониторинга)
python ~/test_scripts_keystack/openstack-pulse/pulse.py --single
```