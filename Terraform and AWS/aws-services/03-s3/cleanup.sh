#!/usr/bin/env bash
# A versioned bucket can only be deleted once every version and delete marker is gone.
set -euo pipefail
source ../localstack.env
B=bookshelf-covers
python3 - "$B" <<'PY' | while read -r key vid; do awsl s3api delete-object --bucket "$B" --key "$key" --version-id "$vid" > /dev/null; done
import json, os, subprocess, sys
out = subprocess.check_output(["aws", "--endpoint-url", os.environ["LOCALSTACK_URL"], "s3api",
                               "list-object-versions", "--bucket", sys.argv[1], "--output", "json"])
data = json.loads(out or "{}")
for item in data.get("Versions", []) + data.get("DeleteMarkers", []):
    print(item["Key"], item["VersionId"])
PY
awsl s3api delete-bucket --bucket "$B"
echo "bucket $B removed"
