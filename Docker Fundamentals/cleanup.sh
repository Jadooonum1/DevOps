#!/usr/bin/env bash
# Remove every container and image created by run-all.sh.
set -uo pipefail
names="lib-node-hello lib-python-hello lib-java-hello lib-apache-hello lib-react-hello lib-nginx-hello"
docker rm -f $names 2>/dev/null
docker rmi $names 2>/dev/null
echo "cleanup done"
