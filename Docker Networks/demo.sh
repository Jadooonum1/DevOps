#!/usr/bin/env bash
# Walk-through of user-defined bridges, host networking and bind mounts.
# Every object created is prefixed with lib- so cleanup.sh can remove it.
set -uo pipefail
cd "$(dirname "$0")"
step() { printf '\n### %s\n' "$*"; }

step "1. Create three user-defined bridge networks"
docker network create lib-frontend-net
docker network create lib-backend-net
docker network create --internal lib-data-net   # --internal: no route to the outside world

step "2. Start one container per tier"
docker run -d --name lib-reader-web   --network lib-frontend-net nginx:1.27-alpine
docker run -d --name lib-loan-service --network lib-backend-net  nginx:1.27-alpine
docker run -d --name lib-catalog-db   --network lib-data-net \
  -e POSTGRES_PASSWORD=example-only postgres:17-alpine

step "3. Attach loan-service to the other two networks (multi-homed container)"
docker network connect lib-frontend-net lib-loan-service
docker network connect lib-data-net     lib-loan-service
docker inspect lib-loan-service \
  --format '{{range $n, $c := .NetworkSettings.Networks}}{{$n}}={{$c.IPAddress}} {{end}}'

sleep 3   # give postgres a moment to open 5432

step "4. Reachability tests (DNS by container name on user-defined bridges)"
echo -n "loan-service -> reader-web:80   : "; docker exec lib-loan-service wget -qO- -T 3 http://lib-reader-web | grep -o '<title>.*</title>'
echo -n "loan-service -> catalog-db:5432 : "; docker exec lib-loan-service nc -z -w 3 lib-catalog-db 5432 && echo reachable
echo -n "reader-web   -> loan-service:80 : "; docker exec lib-reader-web wget -qO- -T 3 http://lib-loan-service | grep -o '<title>.*</title>'
echo -n "reader-web   -> catalog-db:5432 : "; docker exec lib-reader-web nc -z -w 3 lib-catalog-db 5432 2>&1 && echo reachable || echo "blocked (expected)"
echo -n "catalog-db   -> internet        : "; docker exec lib-catalog-db wget -qO- -T 3 http://example.com >/dev/null 2>&1 && echo reachable || echo "blocked by --internal (expected)"

step "5. Default bridge has no container-name DNS"
docker run -d --name lib-default-a nginx:1.27-alpine >/dev/null
echo -n "default bridge, lookup lib-default-a : "
docker run --rm busybox:1.36 wget -qO- -T 3 http://lib-default-a 2>&1 | head -1

step "6. Host network (no NAT, no -p)"
docker run -d --name lib-host-loan --network host \
  -v "$PWD/host-net/default.conf:/etc/nginx/conf.d/default.conf:ro" nginx:1.27-alpine
sleep 1
docker inspect lib-host-loan --format 'NetworkMode={{.HostConfig.NetworkMode}} Ports={{.NetworkSettings.Ports}}'
echo -n "another host-network container -> 127.0.0.1:18301 : "
docker run --rm --network host busybox:1.36 wget -qO- -T 3 http://127.0.0.1:18301

step "7. Bind mount: edit a host file, container serves the new version"
cp site/index.html site/index.html.bak
docker run -d --name lib-notice-board -p 18302:80 \
  -v "$PWD/site:/usr/share/nginx/html:ro" nginx:1.27-alpine
sleep 1
curl -s http://localhost:18302 | grep -o '<p id="notice">.*</p>'
sed -i.tmp 's/Notice v1: the reading room opens at 9am./Notice v2: the reading room now opens at 8am./' site/index.html && rm -f site/index.html.tmp
sleep 1   # Docker Desktop file sharing can take a moment to propagate the change
curl -s http://localhost:18302 | grep -o '<p id="notice">.*</p>'
docker inspect lib-notice-board --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}} rw={{.RW}}{{end}}'
mv site/index.html.bak site/index.html   # restore v1 for the next run

step "8. Named volume survives container removal"
docker volume create lib-shelf-data >/dev/null
docker run --rm -v lib-shelf-data:/data busybox:1.36 sh -c 'echo "Dune,Frank Herbert" > /data/books.csv'
docker run --rm -v lib-shelf-data:/data busybox:1.36 cat /data/books.csv
