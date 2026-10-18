#!/usr/bin/env bash
set -uo pipefail
source ../localstack.env
POLICY_ARN="arn:aws:iam::000000000000:policy/catalog-covers-read-only"
awsl iam remove-role-from-instance-profile --instance-profile-name bookshelf-ec2-profile --role-name bookshelf-ec2-role
awsl iam delete-instance-profile --instance-profile-name bookshelf-ec2-profile
awsl iam detach-role-policy --role-name bookshelf-ec2-role --policy-arn "$POLICY_ARN"
awsl iam delete-role --role-name bookshelf-ec2-role
for u in asha-librarian ravi-cataloguer; do
  awsl iam remove-user-from-group --group-name library-staff --user-name "$u"
  awsl iam delete-user --user-name "$u"
done
awsl iam delete-group-policy --group-name library-staff --policy-name deny-delete-catalog
awsl iam detach-group-policy --group-name library-staff --policy-arn "$POLICY_ARN"
awsl iam delete-group --group-name library-staff
awsl iam delete-policy --policy-arn "$POLICY_ARN"
echo "IAM demo resources removed"
