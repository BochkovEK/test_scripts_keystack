#!/bin/bash

# by hand

{
TARGET="compute-01"; \
VMS="vm1 vm2 vm3"; \
for vm in $VMS; do \
  openstack server migrate --os-compute-api-version 2.53\
    --live-migration \
    --host $TARGET \
     $vm & \
  sleep 0.5; \
done; \
}

#watch -d -c "openstack server migration list -c ID -c 'Source Node' -c 'Dest Node' -c Status -c 'Created At' -c 'Updated At' -c 'Server UUID'"

openstack server list --all-proj --long|grep -E "test-vm-08.*cdm-bl-pca06|test-vm-09.*cdm-bl-pca06"
