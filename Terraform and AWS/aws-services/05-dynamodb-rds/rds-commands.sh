#!/usr/bin/env bash
# RDS commands for reference. On LocalStack these need the Pro image (LOCALSTACK_AUTH_TOKEN);
# on real AWS they create billable resources - delete them afterwards.
set -euo pipefail
source ../localstack.env
: "${PRIVATE_SUBNET_A:?export PRIVATE_SUBNET_A and PRIVATE_SUBNET_B (two private subnets in different AZs)}"
: "${PRIVATE_SUBNET_B:?}"

awsl rds create-db-subnet-group --db-subnet-group-name library-db-subnets \
  --db-subnet-group-description "private subnets for the catalogue DB" \
  --subnet-ids "$PRIVATE_SUBNET_A" "$PRIVATE_SUBNET_B"

# --manage-master-user-password stores the password in Secrets Manager instead of on the command line
awsl rds create-db-instance --db-instance-identifier library-catalog-db \
  --engine postgres --engine-version 16 --db-instance-class db.t4g.micro \
  --allocated-storage 20 --storage-encrypted \
  --master-username librarian --manage-master-user-password \
  --db-subnet-group-name library-db-subnets --no-publicly-accessible \
  --backup-retention-period 7

awsl rds wait db-instance-available --db-instance-identifier library-catalog-db
awsl rds describe-db-instances --db-instance-identifier library-catalog-db \
  --query 'DBInstances[0].[DBInstanceStatus,Endpoint.Address,Endpoint.Port,MultiAZ]'

# cleanup
awsl rds delete-db-instance --db-instance-identifier library-catalog-db --skip-final-snapshot
awsl rds wait db-instance-deleted --db-instance-identifier library-catalog-db
awsl rds delete-db-subnet-group --db-subnet-group-name library-db-subnets
