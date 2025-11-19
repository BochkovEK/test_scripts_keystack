import sys
import openstack
from openstack import connection


# Настройка отображения
def print_header(title):
    print(f"\n{'=' * 60}")
    print(f" {title}")
    print(f"{'=' * 60}")


def get_nova_server_info(conn, consumer_uuid):
    """
    Пытаемся найти сервер в Nova по UUID потребителя.
    """
    try:
        # ignore_missing=True вернет None, если сервер не найден
        server = conn.compute.find_server(consumer_uuid, ignore_missing=True)
        if server:
            return {
                "found": True,
                "name": server.name,
                "status": server.status,
                "host": server.compute_host
            }
    except Exception as e:
        return {"found": False, "error": str(e)}

    return {"found": False, "reason": "Not found in Nova"}


def audit_provider(conn, provider_uuid):
    print_header(f"AUDIT REPORT FOR: {provider_uuid}")

    # 1. Получаем Inventory (Инвентарь)
    try:
        # Прямой запрос к Placement API, так как SDK для Placement иногда ограничен
        resp = conn.placement.get(f'/resource_providers/{provider_uuid}/inventories')
        inventories = resp.json().get('inventories', {})

        print("\n[1] INVENTORY (Физические ресурсы):")
        print(f"{'CLASS':<15} | {'TOTAL':<10} | {'RESERVED':<10} | {'ALLOCATION RATIO':<15}")
        print("-" * 60)
        for rc, data in inventories.items():
            print(f"{rc:<15} | {data['total']:<10} | {data['reserved']:<10} | {data['allocation_ratio']:<15}")

    except Exception as e:
        print(f"Ошибка при получении Inventory: {e}")
        return

    # 2. Получаем Allocations (Кто что занял)
    try:
        resp = conn.placement.get(f'/resource_providers/{provider_uuid}/allocations')
        allocations = resp.json().get('allocations', {})

        print("\n[2] ALLOCATIONS (Потребители ресурсов):")

        if not allocations:
            print(">> Аллокаций нет. Гипервизор чист.")
            return

        for consumer_uuid, data in allocations.items():
            resources = data.get('resources', {})
            print(f"\n---> Consumer UUID: {consumer_uuid}")

            # Вывод занятых ресурсов
            res_str = ", ".join([f"{k}={v}" for k, v in resources.items()])
            print(f"     Resources Held: {res_str}")

            # 3. Кросс-проверка с Nova
            nova_info = get_nova_server_info(conn, consumer_uuid)

            if nova_info['found']:
                print(f"     STATUS: [OK] Valid Nova Instance")
                print(f"     Name:   {nova_info['name']}")
                print(f"     State:  {nova_info['status']}")
                print(f"     Host:   {nova_info['host']}")
            else:
                # Это и есть ваша проблема
                print(f"     STATUS: [!!! WARNING !!!] ORPHANED / PHANTOM")
                print(f"     Details: Consumer exists in Placement but NOT in Nova.")
                print(f"     Action:  This allocation is likely leaked.")

    except Exception as e:
        print(f"Ошибка при получении Allocations: {e}")


def main():
    # Получаем UUID из аргументов или просим ввести
    if len(sys.argv) > 1:
        target_uuid = sys.argv[1]
    else:
        target_uuid = input("Введите UUID Resource Provider (Hypervisor): ").strip()

    if not target_uuid:
        print("UUID не указан.")
        sys.exit(1)

    # Подключение к OpenStack (ищет clouds.yaml или переменные окружения)
    try:
        conn = openstack.connect()
    except Exception as e:
        print(f"Ошибка подключения к OpenStack: {e}")
        sys.exit(1)

    audit_provider(conn, target_uuid)


if __name__ == "__main__":
    main()