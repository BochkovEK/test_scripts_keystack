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

**Расположение:** `~/test_scripts_keystack/terraform/example/create_vms_with_tf_module/`

## Уствновка Terraform

1) Скачать бинарник Terraform:
```bash
curl -O https://repo.itkey.com/repository/bootstrap/terraform/terraform_1.8.5_linux_amd64
chmod 777 terraform_1.8.5_linux_amd64
```
2) Переместить бинарник Terraform в /bin
- [Вариант 1] /usr/local/
```bash
mv ./terraform_1.8.5_linux_amd64 /usr/local/terraform
```
- [Вариант 2] $VIRTUAL_ENV/bin/terraform # terraform доступен только для VENV
```bash
mv ./terraform_1.8.5_linux_amd64 $VIRTUAL_ENV/bin/terraform

#  for apply changes
deactivate
source ~/$venv_folder_name/bin/activate
```

## Создание файла переменных окружения для работы с Terraform модулем cloud.yml

1) Получить id тестового проекта
```bash
vi $VIRTUAL_ENV/openrcopenstack project list
export  test_projcet_id=<id>
```

2) Создать cloud.yml
```bash
cat <<-EOF > $VIRTUAL_ENV/clouds.yml
clouds:
  openstack:
    auth:
      auth_url: $OS_AUTH_URL # https://fc-lab1.lab.itkey.com:5000/v3
      username: "$OS_USERNAME"
      user_domain_name: "Default"
      password: $OS_PASSWORD
      project_id: $test_project_id
    region_name: "$OS_REGION_NAME"
    interface: "public"
    identity_api_version: 3
    cacert: "$OS_CACERT"
EOF
```

3) Задать переменную окружения указав путь до сloud.yml
```bash
export OS_CLIENT_CONFIG_FILE="$VIRTUAL_ENV/clouds.yml"
```

## Подготовка каталога модуля Terraform (create_vms_with_tf_module)

1) Скопировать исходный каталог 'create_vms_with_tf_module'
```bash
cp -r ~/test_scripts_keystack/terraform/examples/create_vms_with_tf_module/ $VIRTUAL_ENV
```
2) Отредактировать конфиг main.tf изменив путь к каталогу скриптов тестирования
```bash
vi $VIRTUAL_ENV/create_vms_with_module/main.tf
# set for all modules (source)
source = "/path/to/test_scripts_keystack/terraform/modules/instances"
```


## Конфигурация и создание ресурсов

### Конфигурация виртуальных машин (VMs)
Конфигурация создаваемых ВМ определяется в файле имеющим расширение ***.auto.tfvars**  
Файл *.auto.tfvars должен иметь формат **json** и находится в каталоге 'create_vms_with_tf_module'

### Описание параметров ВМ (*.auto.tfvars)
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
```
### Создание виртуальных машин (VMs)
1) Перейти в каталог 'create_vms_with_tf_module'
```bash
cd $VIRTUAL_ENV/create_vms_with_tf_module
```

2) Инициализировать Terraform
```bash
terraform init
```

3) Создать план выполнения Terraform
```bash
terraform plan -var-file "*.auto.tfvars" -out=plan.tfplan
```
**ПРИМЕЧАНИЕ:** Во избежании конфликтов описаний файл *.auto.tfvars в каталоге foo должен быть только один

4) Создание ресурсов
```bash
terraform apply "plan.tfplan"
<type> "yes"
```

### Удаление виртуальных машин (VMs)
```bash
terraform destroy
<type> "yes"
```




