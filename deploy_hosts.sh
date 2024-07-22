nodes_to_find='\-ctrl\-..( |$)|\-comp\-..( |$)|\-net\-..( |$)'
srv=$(cat /etc/hosts | grep -E "$nodes_to_find" | awk '{print $1}')
for host in $srv;do
    echo "Copy hosts to $(cat /etc/hosts | grep -E ${host} | awk '{print $2}'):"
    scp /etc/hosts $host:/etc/hosts
done
