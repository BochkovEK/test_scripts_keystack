import sys
import os
import re
import socket
import dns.resolver

# the script work by inventory_to_hosts.sh

node_pattern = "-lcm-|-comp-|-cmpt-|-ctrl-|-net-|-add_vm-"
lcm_pattern = "lcm-01"
kolla_internal_address = "kolla_internal_address"
external_floating = "external_floating"
ansible_host = "ansible_host"
path_to_inventory = sys.argv[1]
internal_prefix = os.environ['INT_PREF']
external_prefix = os.environ['EXT_PREF']
output_file = os.environ['OUTPUT_FILE_PATH']
region = os.environ['REGION']
domain = os.environ['DOMAIN']
gitlab_short_name = os.environ['GITLAB_SHORT_NAME']
hosts_string = []

# Словарь для хранения хостов по группам
hosts_by_group = {
    'control': [],
    'network': [],
    'compute': [],
    'other': []
}

# Словарь для соответствия групп и префиксов
group_prefixes = {
    'control': 'ctrl',
    'network': 'net',
    'compute': 'comp'
}


def resolve_dns(hostname):
    """Резолвинг DNS для получения IP адреса"""
    try:
        # Пробуем стандартное разрешение через socket
        ip = socket.gethostbyname(hostname)
        print(f"DNS resolved {hostname} -> {ip}")
        return ip
    except socket.gaierror:
        try:
            # Пробуем через DNS resolver для более надежного разрешения
            resolver = dns.resolver.Resolver()
            answers = resolver.resolve(hostname, 'A')
            if answers:
                return str(answers[0])
        except:
            pass

    print(f"Warning: Could not resolve DNS for {hostname}")
    return None


def parse_inventory(path):
    current_group = None

    with open(path, "r") as inventory:
        for line in inventory:
            line = line.strip()

            # Пропускаем пустые строки и комментарии
            if not line or line.startswith('#'):
                continue

            # Определяем текущую группу
            if line.startswith('[') and line.endswith(']'):
                group_name = line[1:-1].split(':')[0]  # Убираем [ ] и возможные :vars
                if group_name in hosts_by_group:
                    current_group = group_name
                else:
                    current_group = 'other'
                continue

            # Если это строка с хостом и мы в известной группе
            if current_group and current_group in hosts_by_group and line:
                # Извлекаем имя хоста (первое слово в строке)
                hostname = line.split()[0].strip()
                if hostname and hostname not in hosts_by_group[current_group]:
                    hosts_by_group[current_group].append(hostname)


def get_ip_for_host(hostname, inventory_path):
    """Функция для получения IP адреса из inventory файла или через DNS"""
    ip_from_inventory = None

    try:
        with open(inventory_path, "r") as inventory:
            for line in inventory:
                line = line.strip()
                if hostname in line and ansible_host in line:
                    # Ищем строку с ansible_host и нашим хостом
                    parts = line.split()
                    for part in parts:
                        if part.startswith(ansible_host + '='):
                            ip_from_inventory = part.split('=')[1]
                            print(f"Found IP in inventory: {hostname} -> {ip_from_inventory}")
                            return ip_from_inventory
    except Exception as e:
        print(f"Error reading inventory: {e}")

    # Если в inventory нет IP, пробуем DNS резолвинг
    if not ip_from_inventory:
        ip_from_dns = resolve_dns(hostname)
        if ip_from_dns:
            return ip_from_dns

    return None


def generate_host_entries():
    """Генерация записей для файла hosts"""
    entries = []
    unresolved_hosts = []

    for group, hosts in hosts_by_group.items():
        if group == 'other':
            continue

        prefix = group_prefixes.get(group, group)

        for hostname in hosts:
            ip = get_ip_for_host(hostname, path_to_inventory)
            if ip:
                # Извлекаем номер из имени хоста (предполагаем формат name-XX.domain.com)
                host_number_match = re.search(r'name-(\d+)', hostname)
                if host_number_match:
                    host_number = host_number_match.group(1)
                    short_name = f"{prefix}-{host_number}"
                    entry = f"{ip} {hostname} {short_name}"
                    entries.append(entry)
                else:
                    # Альтернативный вариант если формат имени другой
                    short_name = f"{prefix}-{hostname.split('.')[0]}"
                    entry = f"{ip} {hostname} {short_name}"
                    entries.append(entry)
            else:
                unresolved_hosts.append(hostname)

    if unresolved_hosts:
        print(f"Warning: Could not resolve IP for hosts: {unresolved_hosts}")

    return entries


def write_file(path_to_file, strings):
    with open(path_to_file, "w") as file:
        # Группируем записи по типам для лучшей читаемости
        control_entries = [s for s in strings if 'ctrl-' in s]
        network_entries = [s for s in strings if 'net-' in s]
        compute_entries = [s for s in strings if 'comp-' in s]
        other_entries = [s for s in strings if not any(x in s for x in ['ctrl-', 'net-', 'comp-'])]

        # Записываем с разделением по группам
        if control_entries:
            file.write("# Control nodes\n")
            for entry in control_entries:
                file.write(entry + "\n")
            file.write("\n")

        if network_entries:
            file.write("# Network nodes\n")
            for entry in network_entries:
                file.write(entry + "\n")
            file.write("\n")

        if compute_entries:
            file.write("# Compute nodes\n")
            for entry in compute_entries:
                file.write(entry + "\n")
            file.write("\n")

        if other_entries:
            file.write("# Other nodes\n")
            for entry in other_entries:
                file.write(entry + "\n")
            file.write("\n")


# Основная логика
if __name__ == "__main__":
    try:
        parse_inventory(path_to_inventory)
        print(f"Parsed groups: {[k for k, v in hosts_by_group.items() if v]}")

        host_entries = generate_host_entries()
        write_file(output_file, host_entries)

        print(f"Generated {len(host_entries)} host entries")
        print(f"Data written to {output_file}")

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)