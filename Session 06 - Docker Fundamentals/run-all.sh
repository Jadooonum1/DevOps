#!/usr/bin/env bash
# Build and start all six hello-world containers, then curl each one.
set -euo pipefail
cd "$(dirname "$0")"

# folder:image:host-port:container-port
apps=(
  "node-hello:lib-node-hello:18101:3000"
  "python-hello:lib-python-hello:18102:5000"
  "java-hello:lib-java-hello:18103:8080"
  "apache-hello:lib-apache-hello:18104:80"
  "react-hello:lib-react-hello:18105:80"
  "nginx-hello:lib-nginx-hello:18106:80"
)

for entry in "${apps[@]}"; do
  IFS=: read -r dir image host_port container_port <<<"$entry"
  echo "==> building $image from ./$dir"
  docker build -q -t "$image" "./$dir"
  docker rm -f "$image" >/dev/null 2>&1 || true
  docker run -d --name "$image" -p "$host_port:$container_port" "$image" >/dev/null
done

echo "==> waiting for the JVM and Flask to come up"
sleep 4

for entry in "${apps[@]}"; do
  IFS=: read -r dir image host_port _ <<<"$entry"
  printf '%-18s http://localhost:%s  ' "$image" "$host_port"
  curl -fsS "http://localhost:$host_port/" | grep -oE '<h1>[^<]*</h1>|<title>[^<]*</title>' | head -1 || echo "FAILED"
done

docker ps --filter "name=^lib-.*-hello$" --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
