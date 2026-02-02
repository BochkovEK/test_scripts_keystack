escape_sed() {
  # Escape only what's needed for the sed replacement part
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

if [[ $KS_LDAP_USE == "y" ]]; then
  #echo "Copy certificates"
  #cp certs/ldaps.pem "$GITLAB_HOME/config/trusted-certs/ldaps.pem"
  #cat "certs/ldaps.pem" >> "$GITLAB_RUNNER_HOME/certs/ca.crt"

  echo "Use a portable delimiter (| can conflict if value has /)"
  echo "Always escape sed-sensitive characters in replacement values"
  sed -i "s|LDAP_USE|true|" "./compose.yaml"
  sed -i "s|LDAP-SERVER-URI|$(escape_sed "$KS_LDAP_SERVER_URI")|" \
         "./compose.yaml"
  sed -i "s|LDAP-SERVER-PORT|$(escape_sed "$KS_LDAP_SERVER_PORT")|" \
         "./compose.yaml"
  sed -i "s|LDAP-USER-SEARCH-BASEDN|$(escape_sed "$KS_LDAP_USER_SEARCH_BASEDN")|" \
         "./compose.yaml"
  sed -i "s|LDAP-READER-GROUP-DN|$(escape_sed "$KS_LDAP_READER_GROUP_DN")|" \
         "./compose.yaml"
  sed -i "s|LDAP-AUDITOR-GROUP-DN|$(escape_sed "$KS_LDAP_AUDITOR_GROUP_DN")|" \
         "./compose.yaml"
  sed -i "s|LDAP-ADMIN-GROUP-DN|$(escape_sed "$KS_LDAP_ADMIN_GROUP_DN")|" \
         "./compose.yaml"
  sed -i "s|LDAP-BIND-DN|$(escape_sed "$KS_LDAP_BIND_DN")|" \
         "./compose.yaml"

  echo "Remove LDAP-BIND-DN & LDAP-BIND-PASSWORD if defined"
  sed -i '/LDAP-BIND-DN/d;/LDAP-BIND-PASSWORD/d' "./compose.yaml"
else
  sed -i "s|LDAP_USE|false|" "./compose.yaml"
fi
