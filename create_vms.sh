#Security group

project1=
project2=

# Создать не шаренную сеть Net1_1 (shared=no)
openstack network create \
    --project $project1 \
    --internal \
    --no-share \
    --description "No shared network for project $project1" \
    Net1_1

# Создать подсеть для Net1_1 (192.168.1.0/24)
openstack subnet create \
    --network Net1_1 \
    --subnet-range 192.168.1.0/24 \
    Sub_Net1_1

# Создать не шаренную сеть Net1_2 (shared=no)
openstack network create \
    --project $project2 \
    --internal \
    --no-share \
    --description "No shared network for project $project2" \
    Net1_2

# Создать подсеть для Net1_2 (10.0.1.0/24)
openstack subnet create \
    --network Net1_2 \
    --subnet-range 10.0.1.0/24 \
    Sub_Net1_2

# Создать шаренную сеть Net2_2 (shared=yes)
openstack network create \
    --project $project2 \
    --internal \
    --share \
    --description "Shared network $project2" \
    Net2_2

# Создать подсеть для Net2_2 (например, 172.16.0.0/24)
openstack subnet create \
    --network Net2_2 \
    --subnet-range 172.16.0.0/24 \
    Sub_Net2_2

# Проверить созданные сети:
for net in Net1_1 Net1_2 Net2_2; do openstack network show $net; done

# Создать SecurityGroup1
openstack security group create \
    --project $project1 \
    --description "Security Group 1 for $project1" \
    SecurityGroup1

# Создать SecurityGroup2
openstack security group create \
    --project $project1 \
    --description "Security Group 2 for $project1" \
    SecurityGroup2

# Создать SecurityGroup3
openstack security group create \
    --project $project2 \
    --description "Security Group 3 for $project2" \
    SecurityGroup3

# Один цикл для всех групп SecurityGroup1, SecurityGroup2, SecurityGroup3
for sg_id in $(openstack security group list -f value -c ID -c Name | grep -E "SecurityGroup1|SecurityGroup2|SecurityGroup3" | awk '{print $1}'); do
    echo "Adding rules to group ID: $sg_id..."

    # Egress для ICMP
    openstack security group rule create \
        --ingress \
        --ethertype IPv4 \
        --protocol icmp \
        --remote-ip 0.0.0.0/0 \
        --description "ICMP to anywhere" \
        $sg_id

    # Egress для SSH
    openstack security group rule create \
        --ingress \
        --ethertype IPv4 \
        --protocol tcp \
        --remote-ip 0.0.0.0/0 \
        --description "TCP to anywhere" \
        $sg_id

    echo "Rules added to group ID: $sg_id"
done

# Проверить созданные группы
for sg in SecurityGroup1 SecurityGroup2 SecurityGroup3; do openstack security gr show $sg; done

# TestVM1_1: Проект_1, Сеть2_2, SecurityGroup1
openstack --os-project-name "$project1" server create \
  --image "ubuntu-22.04-x64" \
  --flavor "ubuntu_vm-flavor" \
  --network "Net2_2" \
  --network "pub_net" \
  --security-group "SecurityGroup1" \
  --key-name "terraform_keypair" \
  "test-vm-sg-1-1"

# TestVM2_1: Проект_1, Сеть1_1, SecurityGroup2
openstack --os-project-name "$project1" server create \
  --image "ubuntu-22.04-x64" \
  --flavor "ubuntu_vm-flavor" \
  --network "Net1_1" \
  --network "pub_net" \
  --security-group "SecurityGroup2" \
  --key-name "terraform_keypair" \
  "test-vm-sg-2-1"

# TestVM3_1: Проект_1, Сеть1_1, SecurityGroup1
openstack --os-project-name "$project1" server create \
  --image "ubuntu-22.04-x64" \
  --flavor "ubuntu_vm-flavor" \
  --network "Net1_1" \
  --network "pub_net" \
  --security-group "SecurityGroup1" \
  --key-name "terraform_keypair" \
  "test-vm-sg-3-1"

# TestVM1_2: Проект_2, Сеть1_2, SecurityGroup3
openstack --os-project-name "$project2" server create \
  --image "ubuntu-22.04-x64" \
  --flavor "ubuntu_vm-flavor" \
  --network "Net1_2" \
  --network "pub_net" \
  --security-group "SecurityGroup3" \
  --key-name "terraform_keypair" \
  "test-vm-sg-1-2"