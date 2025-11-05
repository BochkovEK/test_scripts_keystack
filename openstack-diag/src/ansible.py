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
        self.ansible_path = Path(self.config.ansible_path)
        self.inventory_path = Path(self.config.inventory_path)
        self.ansible_cfg_path = self.config.ansible_cfg_path

        if not self.ansible_cfg_path.exists():
            logger.warning(f"ansible.cfg not found: {self.ansible_cfg_path}")

        if not self.inventory_path.exists():
            logger.warning(f"Inventory file not found: {self.inventory_path}")

        logger.info("Ansible configuration:")
        logger.info(f"  - Inventory: {self.inventory_path}")
        logger.info(f"  - Ansible path: {self.ansible_path}")
        logger.info(f"  - Ansible config: {self.ansible_cfg_path}")

    def run_playbook(self, playbook_path: str) -> Dict[str, Any]:
        """
        Run Ansible playbook using ansible-runner

        Args:
            playbook_path: Full path to playbook file

        Returns:
            Dict with execution results
        """
        playbook_path = Path(playbook_path)

        if not playbook_path.exists():
            return {
                'success': False,
                'error': f"Playbook not found: {playbook_path}",
                'return_code': -1
            }

        logger.info(f"Running playbook: {playbook_path}")

        try:
            result = ansible_runner.run(
                playbook=str(playbook_path),
                inventory=str(self.inventory_path),
                private_data_dir=str(self.ansible_path),
                quiet=True,
                envvars={
                    'ANSIBLE_CONFIG': str(self.ansible_cfg_path)
                }
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

    def get_available_playbooks(self) -> Dict[str, Path]:
        """Get dictionary of available playbooks from configured playbooks directory"""
        playbooks = {}
        playbooks_dir = Path(self.config.playbooks_path)  # ✅ Из конфига

        if playbooks_dir.exists():
            for pattern in ['*.yml', '*.yaml']:
                for file in playbooks_dir.glob(pattern):
                    playbooks[file.name] = file
        else:
            logger.warning(f"Playbooks directory not found: {playbooks_dir}")

        return playbooks


# Global instance
_ansible = None


def get_ansible_runner(config=None):
    """Get Ansible instance"""
    global _ansible
    if _ansible is None:
        if config is None:
            from .config import get_config
            config = get_config()
        _ansible = Ansible(config)
    return _ansible
