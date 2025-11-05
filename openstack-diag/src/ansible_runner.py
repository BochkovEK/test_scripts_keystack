"""
Ansible Runner Module for OpenStack Diagnostics
Provides running Ansible playbooks and processing results
"""

import os
import subprocess
import tempfile
import json
from typing import Dict, List, Optional, Any, Tuple
from pathlib import Path

from .logger import get_logger
from .config import Config

logger = get_logger(__name__)


class AnsibleRunner:
    def __init__(self, config: Config):
        self.config = config
        self.ansible_path = Path(__file__).parent.parent / 'ansible'
        self.playbooks_path = self.ansible_path / 'playbooks'
        self.inventory_path = Path(__file__).parent.parent / 'inventory.ini'

        self.playbooks_path.mkdir(parents=True, exist_ok=True)

        logger.info(f"Ansible Runner initialized. Playbooks path: {self.playbooks_path}")

    def run_playbook(self, playbook_name: str) -> Dict[str, Any]:
        """
        Run Ansible playbook for OpenStack diagnostics

        Args:
            playbook_name: Playbook name to execute

        Returns:
            Dict with execution results
        """
        playbook_path = self.playbooks_path / playbook_name

        if not playbook_path.exists():
            error_msg = f"Playbook not found: {playbook_path}"
            logger.error(error_msg)
            return {
                'success': False,
                'error': error_msg,
                'return_code': -1,
                'output': ''
            }

        # Build Ansible command
        cmd = self._build_ansible_command(playbook_path)

        logger.info(f"Running Ansible playbook: {' '.join(cmd)}")

        try:
            # Execute command
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                cwd=self.ansible_path
            )

            # Parse result
            return self._parse_ansible_result(result, playbook_name)

        except Exception as e:
            error_msg = f"Error executing playbook {playbook_name}: {str(e)}"
            logger.error(error_msg)
            return {
                'success': False,
                'error': error_msg,
                'return_code': -1,
                'output': ''
            }

    def _build_ansible_command(self,
                               playbook_path: Path,
                               extra_vars: Optional[Dict[str, Any]],
                               tags: Optional[List[str]],
                               limit: Optional[str]) -> List[str]:
        """
        Build Ansible command

        Returns:
            List[str]: Command to execute
        """
        cmd = [
            'ansible-playbook',
            '-i', str(self.inventory_path),
            str(playbook_path)
        ]

        # Add extra variables
        if extra_vars:
            vars_str = ' '.join([f"{k}={v}" for k, v in extra_vars.items()])
            cmd.extend(['--extra-vars', vars_str])

        # Add tags
        if tags:
            cmd.extend(['--tags', ','.join(tags)])

        # Add limit
        if limit:
            cmd.extend(['--limit', limit])

        # Add configuration parameters
        if self.config.ansible.get('verbose', False):
            cmd.append('-v')

        if self.config.ansible.get('check_mode', False):
            cmd.append('--check')

        if self.config.ansible.get('diff_mode', False):
            cmd.append('--diff')

        return cmd

    def _parse_ansible_result(self, result: subprocess.CompletedProcess, playbook_name: str) -> Dict[str, Any]:
        """
        Parse Ansible execution result

        Returns:
            Dict with structured results
        """
        success = result.returncode == 0

        # Base result
        ansible_result = {
            'success': success,
            'return_code': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'playbook': playbook_name
        }

        if success:
            logger.info(f"Playbook {playbook_name} executed successfully")
            ansible_result['message'] = f"Playbook {playbook_name} executed successfully"
        else:
            logger.error(f"Playbook {playbook_name} failed. Code: {result.returncode}")
            ansible_result['error'] = f"Playbook failed. Code: {result.returncode}"
            ansible_result['message'] = result.stderr or result.stdout

        # Try to extract JSON output if present
        json_output = self._extract_json_output(result.stdout)
        if json_output:
            ansible_result['json_output'] = json_output

        return ansible_result