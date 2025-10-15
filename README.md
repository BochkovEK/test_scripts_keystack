# TSK (test scripts KeyStack)

## Назначение и возможности

Вспомогательные скрипты ручного тестирования KeyStack - TSK (test scripts KeyStack) служат для упрощения проведения ручного тестирования компонентов KeyStack, выполняя следующие действия:

- **Развертывание виртуальных машин** в разных конфигурациях
- **Проверка состояния контейнеров** сервисов KeyStack на узлах стенда
- **Циклическое выполнение команд** на узлах стенда
- **Сбор и вывод логов** тестируемых модулей (VMHA, DRS)
- **Создание нагрузки** на виртуальных ресурсах облака
- **Редактирование и применение конфигов** тестируемых модулей

Библиотека включает два основных компонента:

- **Shell-скрипты** - объединяют типовые операции тестирования в логику с возможностью параметризации запуска
- **Модуль Terraform** - упрощает создание виртуальных машин для подготовки исходных состояний тест кейсов

# Shell скрипты

## Управление виртуальными машинами
- **Создание ВМ**
  - `create_vms.sh` - создание виртуальных машин
  - `clean_created_vms.sh` - очистка созданных ВМ

## Автоматизация выполнения команд
- `inventory_to_hosts.sh` - преобразование inventory в hosts файл
- `check_container_state_on_nodes.sh` - проверка состояния контейнеров на узлах
- `command_on_nodes.sh` - выполнение команд на узлах стенда
- `command_on_vms.sh` - выполнение команд на ВМ облака

---

## Тестирование VMHA (High Availability)
- `edit_ha_config.sh` - редактирование конфигурации HA
- `check_nova_consult.sh` - проверка nova consult
- `check_consult_log.sh` - проверка логов consult
- `exclude_node_by_net.sh` - исключение узла по сети
- `baremetal_power_management.sh` - управление питанием baremetal серверов

## Тестирование DRS (Distributed Resource Scheduler)
- `edit_drs_config.sh` - редактирование конфигурации DRS
- `check_drs_log.sh` - проверка логов DRS
- `start_stress.sh` - запуск стресс-теста на ВМ
- `remove_drs_job_config_list.sh` - удаление конфигурации заданий DRS

---

# Модуль Terraform

**Расположение:** `./terraform/example/create_vms_with_tf_module/`

## Основные параметры конфигурации

### Конфигурация виртуальных машин (VMs)
```hcl
VMs = {
    <vm_name> = {
        vm_qty                              = <vms_quantity>
        image_name                          = "<image_name>"           # по умолчанию "cirros-0.6.2-x86_64-disk.img"
        config_drive                        = true                     # использование config_drive
        flavor_name                         = "<existing_flavor_name>" # существующий flavor
        
        # Создание нового flavor
        flavor = {
            vcpus       = <vCPUs>
            ram         = <RAM>              # в мегабайтах (пример: 4096 для 4GB)
            extra_specs = "<string>"
        }
        # Если flavor не указан: 2 vCPUs, 2 GB RAM
        
        keypair_name        = "<existing_keypair_name>" # или создание "terraform_keypair" из ~/test_scripts_keystack/key_test.pub
        security_groups     = []                        # список групп или создание с SSH и ICMP правилами
        server_group_uuid   = "<existing_server_group_UUID>" # UUID (не имя)
        
        # Создание server group
        server_group = {
            name   = "<server_group_name>"
            policy = "<policy>" # варианты: ['anti-affinity', 'affinity', 'soft-anti-affinity', 'soft-affinity']
        }
        
        az_hint                             = "<az_name>:<hyper_name>"
        network_name                        = "<network_name>"        # по умолчанию "pub_net"
        boot_volume_size                    = <size>                  # в GB, по умолчанию 5 GB
        boot_volume_delete_on_termination   = "true\false"           # по умолчанию "true"
        
        # Дополнительные диски
        disks = [
          {
            boot_index = <boot_index>
            size = <size>
          },
        ]
        
        metadata = {}
        
        # Cloud-init конфигурация
        user_data = <<-EOT
                    #cloud-config
                    chpasswd:
                        list: |
                            ubuntu:1111
                        expire: False
                    ssh_pwauth: True
                    EOT
        
        # Или использование шаблона:
        # { template_file = "templates/cloud-init-2.yaml" }
    }
}

AZs = {
    <aggr_name> = {
        az_name    = "az_name"        # пример: "az_1"
        hosts_list = [ "<list_hosts>" ]
    }
}

