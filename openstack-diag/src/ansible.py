"""
Ansible for OpenStack Diagnostics
Uses ansible-runner library for playbook run
"""

from pathlib import Path
from typing import Dict, Any
import ansible_runner

from logger import get_logger

logger = get_logger(__name__)


class Ansible:
    """Ansible playbook runner using ansible-runner"""

    def __init__(self, config):
        self.config = config
        self.ansible_path = Path(__file__).parent.parent / 'ansible'
        self.playbooks_path = self.ansible_path / 'playbooks'
        self.inventory_path = Path(__file__).parent.parent / 'inventory.ini'
        self.ansible_cfg_path = self.config.ansible_cfg_path  # ✅ Берем из config.py

        if not self.ansible_cfg_path.exists():
            logger.warning(f"ansible.cfg not found: {self.ansible_cfg_path}")
        else:
            logger.info(f"Using ansible.cfg: {self.ansible_cfg_path}")

        # Debug: log Ansible configuration
        logger.info("Ansible configuration:")
        logger.info(f"  - Inventory: {self.inventory_path}")
        logger.info(f"  - Ansible path: {self.ansible_path}")
        logger.info(f"  - Playbooks path: {self.playbooks_path}")

        logger.info(f"Ansible initialized with ansible-runner")

    def run_playbook(self, playbook_name: str) -> Dict[str, Any]:
        """
        Run Ansible playbook using ansible-runner

        Args:
            playbook_name: Name of playbook to run

        Returns:
            Dict with execution results
        """
        playbook_path = self.playbooks_path / playbook_name

        if not playbook_path.exists():
            return {
                'success': False,
                'error': f"Playbook not found: {playbook_path}",
                'return_code': -1
            }

        logger.info(f"Running playbook: {playbook_name}")

        try:
            # result = ansible_runner.run(invento=foo)
            result = ansible_runner.run(
                playbook=str(playbook_path),
                inventory=str(self.inventory_path),
                private_data_dir=str(self.ansible_path),
                quiet=True,
                # ansible_cfg=str(self.ansible_cfg_path)
            )

            return {
                'success': result.status == 'successful',
                'return_code': result.rc,
                'stdout': result.stdout.read() if result.stdout else '',
                'stderr': result.stderr.read() if result.stderr else '',
                'status': result.status
            }

        except Exception as e:
            logger.error(f"Playbook execution failed: {e}")
            return {
                'success': False,
                'error': str(e),
                'return_code': -1
            }

    def get_available_playbooks(self):
        """Get list of available playbooks"""
        playbooks = []
        if self.playbooks_path.exists():
            for file in self.playbooks_path.glob('*.yml'):
                playbooks.append(file.name)
            for file in self.playbooks_path.glob('*.yaml'):
                playbooks.append(file.name)
        return playbooks


# Global instance
_ansible_executor = None


def get_ansible_runner(config=None):
    """Get Ansible instance"""
    global _ansible_executor
    if _ansible_executor is None:
        if config is None:
            from .config import get_config
            config = get_config()
        _ansible_executor = Ansible(config)
    return _ansible_executor

