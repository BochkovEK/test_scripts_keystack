import os
import yaml
from dotenv import load_dotenv
from keystoneauth1 import session
from keystoneauth1.identity import v3


class DotDict:
    """Simple dot-notation access to dictionary attributes"""

    def __init__(self, data):
        for key, value in data.items():
            if isinstance(value, dict):
                setattr(self, key, DotDict(value))
            else:
                setattr(self, key, value)


class Config:
    def __init__(self):
        # Load environment variables from .env
        load_dotenv()

        # Get project root directory
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        # Load base config with absolute path
        config_path = os.path.join(self.project_root, 'config', 'config.yml')
        with open(config_path) as f:
            config_data = yaml.safe_load(f)

        # Convert to dot notation for easy access
        self.settings = DotDict(config_data)

        # Create Keystone session
        self.session = self._create_session()

    def _create_session(self):
        auth = v3.Password(
            auth_url=os.getenv('OS_AUTH_URL'),
            username=os.getenv('OS_USERNAME'),
            password=os.getenv('OS_PASSWORD'),
            project_name=os.getenv('OS_PROJECT_NAME'),
            user_domain_name=os.getenv('OS_USER_DOMAIN_NAME', 'Default'),
            project_domain_name=os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default')
        )
        return session.Session(auth=auth)
