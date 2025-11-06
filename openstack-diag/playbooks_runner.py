"""
Simple Ansible Playbook Runner for OpenStack Diagnostics
Run playbooks and extract registered variables
"""

import sys
import argparse
from pathlib import Path
from typing import List, Dict, Any
import json

# Fix imports for direct script execution
src_path = Path(__file__).parent / 'src'
sys.path.insert(0, str(src_path))

from config import get_config
from logger import get_logger
from ansible import get_ansible_runner


class PlaybookRunner:
    """
    Simple playbook runner that extracts registered variables
    """

    def __init__(self):
        self.config = get_config()
        self.runner = get_ansible_runner(self.config)
        self.logger = get_logger(__name__)

    def run_playbook(self, playbook_path: str) -> Dict[str, Any]:
        """
        Run playbook and extract registered variables from output
        Returns raw registered data for parsing
        """
        self.logger.info(f"Running playbook: {playbook_path}")

        try:
            ansible_result = self.runner.run_playbook(playbook_path)

            if not ansible_result['success']:
                return {
                    'success': False,
                    'error': ansible_result.get('error', 'Unknown error'),
                    'return_code': ansible_result['return_code']
                }

            # Extract registered variables from stdout
            registered_data = self._extract_registered_vars(ansible_result['stdout'])

            return {
                'success': True,
                'registered_vars': registered_data,
                'return_code': ansible_result['return_code'],
                'raw_stdout': ansible_result['stdout']
            }

        except Exception as e:
            return {
                'success': False,
                'error': str(e)
            }

    def _extract_registered_vars(self, stdout: str) -> Dict[str, Any]:
        """
        Extract registered variables from Ansible output
        Looks for patterns like "containers_json": {...}
        """
        try:
            # Look for JSON patterns in the output
            lines = stdout.split('\n')
            for line in lines:
                line = line.strip()
                # Look for registered variable patterns
                if '"containers_json":' in line and '{' in line and '}' in line:
                    # Extract the JSON part
                    start = line.find('{')
                    end = line.rfind('}') + 1
                    if start != -1 and end != -1:
                        json_str = line[start:end]
                        return json.loads(json_str)
        except Exception as e:
            self.logger.error(f"Error extracting registered vars: {e}")

        return {}

    def get_available_playbooks(self) -> Dict[str, Path]:
        """Get all available playbooks"""
        return self.runner.get_available_playbooks()


def main():
    """Main function"""
    parser = argparse.ArgumentParser(description='Run Ansible playbook and show output')
    parser.add_argument('playbook', help='Playbook path to run')

    args = parser.parse_args()

    # from ansible import get_ansible_runner
    runner = get_ansible_runner()

    playbook_path = Path(args.playbook)
    result = runner.run_playbook(playbook_path)

    print(f"Success: {result['success']}")
    print(f"Return code: {result['return_code']}")
    print(f"Stdout:\n{result['stdout']}")
    if result['stderr']:
        print(f"Stderr:\n{result['stderr']}")


if __name__ == "__main__":
    main()