#!/usr/bin/env bash

read -r -p "Domain name [itkey]: " domain
domain=${domain:-itkey}

read -r -p "Projcet name [demo]: " project
project=${project:-demo}

user_domain="$domain"

declare -A group_role_map
group_role_map=(
        [pes_member]='member'
        [pes_admin]='admin'
        [pes_security_auditor]='reader'
        [pes_reader]='reader'
)

function openstack() { command openstack --insecure "$@"; }

function run() {
        (( DEBUG )) && printf 'Running: %s\n' "$*" >&2
        (( DRY_RUN )) || "$@"
}

declare -A group_id_map
while mapfile -t -n 2 ary && (( ${#ary[@]} )); do
        (( DEBUG )) && printf '%s %s\n' "${ary[@]}"
        group_id_map["${ary[1]}"]="${ary[0]}"
done < <(
        openstack group list -f json --domain itkey | jq -r '.[] | .ID, .Name'
)

for group in "${!group_role_map[@]}"; do
        run openstack role add --project "$project" --group "${group_id_map[$group]}" --user-domain "$user_domain" "${group_role_map[$group]}"
done

run openstack role add --domain "$domain" --group "${group_id_map[pes_admin]}" --user-domain "$user_domain" --inherited admin
run openstack role add --system all --group "${group_id_map[pes_admin]}" --user-domain "$user_domain" admin

run openstack role add --domain "$domain" --group "${group_id_map[pes_reader]}" --user-domain "$user_domain" --inherited reader
run openstack role add --system all --group "${group_id_map[pes_reader]}" --user-domain "$user_domain" reader
