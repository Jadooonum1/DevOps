#!/usr/bin/env bash
# Boot-test the user_data that Terraform actually attached to the instance.
# LocalStack's EC2 never boots a VM, so we play cloud-init ourselves: fetch the rendered script
# from the (emulated) EC2 API and run it as root in an Amazon Linux 2023 container that can
# reach LocalStack's S3. systemctl is stubbed because containers have no systemd.
#
# usage: bash scripts/boot-test.sh            (after terraform apply, LocalStack on :4566)
#        SERVE_PORT=8088 bash scripts/boot-test.sh   keeps the container running and publishes nginx on
#        http://localhost:8088/ so the page can be opened in a browser; stop it with
#        docker rm -f lib-reader-web-boot
set -euo pipefail
cd "$(dirname "$0")/../terraform-project"

export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
EP="${LOCALSTACK_URL:-http://localhost:4566}"

IID=$(terraform output -json web_servers >/dev/null && \
      aws --endpoint-url "$EP" ec2 describe-instances \
        --filters "Name=tag:Name,Values=reader-web-dev-1" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId' --output text)
echo "instance: $IID"

WORK=$(mktemp -d "${PWD}/.boot-test.XXXX")   # inside the project so Docker Desktop can mount it
trap 'rm -rf "$WORK"' EXIT
aws --endpoint-url "$EP" ec2 describe-instance-attribute --instance-id "$IID" --attribute userData \
  --query 'UserData.Value' --output text | base64 --decode > "$WORK/user-data.sh"
bash -n "$WORK/user-data.sh" && echo "user_data: bash syntax OK"

cat > "$WORK/prepare.sh" <<'PREP'
set -e
# cloud-init stand-ins: point the AWS CLI at LocalStack and fake systemctl
mkdir -p /root/.aws
printf '[default]\ns3 =\n    addressing_style = path\n' > /root/.aws/config
cat > /usr/local/bin/systemctl <<'STUB'
#!/bin/bash
[ "$*" = "enable --now nginx" ] && exec nginx
echo "systemctl stub: ignoring '$*'"
STUB
chmod +x /usr/local/bin/systemctl
bash /work/user-data.sh
echo "--- served page ---"
curl -fsS http://localhost/ | grep -E "<h1>|Served by"
PREP

RUN_ARGS=(--add-host host.docker.internal:host-gateway
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_DEFAULT_REGION
  -e AWS_ENDPOINT_URL=http://host.docker.internal:4566)

if [ -z "${SERVE_PORT:-}" ]; then
  docker run --rm "${RUN_ARGS[@]}" -v "$WORK:/work:ro" amazonlinux:2023 bash /work/prepare.sh
else
  # copy the scripts into the container (the temp dir is deleted when this script exits)
  docker create --name lib-reader-web-boot -p "$SERVE_PORT:80" "${RUN_ARGS[@]}" amazonlinux:2023 \
    bash -c 'bash /work/prepare.sh && exec sleep infinity' > /dev/null
  docker cp "$WORK/." lib-reader-web-boot:/work
  docker start lib-reader-web-boot > /dev/null
  for _ in $(seq 1 120); do
    curl -fsS "http://localhost:$SERVE_PORT/" > /dev/null 2>&1 && break
    sleep 2
  done
  docker logs lib-reader-web-boot 2>&1 | tail -4
  curl -fsS -o /dev/null -w "http://localhost:$SERVE_PORT/ -> HTTP %{http_code}\n" "http://localhost:$SERVE_PORT/"
fi
