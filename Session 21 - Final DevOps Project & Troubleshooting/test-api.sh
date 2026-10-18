#!/usr/bin/env bash
# Smoke-test the bookshelf API through the nginx frontend.
# Usage: ./test-api.sh [base-url]   (default http://localhost:18080)
set -euo pipefail
BASE="${1:-http://localhost:18080}"
pass=0; fail=0

check() {  # check <description> <expected-status> <method> <path> [json-body]
  local desc=$1 want=$2 method=$3 path=$4 body=${5:-}
  local args=(-s -o /tmp/lib-api-body -w '%{http_code}' -X "$method" "$BASE$path")
  [[ -n $body ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  local got; got=$(curl "${args[@]}")
  if [[ $got == "$want" ]]; then
    pass=$((pass + 1)); printf 'PASS %-38s %s\n' "$desc" "$got"
  else
    fail=$((fail + 1)); printf 'FAIL %-38s want %s got %s: %s\n' "$desc" "$want" "$got" "$(cat /tmp/lib-api-body)"
  fi
}

check "frontend serves index.html"        200 GET  /
check "health reports database up"         200 GET  /api/health
check "add a book"                         201 POST /api/books '{"title":"The Left Hand of Darkness","author":"Ursula K. Le Guin"}'
id=$(sed -E 's/.*"id":([0-9]+).*/\1/' /tmp/lib-api-body)
echo "     created book id=$id"
check "list books"                         200 GET  /api/books
grep -q "Left Hand of Darkness" /tmp/lib-api-body && echo "     new book present in list"
check "borrow the book"                    200 POST "/api/books/$id/borrow"
check "borrow again is a conflict"         409 POST "/api/books/$id/borrow"
check "return the book"                    200 POST "/api/books/$id/return"
check "reject empty title"                 422 POST /api/books '{"title":"","author":"x"}'
check "delete the book"                    204 DELETE "/api/books/$id"
check "deleted book is gone"               404 POST "/api/books/$id/borrow"

rm -f /tmp/lib-api-body
echo "passed=$pass failed=$fail"
[[ $fail -eq 0 ]]
