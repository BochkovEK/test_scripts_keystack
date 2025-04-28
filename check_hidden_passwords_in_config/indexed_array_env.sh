#!/bin/bash

output_env_file=".config_list_for_2024.3"

# Create array
TS_CONTROL_CONFIG_LIST=(
  "/etc/kolla/drs/drs.ini"
  "/etc/kolla/cinder-volume/cinder.conf"
  "/etc/kolla/glance-api/glance-api.conf"
  "/etc/kolla/neutron-server/neutron.conf"
  "/etc/kolla/nova-api/nova.conf"
  "/etc/kolla/nova-api-bootstrap/nova.conf"
  "/etc/kolla/nova-conductor/nova.conf"
  "/etc/kolla/nova-novncproxy/nova.conf"
  "/etc/kolla/nova-conductor/nova.conf"
  "/etc/kolla/nova-scheduler/nova.conf"
  "/etc/kolla/nova-serialproxy/nova.conf"
  "/etc/kolla/keystone/keystone.conf"
  "/etc/kolla/adminui-backend/adminui-backend-osloconf.conf"
  "/etc/kolla/placement-api/placement.conf"
)

TS_COMPUTE_CONFIG_LIST=(
  "/etc/kolla/nova-compute/nova.conf"
)

TS_HASHED_PASSWORD_CONFIG_LIST=(
  "/etc/kolla/haproxy/services.d/opensearch-dashboards.cfg"
  "/etc/kolla/rabbitmq/definitions.json"
  "/etc/kolla/proxysql/users/*"
  "/etc/kolla/haproxy/services.d/prometheus-alertmanager.cfg"
)

TS_PROMETHEUS_EXPORTERS_CONFIG_LIST=(
)


#array with index to env
for i in "${!TS_CONTROL_CONFIG_LIST[@]}"; do
  echo "TS_CONTROL_CONFIG_LIST_$i=${TS_CONTROL_CONFIG_LIST[$i]}" >> $output_env_file
done

for i in "${!TS_COMPUTE_CONFIG_LIST[@]}"; do
  echo "TS_COMPUTE_CONFIG_LIST$i=${TS_COMPUTE_CONFIG_LIST[$i]}" >> $output_env_file
done

for i in "${!TS_HASHED_PASSWORD_CONFIG_LIST[@]}"; do
  echo "TS_HASHED_PASSWORD_CONFIG_LIST$i=${TS_HASHED_PASSWORD_CONFIG_LIST[$i]}" >> $output_env_file
done

for i in "${!TS_PROMETHEUS_EXPORTERS_CONFIG_LIST[@]}"; do
  echo "TS_PROMETHEUS_EXPORTERS_CONFIG_LIST$i=${TS_PROMETHEUS_EXPORTERS_CONFIG_LIST[$i]}" >> $output_env_file
done


