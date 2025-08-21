# Description
# vi ~/test_scripts_keystack/inventory # Create inventory from output 'vms' stage
# cd ~/test_scripts_keystack/
# python ./installer_v2/lcm_config_parser.py

import configparser
import re
import argparse
import os
import shutil
# from datetime import datetime

# Константы по умолчанию
DEFAULT_INVENTORY = 'inventory'
SSH_USER = "kolla"
DEFAULT_CONFIG = f'/home/{SSH_USER}/installer/mutiple-node/lcm-config.yaml'
CORP_DOMAIN = "vm.lab.itkey.com"
ACTIVE_DIRECTORY_STRINGS = """
ldap_enable: "true" # "true" или "false"
ldap_host: "ldaps-lab.slavchenkov-keystack.vm.lab.itkey.com" # FQDN из SAN сертификата точки входа AD
ldap_ca_cert_file: "ldaps.pem" # Публичный сертификат центра сертификации в PEM-формате; файл должен находиться рядом с конфигом
ldap_bind_dn: "CN=ldap-ro,CN=Users,DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
ldap_user_search_basedn: "DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
ldap_group_search_basedn: "OU=Keystack,OU=Applications,DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
ldap_reader_group_dn: "CN=preevostack_reader,OU=Keystack,OU=Applications,DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
ldap_auditor_group_dn: "CN=preevostack_security_admin,OU=Keystack,OU=Applications,DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
ldap_operator_group_dn: "CN=preevostack_support_admin,OU=Keystack,OU=Applications,DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
ldap_admin_group_dn: "CN=preevostack_infra_admin,OU=Keystack,OU=Applications,DC=slavchenkov-keystack,DC=vm,DC=lab,DC=itkey,DC=com"
"""


def create_backup(config_path):
    """Создает бэкап файла конфигурации только если его нет"""
    if not os.path.exists(config_path):
        return None

    backup_path = f"{config_path}_backup"

    # Проверяем, существует ли уже бэкап
    if os.path.exists(backup_path):
        print(f"Бэкап уже существует: {backup_path}")
        return backup_path

    try:
        shutil.copy2(config_path, backup_path)
        print(f"Создан бэкап: {backup_path}")
        return backup_path
    except Exception as e:
        print(f"Ошибка при создании бэкапа: {e}")
        return None


def parse_arguments():
    """Парсит аргументы командной строки"""
    parser = argparse.ArgumentParser(description='Обработка inventory и конфигурационного файла')
    parser.add_argument('--inventory', '-i',
                        default=DEFAULT_INVENTORY,
                        help=f'Путь к inventory файлу (по умолчанию: {DEFAULT_INVENTORY})')
    parser.add_argument('--config', '-c',
                        default=DEFAULT_CONFIG,
                        help=f'Путь к конфигурационному файлу (по умолчанию: {DEFAULT_CONFIG})')
    parser.add_argument('--output', '-o',
                        help='Путь для выходного файла (по умолчанию: перезапись исходного конфига)')
    parser.add_argument('--no-backup', action='store_true',
                        help='Не создавать бэкап файла')

    return parser.parse_args()


def parse_inventory(inventory_file):
    """Парсит inventory файл и возвращает данные в структурированном виде"""
    if not os.path.exists(inventory_file):
        raise FileNotFoundError(f"Inventory файл не найден: {inventory_file}")

    config = configparser.ConfigParser(allow_no_value=True)
    config.read(inventory_file)

    inventory_data = {
        'vars': {},
        'groups': {}
    }

    # Парсим переменные из [all:vars]
    if 'all:vars' in config:
        inventory_data['vars'] = dict(config['all:vars'])

    # Парсим группы
    for section in config.sections():
        if section != 'all:vars':
            inventory_data['groups'][section] = []
            for host in config[section]:
                if host.strip() and not host.startswith('#'):
                    # Извлекаем имя хоста и ansible_host
                    host_parts = host.split()
                    host_name = host_parts[0]
                    ansible_host = config[section][host]

                    # Если ansible_host не указан явно, пытаемся извлечь из строки
                    if not ansible_host or ansible_host.strip() == '':
                        for part in host_parts:
                            if part.startswith('ansible_host='):
                                ansible_host = part.split('=')[1]
                                break

                    host_data = {
                        'name': host_name,
                        'ansible_host': ansible_host.strip() if ansible_host else ''
                    }
                    inventory_data['groups'][section].append(host_data)

    return inventory_data


def replace_config_values(config_content, inventory_data):
    """Заменяет значения в конфиге согласно правилам"""

    # 1) Замена ssh_username
    config_content = re.sub(
        r'ssh_username:\s*".*?"',
        f'ssh_username: "{SSH_USER}"',
        config_content
    )

    # 2) Замена fqdn_cp на имена узлов из группы [k0s] с добавлением домена
    k0s_nodes = inventory_data['groups'].get('k0s', [])
    for i, node in enumerate(k0s_nodes, 1):
        config_content = re.sub(
            rf'fqdn_cp{i}:\s*".*?"',
            f'fqdn_cp{i}: "{node["name"]}.{CORP_DOMAIN}"',
            config_content
        )

    # 3) Замена cp_vip на k0s_vip с добавлением /27
    k0s_vip = inventory_data['vars'].get('k0s_vip', '')
    if k0s_vip:
        # Убираем кавычки если они есть
        k0s_vip = k0s_vip.strip('"\'')
        config_content = re.sub(
            r'cp_vip:\s*".*?"',
            f'cp_vip: "{k0s_vip}/27"',
            config_content
        )

    # 4) Замена loadbalancer_ip_pool
    service_vip = inventory_data['vars'].get('service_vip', '')
    if service_vip:
        service_vip = service_vip.strip('"\'')
        config_content = re.sub(
            r'loadbalancer_ip_pool:\s*".*?"',
            f'loadbalancer_ip_pool: "{service_vip}-{service_vip}"',
            config_content
        )

    # 5) Замена domain_name (берем первое имя из группы [k0s] и обрабатываем)
    if k0s_nodes:
        first_node_name = k0s_nodes[0]['name']
        # Ищем часть до "-lcm" или используем все имя
        if '-lcm' in first_node_name:
            domain_base = first_node_name.split('-lcm')[0]
        else:
            domain_base = first_node_name

        config_content = re.sub(
            r'domain_name:\s*".*?"',
            f'domain_name: "{domain_base}.{CORP_DOMAIN}"',
            config_content
        )

    # 6) Замена блока Active Directory
    ad_block_pattern = r'# Настройки подключения к Active Directory.*?(?=^#|\Z)'
    config_content = re.sub(
        ad_block_pattern,
        f'# Настройки подключения к Active Directory\n{ACTIVE_DIRECTORY_STRINGS}\n\n',
        config_content,
        flags=re.DOTALL | re.MULTILINE
    )

    return config_content


def main():
    # Парсим аргументы командной строки
    args = parse_arguments()

    try:
        # Проверяем существование файлов
        if not os.path.exists(args.inventory):
            raise FileNotFoundError(f"Inventory файл не найден: {args.inventory}")
        if not os.path.exists(args.config):
            raise FileNotFoundError(f"Конфигурационный файл не найден: {args.config}")

        # Определяем путь для выходного файла
        output_file = args.output if args.output else args.config

        # Создаем бэкап если не указан --no-backup и если мы перезаписываем исходный файл
        if not args.no_backup and output_file == args.config:
            backup_path = create_backup(args.config)
            if not backup_path:
                print("Предупреждение: не удалось создать бэкап, продолжение без бэкапа")

        # Парсим inventory
        print(f"Чтение inventory: {args.inventory}")
        inventory_data = parse_inventory(args.inventory)

        # Читаем исходный конфиг
        print(f"Чтение конфига: {args.config}")
        with open(args.config, 'r', encoding='utf-8') as f:
            config_content = f.read()

        # Заменяем значения
        updated_config = replace_config_values(config_content, inventory_data)

        # Сохраняем результат
        print(f"Сохранение результата в: {output_file}")
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(updated_config)

        print("Конфиг успешно обновлен!")

        # Показываем изменения
        print("\nОсновные изменения:")
        print(f"  ssh_username: -> {SSH_USER}")
        if 'k0s' in inventory_data['groups']:
            for i, node in enumerate(inventory_data['groups']['k0s'], 1):
                print(f"  fqdn_cp{i}: -> {node['name']}")
        if 'k0s_vip' in inventory_data['vars']:
            k0s_vip = inventory_data['vars']['k0s_vip'].strip('"\'')
            print(f"  cp_vip: -> {k0s_vip}/27")

    except FileNotFoundError as e:
        print(f"Ошибка: {e}")
    except Exception as e:
        print(f"Ошибка при обработке файлов: {e}")


if __name__ == "__main__":
    main()