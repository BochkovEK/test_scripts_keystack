#!/bin/bash

#the script copy hosts to all nodes

#script_dir=$(dirname $0)
nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)|\-net\-..( |$)|\-lcm\-..( |$)'
parses_file=/etc/hosts

srv=$(cat $parses_file | grep -E "$nodes_to_find" | awk '{print $1}')
for host in $srv;do
  scp $parses_file $host:$parses_file
done