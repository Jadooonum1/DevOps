#!/usr/bin/env bash
# S3 hands-on against LocalStack.
set -euo pipefail
source ../localstack.env
B=bookshelf-covers
WORK=$(mktemp -d)

awsl s3api create-bucket --bucket "$B" > /dev/null
awsl s3api put-public-access-block --bucket "$B" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# --- versioning + default encryption -----------------------------------------
awsl s3api put-bucket-versioning --bucket "$B" --versioning-configuration Status=Enabled
awsl s3api put-bucket-encryption --bucket "$B" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
awsl s3api get-bucket-versioning --bucket "$B"
awsl s3api get-bucket-encryption --bucket "$B" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'

# two versions of the same object
echo "Clean Code - first edition blurb"  > "$WORK/blurb.txt"
awsl s3 cp --only-show-errors "$WORK/blurb.txt" "s3://$B/blurbs/9780132350884.txt"
echo "Clean Code - corrected blurb"      > "$WORK/blurb.txt"
awsl s3 cp --only-show-errors "$WORK/blurb.txt" "s3://$B/blurbs/9780132350884.txt"
awsl s3api list-object-versions --bucket "$B" --prefix blurbs/ \
  --query 'Versions[].[VersionId,IsLatest,Size]' --output table

# an infrequently-read object straight into a cheaper storage class
echo "scanned page" > "$WORK/page-001.txt"
awsl s3 cp --only-show-errors "$WORK/page-001.txt" "s3://$B/scans/page-001.txt" --storage-class STANDARD_IA
awsl s3api head-object --bucket "$B" --key scans/page-001.txt --query '[StorageClass,ServerSideEncryption]'

# --- lifecycle + bucket policy -------------------------------------------------
awsl s3api put-bucket-lifecycle-configuration --bucket "$B" --lifecycle-configuration file://policies/lifecycle.json
awsl s3api get-bucket-lifecycle-configuration --bucket "$B" --query 'Rules[].ID'
awsl s3api put-bucket-policy --bucket "$B" --policy file://policies/require-tls.json
awsl s3api get-bucket-policy --bucket "$B" --query Policy --output text | python3 -m json.tool | head -8

# --- restore the previous version by copying it over the latest ----------------
OLD=$(awsl s3api list-object-versions --bucket "$B" --prefix blurbs/ \
  --query 'Versions[?IsLatest==`false`].VersionId | [0]' --output text)
awsl s3api copy-object --bucket "$B" --key blurbs/9780132350884.txt \
  --copy-source "$B/blurbs/9780132350884.txt?versionId=$OLD" > /dev/null
awsl s3 cp "s3://$B/blurbs/9780132350884.txt" -      # prints the first-edition text again

# --- a delete only adds a delete marker when versioning is on ------------------
awsl s3 rm "s3://$B/scans/page-001.txt"
awsl s3api list-object-versions --bucket "$B" --prefix scans/ \
  --query '{versions: length(Versions), deleteMarkers: length(DeleteMarkers)}'
rm -rf "$WORK"
