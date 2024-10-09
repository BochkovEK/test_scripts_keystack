
mkdir -p $GITLAB_HOME/{data,logs,config/trusted-certs}
mkdir -p $GITLAB_RUNNER_HOME/{certs,builds,cache}
cp $CA_HOME/cert/chain-$GITLAB_NAME.pem $GITLAB_RUNNER_HOME/certs/$GITLAB_NAME.$DOMAIN.crt
cp $CA_HOME/cert/chain-ca.pem $GITLAB_RUNNER_HOME/certs/ca.crt
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp $CA_HOME/cert/$NEXUS_FQDN.pem $GITLAB_RUNNER_HOME/certs/$NEXUS_FQDN.crt
fi
cp config-template.toml $GITLAB_RUNNER_HOME
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" $GITLAB_RUNNER_HOME/config-template.toml
sed -i "s/RELEASE/$RELEASE/g" $GITLAB_RUNNER_HOME/config-template.toml
sed -i "s|GITLAB_RUNNER_HOME|$GITLAB_RUNNER_HOME|g" $GITLAB_RUNNER_HOME/config-template.toml
openssl rand -base64 20 > $CFG_HOME/gitlab_runner_token
ssh-keygen -qt rsa -b 2048 -N "" -f $CFG_HOME/gitlab_key -C "root@gitlab"
if [[ $LDAP_GITLAB == "y" ]]; then
  cp certs/ldaps.pem /$GITLAB_HOME/config/trusted-certs/ldaps.pem
  sed -i "s|LDAP_GITLAB|true|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI_GITLAB|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN_GITLAB|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-BIND-PASSWORD|$LDAP_BIND_PASSWORD_GITLAB|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN_GITLAB|" $CFG_HOME/compose.yaml
  sed -i "s|LDAP-REQUIRE-GROUP-DN|$LDAP_REQUIRE_GROUP_DN_GITLAB|" $CFG_HOME/compose.yaml
else
  sed -i "s|LDAP_GITLAB|false|" $CFG_HOME/compose.yaml
fi


##############
# * Netbox * #
##############
mkdir -p $NETBOX_HOME/{postgres,redis,redis-cache} $NETBOX_HOME/netbox/{configuration,media,reports,scripts}
cp netbox-docker/docker-compose.yml $CFG_HOME/netbox-compose.yml
cp -r netbox-docker/env $NETBOX_HOME
cp -r netbox-docker/configuration $NETBOX_HOME/netbox
cp netbox-docker/netbox.dump $CFG_HOME/netbox.dump
netbox_admin_password=$(grep SUPERUSER_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
netbox_db_password=$(grep DB_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
netbox_redis_password=$(grep REDIS_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
netbox_redis_cache_password=$(grep REDIS_CACHE_PASSWORD $NETBOX_HOME/env/netbox.env | awk -F '=' '{print $2}')
# Netbox LDAP settings
if [[ $LDAP_NETBOX == "y" ]]; then
  sed -i "s|LDAP-SERVER-URI|$LDAP_SERVER_URI_NETBOX|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-BIND-DN|$LDAP_BIND_DN_NETBOX|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-BIND-PASSWORD|$LDAP_BIND_PASSWORD_NETBOX|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-USER-SEARCH-BASEDN|$LDAP_USER_SEARCH_BASEDN_NETBOX|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-GROUP-SEARCH-BASEDN|$LDAP_GROUP_SEARCH_BASEDN_NETBOX|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-REQUIRE-GROUP-DN|$LDAP_REQUIRE_GROUP_DN_NETBOX|g" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-IS-ADMIN-DN|$LDAP_IS_ADMIN_DN_NETBOX|" $NETBOX_HOME/env/netbox.env
  sed -i "s|LDAP-IS-SUPERUSER-DN|$LDAP_IS_SUPERUSER_DN_NETBOX|" $NETBOX_HOME/env/netbox.env
  if [[ $LDAP_TLS_NETBOX == "y" ]]; then
    cp certs/ldaps.pem $NETBOX_HOME/netbox/configuration/ldaps.pem
  fi
fi