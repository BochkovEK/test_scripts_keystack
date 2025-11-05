"""
Simple Ansible Playbook Runner for OpenStack Diagnostics
Run specific playbooks and display results
"""

import sys
import argparse
from pathlib import Path
from typing import List, Dict, Any
from dataclasses import dataclass

# Fix imports for direct script execution
src_path = Path(__file__).parent / 'src'
sys.path.insert(0, str(src_path))

from config import get_config
from logger import get_logger
from ansible import get_ansible_runner


@dataclass
class CheckResult:
    """Result of a single check"""
    name: str
    status: str  # 'success', 'warning', 'error'
    message: str
    details: Dict[str, Any] = None


class PlaybookRunner:
    """
    Simple playbook runner for OpenStack diagnostics
    """

    def __init__(self):
        self.config = get_config()
        self.runner = get_ansible_runner(self.config)
        self.logger = get_logger(__name__)

    def run_playbook(self, playbook_name: str) -> List[CheckResult]:
        """
        Run specific playbook and return results

        Args:
            playbook_name: Name of playbook to run

        Returns:
            List of CheckResult objects
        """
        self.logger.info(f"Running playbook: {playbook_name}")
        results = []

        try:
            ansible_result = self.runner.run_playbook(playbook_name)

            if not ansible_result['success']:
                results.append(CheckResult(
                    name=playbook_name,
                    status="error",
                    message=f"Playbook failed: {ansible_result['error']}",
                    details=ansible_result
                ))
                return results

            # Parse output based on playbook type
            if playbook_name == "check_containers.yml":
                container_results = self._parse_containers_output(ansible_result['stdout'])
                results.extend(container_results)
            else:
                # Generic success for other playbooks
                results.append(CheckResult(
                    name=playbook_name,
                    status="success",
                    message=f"Playbook completed successfully",
                    details={"output": ansible_result['stdout']}
                ))

        except Exception as e:
            results.append(CheckResult(
                name=playbook_name,
                status="error",
                message=f"Execution error: {str(e)}"
            ))

        return results

    def _parse_containers_output(self, ansible_output: str) -> List[CheckResult]:
        """
        Simple container output parser - just extract basic info
        """
        results = []

        # Simple extraction - look for container lines
        lines = ansible_output.split('\n')
        for line in lines:
            if 'CONTAINER ID' in line:
                continue  # Skip header
            if line.strip() and len(line.split()) >= 6:
                parts = line.split()
                name = parts[-1]  # Last column is name
                status = ' '.join(parts[-4:-2])  # Status columns

                results.append(CheckResult(
                    name=f"container_{name}",
                    status="info",
                    message=f"{name}: {status}",
                    details={"name": name, "status": status}
                ))

        return results

    def get_available_playbooks(self) -> List[str]:
        """Get list of available playbooks"""
        return self.runner.get_available_playbooks()


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Run Ansible playbooks for OpenStack diagnostics')
    parser.add_argument('playbook', help='Name of playbook to run')
    parser.add_argument('--list', '-l', action='store_true', help='List available playbooks')

    args = parser.parse_args()

    runner = PlaybookRunner()

    if args.list:
        playbooks = runner.get_available_playbooks()
        print("Available playbooks:")
        for pb in playbooks:
            print(f"  - {pb}")
        return

    if args.playbook not in runner.get_available_playbooks():
        print(f"Error: Playbook '{args.playbook}' not found")
        print("Use --list to see available playbooks")
        sys.exit(1)

    print(f"🚀 Running playbook: {args.playbook}")
    results = runner.run_playbook(args.playbook)

    print(f"\n📊 Results ({len(results)}):")
    for result in results:
        print(f"  {result.status.upper():8} {result.name}: {result.message}")


if __name__ == "__main__":
    main()