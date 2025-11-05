"""
Main diagnostics module for OpenStack
Coordinates all diagnostic checks and provides unified reporting
"""

import sys
from pathlib import Path
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
import json

# Fix imports for direct script execution
if __name__ == "__main__":
    # Add src to path when running directly
    src_path = Path(__file__).parent / 'src'
    sys.path.insert(0, str(src_path))

    from config import get_config
    from logger import get_logger
    from ansible_executor import get_ansible_runner
else:
    # Normal relative imports when used as module
    from .config import get_config
    from .logger import get_logger
    from .ansible_executor import get_ansible_runner


@dataclass
class CheckResult:
    """Result of a single diagnostic check"""
    name: str
    status: str  # 'success', 'warning', 'error'
    message: str
    details: Dict[str, Any] = None
    duration: float = 0.0


class OpenStackDiagnostics:
    """
    Main diagnostics class for OpenStack environment
    Performs comprehensive health checks across all components
    """

    def __init__(self):
        self.config = get_config()
        self.runner = get_ansible_runner(self.config)
        self.logger = get_logger(__name__)
        self.results: List[CheckResult] = []

    def run_full_diagnosis(self) -> Dict[str, Any]:
        """
        Execute complete OpenStack diagnostics

        Returns:
            Dict with overall status and detailed results
        """
        self.logger.info("Starting comprehensive OpenStack diagnostics")

        # 1. Container status on nodes
        container_results = self.check_containers()

        # 2. Keystone service
        keystone_results = self.check_keystone()

        # 3. MariaDB/Galera
        database_results = self.check_database()

        # 4. RabbitMQ
        rabbitmq_results = self.check_rabbitmq()

        return self._compile_report()

    def check_containers(self) -> List[CheckResult]:
        """Check Podman container status on all nodes"""
        self.logger.info("Checking Podman containers status")
        results = []

        try:
            # Run container check playbook
            ansible_result = self.runner.run_playbook("check_containers.yml")

            if not ansible_result['success']:
                results.append(CheckResult(
                    name="container_status",
                    status="error",
                    message=f"Failed to check containers: {ansible_result['error']}"
                ))
                return results

            # Parse container status from Ansible output
            container_checks = self._parse_container_status(ansible_result['stdout'])
            results.extend(container_checks)

        except Exception as e:
            self.logger.error(f"Container check failed: {e}")
            results.append(CheckResult(
                name="container_status",
                status="error",
                message=f"Container check exception: {str(e)}"
            ))

        return results

    def _parse_container_status(self, ansible_output: str) -> List[CheckResult]:
        """
        Parse container status from Podman JSON output

        Returns:
            List of CheckResult objects with container health analysis
        """
        results = []

        try:
            # Extract JSON data from Ansible output
            json_data = self._extract_json_from_output(ansible_output)
            if not json_data:
                return [CheckResult(
                    name="container_parsing",
                    status="error",
                    message="No JSON container data found in output"
                )]

            # Parse containers from JSON array
            containers = json.loads(json_data) if isinstance(json_data, str) else json_data

            for container in containers:
                name = container.get('Names', ['unknown'])[0] if container.get('Names') else 'unknown'
                status = container.get('Status', '')
                state = container.get('State', '')
                created = container.get('CreatedAt', '')

                # Analyze container state
                container_result = self._analyze_container_state(name, created, status, state)
                results.append(container_result)

        except Exception as e:
            return [CheckResult(
                name="container_parsing",
                status="error",
                message=f"Error parsing container JSON: {str(e)}"
            )]

        return results

    def _extract_json_from_output(self, ansible_output: str) -> Optional[Any]:
        """
        Extract JSON data from Ansible command output using json module

        Returns:
            JSON data or None if not found
        """

        try:
            # Method 1: Try to parse entire output as JSON
            try:
                return json.loads(ansible_output)
            except json.JSONDecodeError:
                pass

            # Method 2: Look for JSON in containers_json.stdout lines
            lines = ansible_output.split('\n')
            for i, line in enumerate(lines):
                if 'containers_json.stdout' in line and i + 1 < len(lines):
                    # Try to parse the next line as JSON
                    json_line = lines[i + 1].strip()
                    try:
                        return json.loads(json_line)
                    except json.JSONDecodeError:
                        continue

            # Method 3: Find any line that contains valid JSON
            for line in lines:
                line = line.strip()
                if line.startswith('[') or line.startswith('{'):
                    try:
                        return json.loads(line)
                    except json.JSONDecodeError:
                        continue

        except Exception as e:
            print(f"JSON extraction error: {e}")

        return None

    @staticmethod
    def _parse_uptime_from_status(status: str) -> Dict[str, int]:
        """
        Parse uptime from container status string

        Returns:
            Dict with uptime in minutes, hours, days
        """
        try:
            if "Up" in status:
                # Examples: "Up 2 days", "Up 5 minutes", "Up 1 hour"
                parts = status.split()
                if len(parts) >= 3:
                    value = int(parts[1])
                    unit = parts[2].lower()

                    # Convert to minutes for easy comparison
                    if "minute" in unit:
                        return {"minutes": value, "hours": 0, "days": 0}
                    elif "hour" in unit:
                        return {"minutes": value * 60, "hours": value, "days": 0}
                    elif "day" in unit:
                        return {"minutes": value * 1440, "hours": value * 24, "days": value}

            return {"minutes": 0, "hours": 0, "days": 0}
        except:
            return {"minutes": 0, "hours": 0, "days": 0}

    @staticmethod
    def _extract_json_from_output(ansible_output: str) -> Optional[Dict]:
        """
        Extract JSON data from Ansible output

        Returns:
            JSON dictionary or None if not found
        """
        import json
        import re

        # Try to find JSON in the output
        try:
            # Look for JSON pattern
            json_match = re.search(r'\{.*\}', ansible_output, re.DOTALL)
            if json_match:
                return json.loads(json_match.group())
        except:
            pass

        return None

    def _analyze_container_state(self, name: str, created: str, status: str, health: str) -> CheckResult:
        """
        Analyze container state for ALL containers with uptime and health checks

        Args:
            name: Container name
            created: Creation timestamp
            status: Container status string (e.g., "Up 2 days", "Exited")
            health: Health status (healthy, unhealthy, or empty)

        Returns:
            CheckResult with container health assessment
        """
        # Analyze container status - check ALL containers
        if status.startswith("Up"):
            # Parse uptime from status (format: "Up 2 days", "Up 5 minutes", etc.)
            uptime_info = self._parse_uptime_from_status(status)

            # Check health status if available
            if health == "unhealthy":
                return CheckResult(
                    name=f"container_{name}",
                    status="error",
                    message=f"Container {name} is running but unhealthy",
                    details={"status": status, "health": health, "created": created, "uptime": uptime_info}
                )

            # Check for recently started containers (less than 1 minute)
            if uptime_info and uptime_info.get('minutes', 0) < 1:
                return CheckResult(
                    name=f"container_{name}",
                    status="warning",
                    message=f"Container {name} recently started ({status})",
                    details={"status": status, "health": health, "created": created, "uptime": uptime_info}
                )

            # Container is running, healthy (or no health check), and uptime > 1 minute
            health_message = "and healthy" if health == "healthy" else ""
            return CheckResult(
                name=f"container_{name}",
                status="success",
                message=f"Container {name} is running normally {health_message}({status})".strip(),
                details={"status": status, "health": health, "created": created, "uptime": uptime_info}
            )

        elif status == "exited":
            return CheckResult(
                name=f"container_{name}",
                status="error",
                message=f"Container {name} is exited",
                details={"status": status, "health": health, "created": created}
            )

        elif status == "restarting":
            return CheckResult(
                name=f"container_{name}",
                status="warning",
                message=f"Container {name} is restarting",
                details={"status": status, "health": health, "created": created}
            )

        # Unknown or other states
        return CheckResult(
            name=f"container_{name}",
            status="warning",
            message=f"Container {name} in unexpected state: {status}",
            details={"status": status, "health": health, "created": created}
        )

    def check_keystone(self) -> List[CheckResult]:
        """Check Keystone identity service"""
        self.logger.info("Checking Keystone service")
        # TODO: Implement Keystone checks
        return []

    def check_database(self) -> List[CheckResult]:
        """Check MariaDB/Galera database cluster"""
        self.logger.info("Checking database cluster")
        # TODO: Implement database checks
        return []

    def check_rabbitmq(self) -> List[CheckResult]:
        """Check RabbitMQ message queue"""
        self.logger.info("Checking RabbitMQ")
        # TODO: Implement RabbitMQ checks
        return []

    def _compile_report(self) -> Dict[str, Any]:
        """Compile final diagnostics report"""
        # TODO: Implement report compilation
        return {}


if __name__ == "__main__":
    diag = OpenStackDiagnostics()
    print("🚀 Starting OpenStack Diagnostics...")

    container_results = diag.check_containers()

    print("\n📊 CONTAINER RESULTS:")
    for result in container_results:
        print(f"  {result.status.upper():8} {result.name}: {result.message}")

    print(f"\n📈 Total: {len(container_results)} containers checked")
