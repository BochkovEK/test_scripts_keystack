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


# def extract_task_output(stdout: str) -> str:
#     """
#     Extract only the useful task output from Ansible stdout
#     Removes PLAY, TASK headers and keeps only [host] => {data} patterns
#     """
#     lines = stdout.split('\n')
#     useful_lines = []
#
#     for line in lines:
#         line = line.strip()
#         # Keep only lines with actual task results
#         if '=>' in line and ('ok:' in line or 'changed:' in line):
#             useful_lines.append(line)
#         # Keep debug output with variable values
#         elif line.startswith('"') and ':' in line and line.endswith(','):
#             useful_lines.append(line)
#         # Keep JSON-like structures
#         elif line.startswith('{') or line.startswith('[') or line.endswith('}') or line.endswith(']'):
#             useful_lines.append(line)
#
#     return '\n'.join(useful_lines) if useful_lines else "No structured output found"


def extract_task_output(stdout: str) -> str:
    """
    Extract only the content inside { } from lines like [host] => { ... }
    """
    import re

    lines = stdout.split('\n')
    extracted_data = []

    # Pattern to match [host] => { ... }
    pattern = r'\[.*\]\s+=>\s+\{.*\}'

    for line in lines:
        line = line.strip()
        # Find lines with [host] => { ... } pattern
        match = re.search(pattern, line)
        if match:
            json_like_content = match.group(1)
            extracted_data.append(json_like_content)

    return '\n'.join(extracted_data) if extracted_data else "No structured data found"

def output_playbook_result(playbook_name: str, results: List[CheckResult]):
    """Print results for a single playbook immediately after execution"""
    print(f"\n📊 Results for {playbook_name}:")
    for result in results:
        status_icon = "✅" if result.status == 'success' else "❌"
        print(f"  {status_icon} {result.name}: {result.message}")

        if result.details and 'output_preview' in result.details:
            # Extract clean output from the full preview
            clean_output = extract_task_output(result.details['output_preview'])
            print(f"\n  Clean output:")
            print("  " + "=" * 50)
            print(clean_output)
            print("  " + "=" * 50)


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Run Ansible playbooks for OpenStack diagnostics')
    parser.add_argument('--playbook', '-p', help='Full path to specific playbook to run')

    args = parser.parse_args()
    runner = PlaybookRunner()
    results = []

    if args.playbook:
        # Scenario 1: Run specific playbook by full path
        playbook_path = Path(args.playbook)
        if not playbook_path.exists():
            print(f"Error: Playbook not found: {playbook_path}")
            sys.exit(1)

        print(f"🚀 Running specific playbook: {playbook_path}")
        results = runner.run_playbook(str(playbook_path))
        output_playbook_result(playbook_path.name, results)

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
            output_playbook_result(playbook_name, playbook_results)
            results.extend(playbook_results)

    # Print results summary
    print(f"\n📊 Final Results ({len(results)} checks):")
    success_count = sum(1 for r in results if r.status == 'success')
    error_count = sum(1 for r in results if r.status == 'error')

    print(f"\n🎯 Final Summary:")
    print(f"  Total playbooks run: {len(results) if not args.playbook else 1}")
    print(f"  ✅ Successful: {success_count}")
    print(f"  ❌ Failed: {error_count}")


if __name__ == "__main__":
    main()

