#!/usr/bin/env bash
# DynamoDB hands-on against LocalStack (RDS is a LocalStack Pro feature - see README).
set -euo pipefail
source ../localstack.env
T=library-loans

# partition key = member, sort key = loan date#isbn  -> "all loans of a member, newest first" is one Query
awsl dynamodb create-table --table-name "$T" \
  --attribute-definitions AttributeName=member_id,AttributeType=S AttributeName=loan_key,AttributeType=S \
                          AttributeName=isbn,AttributeType=S \
  --key-schema AttributeName=member_id,KeyType=HASH AttributeName=loan_key,KeyType=RANGE \
  --global-secondary-indexes '[{"IndexName":"by-isbn","KeySchema":[{"AttributeName":"isbn","KeyType":"HASH"}],"Projection":{"ProjectionType":"ALL"}}]' \
  --billing-mode PAY_PER_REQUEST > /dev/null
awsl dynamodb wait table-exists --table-name "$T"
awsl dynamodb describe-table --table-name "$T" --query 'Table.[TableStatus,KeySchema[].AttributeName,BillingModeSummary.BillingMode]'

put() { awsl dynamodb put-item --table-name "$T" --item "$1"; }
put '{"member_id":{"S":"M00042"},"loan_key":{"S":"2025-02-01#9780132350884"},"isbn":{"S":"9780132350884"},"title":{"S":"Clean Code"},"returned":{"BOOL":true}}'
put '{"member_id":{"S":"M00042"},"loan_key":{"S":"2025-03-10#9781491950357"},"isbn":{"S":"9781491950357"},"title":{"S":"Building Microservices"},"returned":{"BOOL":false}}'
put '{"member_id":{"S":"M00077"},"loan_key":{"S":"2025-03-12#9780132350884"},"isbn":{"S":"9780132350884"},"title":{"S":"Clean Code"},"returned":{"BOOL":false}}'

echo "-- Query: M00042's loans, newest first"
awsl dynamodb query --table-name "$T" --key-condition-expression "member_id = :m" \
  --expression-attribute-values '{":m":{"S":"M00042"}}' --no-scan-index-forward \
  --query 'Items[].[loan_key.S,title.S,returned.BOOL]' --output table

echo "-- Query on the GSI: who has borrowed Clean Code?"
awsl dynamodb query --table-name "$T" --index-name by-isbn --key-condition-expression "isbn = :i" \
  --expression-attribute-values '{":i":{"S":"9780132350884"}}' --query 'Items[].member_id.S'

echo "-- conditional update: return a book only if it is still out"
awsl dynamodb update-item --table-name "$T" \
  --key '{"member_id":{"S":"M00077"},"loan_key":{"S":"2025-03-12#9780132350884"}}' \
  --update-expression "SET returned = :t" --condition-expression "returned = :f" \
  --expression-attribute-values '{":t":{"BOOL":true},":f":{"BOOL":false}}' \
  --return-values UPDATED_NEW --query Attributes
# running the same update again fails with ConditionalCheckFailedException
awsl dynamodb update-item --table-name "$T" \
  --key '{"member_id":{"S":"M00077"},"loan_key":{"S":"2025-03-12#9780132350884"}}' \
  --update-expression "SET returned = :t" --condition-expression "returned = :f" \
  --expression-attribute-values '{":t":{"BOOL":true},":f":{"BOOL":false}}' 2>&1 | grep -o ConditionalCheckFailedException || true

echo "-- Scan with a filter (reads the whole table: fine here, expensive at scale)"
awsl dynamodb scan --table-name "$T" --filter-expression "returned = :f" \
  --expression-attribute-values '{":f":{"BOOL":false}}' --query '[Count,ScannedCount]'

awsl dynamodb delete-table --table-name "$T" --query TableDescription.TableName
