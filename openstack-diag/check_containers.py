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

    def run_playbook(self, playbook_path: str) -> List[CheckResult]:
        """
        Run specific playbook and return results with output preview
        """
        self.logger.info(f"Running playbook: {playbook_path}")
        results = []

        try:
            ansible_result = self.runner.run_playbook(playbook_path)

            # Create output preview
            stdout = ansible_result['stdout'] or ""
            stderr = ansible_result['stderr'] or ""

            # Get first and last 50 lines
            stdout_lines = stdout.split('\n')
            output_preview = ""

            if stdout_lines:
                first_50 = '\n'.join(stdout_lines[:50])
                last_50 = '\n'.join(stdout_lines[-50:]) if len(stdout_lines) > 50 else ""

                output_preview = f"First 50 lines:\n{first_50}"
                if last_50:
                    output_preview += f"\n\nLast 50 lines:\n{last_50}"

            if not ansible_result['success']:
                results.append(CheckResult(
                    name=playbook_path,
                    status="error",
                    message=f"Playbook failed: {ansible_result.get('error', 'Unknown error')}",
                    details={
                        "return_code": ansible_result['return_code'],
                        "output_preview": output_preview,
                        "stderr": stderr
                    }
                ))
                return results

            # Success case
            results.append(CheckResult(
                name=playbook_path,
                status="success",
                message=f"Playbook completed successfully",
                details={
                    "return_code": ansible_result['return_code'],
                    "output_preview": output_preview,
                    "stderr": stderr
                }
            ))

        except Exception as e:
            results.append(CheckResult(
                name=playbook_path,
                status="error",
                message=f"Execution error: {str(e)}"
            ))

        return results

    def get_available_playbooks(self) -> Dict[str, Path]:
        """Get all available playbooks"""
        return self.runner.get_available_playbooks()


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Run Ansible playbooks for OpenStack diagnostics')
    parser.add_argument('--playbook', '-p', help='Full path to specific playbook to run')
    parser.add_argument('--list', '-l', action='store_true', help='List available playbooks')

    args = parser.parse_args()

    runner = PlaybookRunner()

    if args.list:
        playbooks = runner.get_available_playbooks()
        print("Available playbooks:")
        for name, path in playbooks.items():
            print(f"  - {name}")
            print(f"    path: {path}")
        return

    results = []

    if args.playbook:
        # Scenario 1: Run specific playbook by full path
        playbook_path = Path(args.playbook)
        if not playbook_path.exists():
            print(f"Error: Playbook not found: {playbook_path}")
            sys.exit(1)

        print(f"🚀 Running specific playbook: {playbook_path}")
        results = runner.run_playbook(str(playbook_path))

    else:
        # Scenario 2: Run all available playbooks
        playbooks = runner.get_available_playbooks()
        if not playbooks:
            print("No playbooks found")
            return

        print(f"🚀 Running all playbooks ({len(playbooks)} total)")

        for playbook_name, playbook_path in playbooks.items():
            print(f"\n📋 Running: {playbook_name}")
            playbook_results = runner.run_playbook(str(playbook_path))
            results.extend(playbook_results)

    # Print results summary
    print(f"\n📊 Final Results ({len(results)} checks):")
    success_count = sum(1 for r in results if r.status == 'success')
    error_count = sum(1 for r in results if r.status == 'error')

    print(f"  ✅ Success: {success_count}")
    print(f"  ❌ Errors: {error_count}")

    # Detailed results
    for result in results:
        status_icon = "✅" if result.status == 'success' else "❌"
        print(f"  {status_icon} {result.name}: {result.message}")

        if result.details and 'output_preview' in result.details:
            print(f"\n  Output preview:")
            print("  " + "=" * 50)
            print(result.details['output_preview'])
            print("  " + "=" * 50)


if __name__ == "__main__":
    main()