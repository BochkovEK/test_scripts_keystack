#!/usr/bin/env python3
"""
Simple script to run Ansible executor and display all output
"""

import sys
from pathlib import Path
# import os

# Add src to path for imports
src_path = Path(__file__).parent / 'src'
sys.path.append(str(src_path))

from config import get_config
from ansible_executor import get_ansible_runner


def main():
    """Main function to run the playbook and display output"""

    # Получаем конфигурацию (может потребоваться создать простой конфиг)
    config = get_config()  # Если нет config.py, создайте простой словарь

    # Получаем экземпляр Ansible исполнителя
    executor = get_ansible_runner(config)

    # Получаем список доступных плейбуков
    playbooks = executor.get_available_playbooks()
    print("Available playbooks:", playbooks)

    # Запускаем плейбук (предполагаем, что он называется 'podman_info.yml')
    playbook_name = "check_containers.yml"  # или другое имя вашего плейбука

    if playbook_name not in playbooks:
        print(f"Playbook {playbook_name} not found. Available playbooks: {playbooks}")
        return

    print(f"\n{'=' * 50}")
    print(f"Running playbook: {playbook_name}")
    print(f"{'=' * 50}\n")

    # Запускаем плейбук
    result = executor.run_playbook(playbook_name)

    # Выводим все результаты
    print("EXECUTION RESULTS:")
    print(f"Success: {result.get('success', False)}")
    print(f"Return code: {result.get('return_code', -1)}")
    print(f"Status: {result.get('status', 'unknown')}")

    if 'error' in result:
        print(f"Error: {result['error']}")

    print(f"\n{'=' * 30} STDOUT {'=' * 30}")
    stdout = result.get('stdout', '')
    if stdout:
        print(stdout)
    else:
        print("No stdout output")

    print(f"\n{'=' * 30} STDERR {'=' * 30}")
    stderr = result.get('stderr', '')
    if stderr:
        print(stderr)
    else:
        print("No stderr output")

    print(f"\n{'=' * 50}")
    if result.get('success', False):
        print("Playbook execution completed SUCCESSFULLY")
    else:
        print("Playbook execution FAILED")
    print(f"{'=' * 50}")


if __name__ == "__main__":
    main()

