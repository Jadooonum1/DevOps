#!/usr/bin/env bash
# IAM hands-on against LocalStack. Run from this folder:  bash commands.sh
set -euo pipefail
source ../localstack.env

# --- users, group, customer-managed policy --------------------------------
awsl iam create-group --group-name library-staff
for u in asha-librarian ravi-cataloguer; do
  awsl iam create-user --user-name "$u" --tags Key=team,Value=library
  awsl iam add-user-to-group --group-name library-staff --user-name "$u"
done

POLICY_ARN=$(awsl iam create-policy --policy-name catalog-covers-read-only \
  --policy-document file://policies/catalog-covers-read-only.json \
  --query Policy.Arn --output text)
awsl iam attach-group-policy --group-name library-staff --policy-arn "$POLICY_ARN"

# an explicit Deny always wins over any Allow
awsl iam put-group-policy --group-name library-staff --policy-name deny-delete-catalog \
  --policy-document file://policies/deny-delete-catalog.json

awsl iam get-group --group-name library-staff --query 'Users[].UserName'
awsl iam list-attached-group-policies --group-name library-staff
awsl iam list-group-policies --group-name library-staff

# --- a role that EC2 instances can assume ----------------------------------
awsl iam create-role --role-name bookshelf-ec2-role \
  --assume-role-policy-document file://policies/ec2-assume-role-trust.json
awsl iam attach-role-policy --role-name bookshelf-ec2-role --policy-arn "$POLICY_ARN"
awsl iam create-instance-profile --instance-profile-name bookshelf-ec2-profile
awsl iam add-role-to-instance-profile --instance-profile-name bookshelf-ec2-profile \
  --role-name bookshelf-ec2-role
awsl iam get-instance-profile --instance-profile-name bookshelf-ec2-profile \
  --query 'InstanceProfile.Roles[].RoleName'

# temporary credentials, the way an instance would get them
awsl sts assume-role --role-arn "arn:aws:iam::000000000000:role/bookshelf-ec2-role" \
  --role-session-name demo --query 'Credentials.[AccessKeyId,Expiration]'
