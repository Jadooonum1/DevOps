#!/usr/bin/env bash
# EC2 hands-on against LocalStack. LocalStack's community EC2 is a mock: instances get IDs, states
# and IPs, but no real VM boots, so there is nothing to SSH into.
set -euo pipefail
source ../localstack.env

# --- prerequisites: image, key pair, security group ----------------------
AMI=$(awsl ec2 describe-images --owners amazon \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
echo "using AMI $AMI"

awsl ec2 create-key-pair --key-name reader-web-key --key-type ed25519 \
  --query KeyMaterial --output text > reader-web-key.pem
chmod 600 reader-web-key.pem          # never commit this file (.gitignore covers *.pem)

SG=$(awsl ec2 create-security-group --group-name reader-web-sg \
  --description "reader-web: HTTP from anywhere, SSH from admin only" \
  --query GroupId --output text)
awsl ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 > /dev/null
awsl ec2 authorize-security-group-ingress --group-id "$SG" --protocol tcp --port 22 --cidr 203.0.113.10/32 > /dev/null
awsl ec2 describe-security-groups --group-ids "$SG" \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,IpRanges[0].CidrIp]' --output table

# --- launch -----------------------------------------------------------------
IID=$(awsl ec2 run-instances --image-id "$AMI" --instance-type t3.micro --count 1 \
  --key-name reader-web-key --security-group-ids "$SG" \
  --user-data file://user-data.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=reader-web-1},{Key=app,Value=library}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "launched $IID"
awsl ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,State.Name,PrivateIpAddress,PublicIpAddress,Placement.AvailabilityZone]' \
  --output table

# --- extra EBS volume ---------------------------------------------------------
AZ=$(awsl ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text)
VOL=$(awsl ec2 create-volume --availability-zone "$AZ" --size 8 --volume-type gp3 \
  --tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=reader-web-data}]' \
  --query VolumeId --output text)
awsl ec2 attach-volume --volume-id "$VOL" --instance-id "$IID" --device /dev/sdf
awsl ec2 describe-volumes --volume-ids "$VOL" --query 'Volumes[0].[VolumeId,Size,VolumeType,State]' --output text

# --- lifecycle: running -> stopped -> running -> terminated ------------------
state() { awsl ec2 describe-instances --instance-ids "$IID" --query 'Reservations[0].Instances[0].State.Name' --output text; }
awsl ec2 stop-instances --instance-ids "$IID" > /dev/null;  echo "after stop:  $(state)"
awsl ec2 start-instances --instance-ids "$IID" > /dev/null; echo "after start: $(state)"
awsl ec2 terminate-instances --instance-ids "$IID" > /dev/null; echo "after terminate: $(state)"

# --- cleanup ----------------------------------------------------------------
awsl ec2 delete-volume --volume-id "$VOL" || true
awsl ec2 delete-security-group --group-id "$SG"
awsl ec2 delete-key-pair --key-name reader-web-key
rm -f reader-web-key.pem
