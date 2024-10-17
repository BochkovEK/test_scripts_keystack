#!/bin/bash

srv=$(cat /etc/hosts | grep -E "ctrl|comp|lcm|net-" | awk '{print $1}')
for host in $srv; do
  scp /etc/hosts $host:/etc/hosts
done