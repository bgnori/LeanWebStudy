#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
command -v curl >/dev/null
command -v jq >/dev/null
port="${1:-18080}"
base="http://127.0.0.1:$port"
work="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]]; then
    if kill -0 "$server_pid" 2>/dev/null; then
      kill "$server_pid"
    fi
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -f "$work/server.log" "$work/body" "$work/headers" "$work/parallel.json"
  rmdir "$work"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  cat "$work/server.log" >&2
  exit 1
}

.lake/build/bin/leanwebstudy "$port" >"$work/server.log" 2>&1 &
server_pid=$!
ready=false
for _ in $(seq 1 100); do
  kill -0 "$server_pid" 2>/dev/null || fail "Server exited before readiness"
  if curl -fsS --max-time 1 "$base/health" >"$work/body" 2>/dev/null; then
    ready=true
    break
  fi
  sleep 0.05
done
[[ "$ready" == true ]] || fail "Server did not become ready"
kill -0 "$server_pid" 2>/dev/null || fail "Server exited during readiness"
jq -e '.status == "ok"' "$work/body" >/dev/null || fail "Health response"

check_status() {
  local expected="$1"
  shift
  local actual
  actual="$(curl -sS --max-time 5 -D "$work/headers" -o "$work/body" \
    -w '%{http_code}' "$@")"
  [[ "$actual" == "$expected" ]] || fail "Expected HTTP $expected, got $actual"
}

check_status 200 "$base/"
grep -qi '^content-type: text/html' "$work/headers" || fail "HTML content type"
grep -qi '^cache-control: no-store' "$work/headers" || fail "Dynamic cache policy"
grep -q 'Dynamic page request: 1' "$work/body" || fail "First dynamic page"
grep -q 'Users from SQLite (:memory:)' "$work/body" || fail "SQLite-backed page"
for user in '1: Alice' '2: Bob' '3: Carol' '4: Dave'; do
  grep -q "<li>$user</li>" "$work/body" || fail "Missing database user: $user"
done
check_status 200 "$base/?ignored=value"
grep -q 'Dynamic page request: 2' "$work/body" || fail "Page did not change"

check_status 200 "$base/api/query"
grep -qi '^content-type: application/json' "$work/headers" || fail "JSON content type"
jq -e '.requestId == 3 and .sql == "SELECT * FROM \"users\" WHERE \"id\" > ?" and
  .params == [3] and .rows == [[4, "Dave"]]' "$work/body" >/dev/null ||
  fail "SQL, bound parameters, or database result"

check_status 404 "$base/missing"
check_status 405 -X POST "$base/"
grep -qi '^allow: GET' "$work/headers" || fail "405 Allow header"

seq 1 32 | xargs -P 8 -I '{}' curl -fsS --max-time 5 "$base/api/query" \
  >"$work/parallel.json"
jq -se 'length == 32 and
  ([.[].requestId] | sort) == [range(4; 36)] and
  all(.[]; .params == [.requestId] and .sql == "SELECT * FROM \"users\" WHERE \"id\" > ?" and
    .rows == [])' \
  "$work/parallel.json" >/dev/null || fail "Concurrent request IDs or SQL parameters"

if .lake/build/bin/leanwebstudy 65536 >"$work/body" 2>&1; then
  fail "Out-of-range port was accepted"
fi
grep -q 'Port must be between 1 and 65535' "$work/body" || fail "Port error message"

echo "PASS: SQLite-backed HTML and SQL JSON, health, 404/405, 32 concurrent queries, port validation"
