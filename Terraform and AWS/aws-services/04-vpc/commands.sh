#!/usr/bin/env bash
# VPC hands-on against LocalStack: one VPC, a public and a private subnet, IGW, routes, NACL.
set -euo pipefail
source ../localstack.env

python3 cidr_plan.py

VPC=$(awsl ec2 create-vpc --cidr-block 10.20.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=library-vpc}]' --query Vpc.VpcId --output text)
awsl ec2 modify-vpc-attribute --vpc-id "$VPC" --enable-dns-hostnames '{"Value":true}'

PUB=$(awsl ec2 create-subnet --vpc-id "$VPC" --cidr-block 10.20.1.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=library-public-a}]' --query Subnet.SubnetId --output text)
PRIV=$(awsl ec2 create-subnet --vpc-id "$VPC" --cidr-block 10.20.11.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=library-private-a}]' --query Subnet.SubnetId --output text)
awsl ec2 modify-subnet-attribute --subnet-id "$PUB" --map-public-ip-on-launch

# Internet gateway + a route table that sends 0.0.0.0/0 to it = a *public* subnet
IGW=$(awsl ec2 create-internet-gateway --query InternetGateway.InternetGatewayId --output text)
awsl ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
RT=$(awsl ec2 create-route-table --vpc-id "$VPC" --query RouteTable.RouteTableId --output text)
awsl ec2 create-route --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" > /dev/null
awsl ec2 associate-route-table --route-table-id "$RT" --subnet-id "$PUB" > /dev/null
# the private subnet keeps the VPC's main route table: only the local 10.20.0.0/16 route

awsl ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC" \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,MapPublicIpOnLaunch,AvailableIpAddressCount]' --output table
awsl ec2 describe-route-tables --route-table-ids "$RT" \
  --query 'RouteTables[0].Routes[].[DestinationCidrBlock,GatewayId]' --output table

# stateless NACL on the public subnet: allow HTTP in and ephemeral ports back out
NACL=$(awsl ec2 create-network-acl --vpc-id "$VPC" --query NetworkAcl.NetworkAclId --output text)
awsl ec2 create-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 100 \
  --protocol tcp --port-range From=80,To=80 --cidr-block 0.0.0.0/0 --rule-action allow
awsl ec2 create-network-acl-entry --network-acl-id "$NACL" --egress --rule-number 100 \
  --protocol tcp --port-range From=1024,To=65535 --cidr-block 0.0.0.0/0 --rule-action allow
awsl ec2 describe-network-acls --network-acl-ids "$NACL" \
  --query 'NetworkAcls[0].Entries[].[RuleNumber,Egress,Protocol,RuleAction,CidrBlock]' --output table

# --- cleanup (reverse order of creation) --------------------------------------
awsl ec2 delete-network-acl --network-acl-id "$NACL"
ASSOC=$(awsl ec2 describe-route-tables --route-table-ids "$RT" --query 'RouteTables[0].Associations[0].RouteTableAssociationId' --output text)
awsl ec2 disassociate-route-table --association-id "$ASSOC"
awsl ec2 delete-route-table --route-table-id "$RT"
awsl ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC"
awsl ec2 delete-internet-gateway --internet-gateway-id "$IGW"
awsl ec2 delete-subnet --subnet-id "$PUB"
awsl ec2 delete-subnet --subnet-id "$PRIV"
awsl ec2 delete-vpc --vpc-id "$VPC"
echo "VPC $VPC and its parts removed"
