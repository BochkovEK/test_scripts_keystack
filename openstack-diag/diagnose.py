"""
Main diagnostics module for OpenStack
Coordinates all diagnostic checks and provides unified reporting
"""

import sys
from pathlib import Path
from typing import Dict, List, Any
from dataclasses import dataclass

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
        self.ansible_runner = get_ansible_runner()
        self.results: List[CheckResult] = []

    def run_full_diagnosis(self) -> Dict[str, Any]:
        """
        Execute complete OpenStack diagnostics

        Returns:
            Dict with overall status and detailed results
        """
        logger.info("Starting comprehensive OpenStack diagnostics")

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
        logger.info("Checking Podman containers status")
        results = []

        try:
            # Run container check playbook
            ansible_result = self.ansible_runner.run_playbook("check_containers.yml")

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
            logger.error(f"Container check failed: {e}")
            results.append(CheckResult(
                name="container_status",
                status="error",
                message=f"Container check exception: {str(e)}"
            ))

        return results

    def _parse_container_status(self, ansible_output: str) -> List[CheckResult]:
        """
        Parse Podman container status from Ansible output

        Returns:
            List of CheckResult objects with container health analysis
        """
        results = []

        # Find container_list.stdout block in Ansible output
        if "container_list.stdout" not in ansible_output:
            return [CheckResult(
                name="container_parsing",
                status="error",
                message="No container data found in output"
            )]

        # Extract container data lines
        lines = ansible_output.split('\n')
        container_lines = []

        # Skip header and collect container data lines
        for line in lines:
            if "CONTAINER ID" in line:
                continue  # Skip header line
            if line.strip() and len(line.split()) >= 6:  # Minimum 6 columns
                container_lines.append(line)

        # Parse each container line
        for line in container_lines:
            parts = line.split()
            if len(parts) < 6:
                continue

            # Extract CREATED (4th from end), STATUS (3rd from end), NAME (last)
            created = parts[-4] + " " + parts[-3]  # "5 weeks ago"
            status = parts[-2] + " " + parts[-1]  # "Up 7 days"
            name = parts[-1]  # Container name

            # Analyze container state
            container_result = self._analyze_container_state(name, created, status)
            results.append(container_result)

        return results

    @staticmethod
    def _analyze_container_state(name: str, created: str, status: str) -> CheckResult:
        """
        Analyze individual container state based on status and uptime

        Returns:
            CheckResult with container health assessment
        """
        # Analyze STATUS field
        if status.startswith("Up"):
            # Extract uptime from status
            if "days" in status:
                days = int(status.split()[1])
                if days > 1:
                    return CheckResult(
                        name=f"container_{name}",
                        status="success",
                        message=f"Container {name} running stable ({status})",
                        details={"status": status, "created": created, "uptime_days": days}
                    )
                else:
                    return CheckResult(
                        name=f"container_{name}",
                        status="warning",
                        message=f"Container {name} recently restarted ({status})",
                        details={"status": status, "created": created, "uptime_days": days}
                    )

            elif "hours" in status:
                hours = int(status.split()[1])
                if hours > 1:
                    return CheckResult(
                        name=f"container_{name}",
                        status="success",
                        message=f"Container {name} running normally ({status})",
                        details={"status": status, "created": created, "uptime_hours": hours}
                    )
                else:
                    return CheckResult(
                        name=f"container_{name}",
                        status="warning",
                        message=f"Container {name} very recently started ({status})",
                        details={"status": status, "created": created, "uptime_hours": hours}
                    )

            elif "minutes" in status:
                minutes = int(status.split()[1])
                if minutes < 2:
                    return CheckResult(
                        name=f"container_{name}",
                        status="warning",
                        message=f"Container {name} just started ({status})",
                        details={"status": status, "created": created, "uptime_minutes": minutes}
                    )
                else:
                    return CheckResult(
                        name=f"container_{name}",
                        status="warning",
                        message=f"Container {name} recently started ({status})",
                        details={"status": status, "created": created, "uptime_minutes": minutes}
                    )

        # Handle non-running states
        elif status in ["Exited", "Restarting", "Unhealthy"]:
            return CheckResult(
                name=f"container_{name}",
                status="error",
                message=f"Container {name} has issues: {status}",
                details={"status": status, "created": created, "issue": "container_failed"}
            )

        # Unknown state
        return CheckResult(
            name=f"container_{name}",
            status="warning",
            message=f"Container {name} in unknown state: {status}",
            details={"status": status, "created": created}
        )

    def check_keystone(self) -> List[CheckResult]:
        """Check Keystone identity service"""
        logger.info("Checking Keystone service")
        # TODO: Implement Keystone checks
        return []

    def check_database(self) -> List[CheckResult]:
        """Check MariaDB/Galera database cluster"""
        logger.info("Checking database cluster")
        # TODO: Implement database checks
        return []

    def check_rabbitmq(self) -> List[CheckResult]:
        """Check RabbitMQ message queue"""
        logger.info("Checking RabbitMQ")
        # TODO: Implement RabbitMQ checks
        return []

    def _compile_report(self) -> Dict[str, Any]:
        """Compile final diagnostics report"""
        # TODO: Implement report compilation
        return {}


if __name__ == "__main__":
    # Direct execution
    diag = OpenStackDiagnostics()
    print("🚀 Starting OpenStack Diagnostics...")
    result = diag.run_full_diagnosis()
    print("📊 Diagnostics completed!")

