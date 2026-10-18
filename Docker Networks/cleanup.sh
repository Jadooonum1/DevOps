#!/usr/bin/env bash
set -uo pipefail
docker rm -f lib-reader-web lib-loan-service lib-catalog-db lib-default-a lib-host-loan lib-notice-board 2>/dev/null
docker network rm lib-frontend-net lib-backend-net lib-data-net 2>/dev/null
docker volume rm lib-shelf-data 2>/dev/null
echo "cleanup done"
