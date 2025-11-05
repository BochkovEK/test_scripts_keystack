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
        self.base_dir = Path(__file__).parent
        self.playbook_path = Path(self.base_dir / 'ansible/playbooks/check_containers.yml')  # Hardcoded path

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
        """Parse Ansible task output with node information"""
        results = []

        # Разделяем вывод по строкам и ищем блоки
        lines = output.split('\n')
        i = 0

        while i < len(lines):
            line = lines[i].strip()

            # Ищем строку начала блока с контейнерами
            if line.startswith('ok: [') and '=>' in line:
                node = line.split('[', 1)[1].split(']', 1)[0]

                # Ищем следующие строки до закрывающей фигурной скобки
                json_lines = []
                brace_count = 0
                json_started = False

                for j in range(i, len(lines)):
                    current_line = lines[j]

                    if '"containers_json.stdout":' in current_line:
                        json_started = True

                    if json_started:
                        json_lines.append(current_line)

                        # Подсчитываем фигурные скобки для нахождения конца JSON объекта
                        brace_count += current_line.count('{') - current_line.count('}')

                        if brace_count <= 0 and current_line.strip() == '}':
                            break

                # Объединяем строки и ищем JSON массив
                block_content = '\n'.join(json_lines)
                json_match = re.search(r'"containers_json\.stdout":\s*(\[.*?\])', block_content, re.DOTALL)

                if json_match:
                    try:
                        json_str = json_match.group(1)
                        containers_data = json.loads(json_str)

                        for container in containers_data:
                            container_status = self._analyze_container(node, container)
                            results.append(container_status)

                    except json.JSONDecodeError as e:
                        self.logger.error(f"JSON parse error for node {node}: {e}")

            i += 1

        return results

    def _analyze_container(self, node: str, container: Dict[str, Any]) -> ContainerStatus:
        """Analyze single container status based on criteria"""

        # Extract container data
        name = container.get('Names', 'unknown')
        state = container.get('State', 'unknown')
        status_str = container.get('Status', '')

        # Parse health and uptime
        health = "healthy" if "(healthy)" in status_str else "unhealthy" if "(unhealthy)" in status_str else "unknown"
        uptime_seconds = self._parse_uptime(status_str)

        # Apply criteria
        check_status, message = self._evaluate_container_status(state, health, uptime_seconds)

        return ContainerStatus(
            node=node,
            container_name=name,
            state=state,
            status=status_str,
            health=health,
            uptime_seconds=uptime_seconds,
            check_status=check_status,
            message=message
        )

    def _evaluate_container_status(self, state: str, health: str, uptime_seconds: int) -> tuple:
        """Evaluate container status based on criteria"""

        if state == "running" and health == "healthy":
            if uptime_seconds > 60:  # > 1 minute
                return "success", "Container is running and healthy"
            else:
                return "warning", "Container recently restarted (< 1 min)"

        elif state in ["exited", "unhealthy", "restarting"]:
            return "error", f"Container state: {state}"

        else:
            return "error", f"Unexpected state: {state}, health: {health}"

    def _parse_uptime(self, status_str: str) -> int:
        """Convert status string like 'Up 7 days (healthy)' to seconds"""
        if not status_str or 'Up' not in status_str:
            return 0

        # Patterns: "Up 7 days", "Up 2 minutes", "Up 30 seconds"
        time_pattern = r'Up\s+(\d+)\s+(second|minute|hour|day|week)s?'
        match = re.search(time_pattern, status_str)

        if match:
            value = int(match.group(1))
            unit = match.group(2)

            multipliers = {
                'second': 1,
                'minute': 60,
                'hour': 3600,
                'day': 86400,
                'week': 604800
            }

            return value * multipliers.get(unit, 1)

        return 0


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