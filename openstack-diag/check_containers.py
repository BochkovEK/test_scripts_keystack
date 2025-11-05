"""
Container Analysis Script
Runs specific playbook and analyzes container status
"""

import sys
import json
import re
from pathlib import Path
from typing import List, Dict, Any
from dataclasses import dataclass

# Fix imports
src_path = Path(__file__).parent / 'src'
sys.path.insert(0, str(src_path))

from config import get_config
from logger import get_logger
from ansible import get_ansible_runner


@dataclass
class ContainerStatus:
    """Container status analysis result"""
    node: str
    container_name: str
    state: str
    status: str
    health: str
    uptime_seconds: int
    check_status: str  # 'success', 'warning', 'error'
    message: str


class ContainerAnalyzer:
    """
    Analyzes container status from Ansible playbook output
    """

    def __init__(self):
        self.config = get_config()
        self.runner = get_ansible_runner(self.config)
        self.logger = get_logger(__name__)
        self.playbook_path = Path('./ansible/playbooks/check_containers.yml')  # Hardcoded path

    def run_analysis(self) -> List[ContainerStatus]:
        """Run playbook and analyze container status"""
        if not self.playbook_path.exists():
            raise FileNotFoundError(f"Playbook not found: {self.playbook_path}")

        self.logger.info(f"Running container analysis playbook: {self.playbook_path}")

        results = []
        ansible_result = self.runner.run_playbook(str(self.playbook_path))

        if not ansible_result['success']:
            self.logger.error(f"Playbook failed: {ansible_result.get('error')}")
            return results

        # Parse and analyze output
        return self._parse_ansible_output(ansible_result['stdout'])

    def _parse_ansible_output(self, output: str) -> List[ContainerStatus]:
        """Parse Ansible output and extract container information"""
        results = []

        # Extract JSON data from Ansible output
        json_pattern = r'"containers_json\.stdout":\s*(\[.*?\])'
        matches = re.findall(json_pattern, output, re.DOTALL)

        for match in matches:
            try:
                containers_data = json.loads(match)
                # TODO: Extract node name and analyze each container
                for container in containers_data:
                    status = self._analyze_container(container)
                    if status:
                        results.append(status)
            except json.JSONDecodeError as e:
                self.logger.error(f"Failed to parse JSON: {e}")

        return results

    def _analyze_container(self, container: Dict[str, Any]) -> ContainerStatus:
        """Analyze single container status based on criteria"""
        # TODO: Implement container analysis logic
        # Extract: State, Status, Names, calculate uptime, determine health
        # Apply criteria: running+healthy+uptime>1min = success, etc.
        pass

    def _parse_uptime(self, status_str: str) -> int:
        """Parse uptime from status string to seconds"""
        # TODO: Convert "Up 7 days", "Up 30 seconds" to seconds
        pass


def main():
    """Main analysis function"""
    analyzer = ContainerAnalyzer()

    try:
        results = analyzer.run_analysis()
        print(f"📊 Container Analysis Results:")
        # TODO: Print formatted results table
        for result in results:
            print(f"  {result.check_status.upper():8} {result.node}:{result.container_name} - {result.message}")

    except Exception as e:
        print(f"❌ Analysis failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()