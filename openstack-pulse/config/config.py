import os
import yaml
from dotenv import load_dotenv
from keystoneauth1 import session
from keystoneauth1.identity import v3


class Config:
    def __init__(self):
        # Load environment variables from .env
        load_dotenv()

        # Load base config
        with open('config.yml') as f:
            self.settings = yaml.safe_load(f)

        # Create Keystone session
        self.session = self._create_session()

    def _create_session(self):
        auth = v3.Password(
            auth_url=os.getenv('OS_AUTH_URL'),
            username=os.getenv('OS_USERNAME'),
            password=os.getenv('OS_PASSWORD'),
            project_name=os.getenv('OS_PROJECT_NAME'),
            user_domain_name=os.getenv('OS_USER_DOMAIN_NAME', 'Default')
        )
        return session.Session(auth=auth)

    @property
    def check_interval(self):
        return self.settings['intervals']['check_interval']