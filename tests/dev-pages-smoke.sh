#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
command -v curl >/dev/null
command -v jq >/dev/null
port="${1:-18082}"
base="http://127.0.0.1:$port"
work="$(mktemp -d)"
server_pid=""
slow_pid=""
mkdir "$work/pages"

cleanup() {
  for pid in "$slow_pid" "$server_pid"; do
    if [[ -n "$pid" ]]; then
      if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fi
      wait "$pid" 2>/dev/null || true
    fi
  done
  rm -f "$work/pages/index.lean" "$work/pages/hello.lean" \
    "$work/pages/slow.lean" "$work/pages/outside.lean" \
    "$work/pages/blog/index.lean" "$work/pages/blog/new.lean" \
    "$work/server.log" "$work/body" \
    "$work/headers" "$work/slow-body" "$work/started" "$work/outside.lean"
  rm -f "$work/template-response"
  rmdir "$work/pages/blog" "$work/pages" "$work"
}
trap cleanup EXIT

mkdir "$work/pages/blog"

printf '%s' '{"requestId":1,"path":"<script>alert(1)</script>","usersHtml":"<ul></ul>"}' |
  lake env lean --run Pages/templates/lean-html.lean >"$work/template-response"
jq -e 'contains("&lt;script&gt;alert(1)&lt;/script&gt;") and
  contains("lean-html テンプレートサンプル")' "$work/template-response" >/dev/null

fail() {
  echo "FAIL: $*" >&2
  cat "$work/server.log" >&2
  exit 1
}

write_page() {
  local file="$1" label="$2"
  cat >"$file" <<EOF
import LeanWebStudy.Page
def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (s!"<p>$label {context.requestId} {context.path}</p>" ++ context.usersHtml)
EOF
}

check_status() {
  local expected="$1" path="$2" actual
  actual="$(curl --path-as-is -sS --max-time 30 -D "$work/headers" \
    -o "$work/body" -w '%{http_code}' "$base$path")"
  [[ "$actual" == "$expected" ]] || fail "Expected HTTP $expected for $path, got $actual"
  kill -0 "$server_pid" 2>/dev/null || fail "Server exited"
}

write_page "$work/pages/index.lean" "original"
.lake/build/bin/leanwebstudy "$port" --dev "$work/pages" >"$work/server.log" 2>&1 &
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

check_status 200 "/"
grep -q 'original 1 /' "$work/body" || fail "Initial page or context"
grep -q '<li>1: Alice</li>' "$work/body" || fail "Shared database context"
grep -qi '^cache-control: no-store' "$work/headers" || fail "Page cache policy"
grep -qi '^content-type: text/html' "$work/headers" || fail "Page content type"
write_page "$work/pages/index.lean" "edited"
check_status 200 "/?ignored=value"
grep -q 'edited 2 /' "$work/body" || fail "Edited source not reloaded"
check_status 404 "/hello"
write_page "$work/pages/hello.lean" "added"
check_status 200 "/hello"
grep -q 'added 3 /hello' "$work/body" || fail "New page not discovered"
write_page "$work/pages/blog/new.lean" "nested"
check_status 200 "/blog/new"
grep -q 'nested 4 /blog/new' "$work/body" || fail "Nested page"
rm "$work/pages/hello.lean"
check_status 404 "/hello"

printf 'this is not valid Lean\n' >"$work/pages/index.lean"
check_status 500 "/"
grep -q '^Page request failed$' "$work/body" || fail "Generic compile error"
grep -q 'Page worker failed' "$work/server.log" || fail "Missing compiler diagnostics"
cat >"$work/pages/index.lean" <<'EOF'
import LeanWebStudy.Page
def main : IO Unit :=
  LeanWebStudy.Page.run fun _ => throw (IO.userError "intentional render failure")
EOF
check_status 500 "/"
grep -q 'intentional render failure' "$work/server.log" || fail "Missing runtime diagnostics"
cat >"$work/pages/index.lean" <<'EOF'
import LeanWebStudy.Page
def main : IO Unit := IO.println "not a JSON response"
EOF
check_status 500 "/"
grep -q 'Invalid page worker response' "$work/server.log" || fail "Protocol error not logged"
write_page "$work/pages/index.lean" "recovered"
check_status 200 "/"
grep -q 'recovered 8 /' "$work/body" || fail "Recovery or counter persistence"
check_status 200 "/api/query"
jq -e '.requestId == 9 and .rows == []' "$work/body" >/dev/null || fail "API state"
write_page "$work/pages/blog/index.lean" "folder index"
check_status 200 "/blog/"
grep -q 'folder index 10 /blog/' "$work/body" || fail "Trailing-slash directory index"
check_status 200 "/blog"
grep -q 'folder index 11 /blog' "$work/body" || fail "Directory index fallback"
status="$(curl -sS --max-time 5 -X POST -D "$work/headers" \
  -o "$work/body" -w '%{http_code}' "$base/")"
[[ "$status" == 405 ]] || fail "Non-GET request"
grep -qi '^allow: GET' "$work/headers" || fail "405 Allow header"
check_status 404 "/../outside"
check_status 404 "/%2e%2e/outside"
check_status 404 "//index"
write_page "$work/outside.lean" "outside"
ln -s "$work/outside.lean" "$work/pages/outside.lean"
check_status 500 "/outside"
grep -q 'Page resolves outside page directory' "$work/server.log" ||
  fail "Symlink escape not rejected"

cat >"$work/pages/slow.lean" <<EOF
import LeanWebStudy.Page
def main : IO Unit :=
  LeanWebStudy.Page.run fun _ => do
    IO.FS.writeFile "$work/started" ""
    IO.sleep 1500
    pure "<p>slow page complete</p>"
EOF
curl -fsS --max-time 30 "$base/slow" >"$work/slow-body" &
slow_pid=$!
started=false
for _ in $(seq 1 200); do
  if [[ -f "$work/started" ]]; then
    started=true
    break
  fi
  kill -0 "$slow_pid" 2>/dev/null || fail "Slow page exited before execution"
  sleep 0.05
done
[[ "$started" == true ]] || fail "Slow page did not start"
curl -fsS --max-time 1 "$base/health" >"$work/body" ||
  fail "Page worker blocked health checks"
jq -e '.status == "ok"' "$work/body" >/dev/null || fail "Health response"
wait "$slow_pid" || fail "Slow page failed"
slow_pid=""
grep -q 'slow page complete' "$work/slow-body" || fail "Slow page response"
rm "$work/pages/index.lean"
check_status 404 "/"
if .lake/build/bin/leanwebstudy "$port" --dev "$work/body" >"$work/body" 2>&1; then
  fail "Non-directory page root accepted"
fi
grep -q 'Page directory is not a directory' "$work/body" || fail "Page root error"

echo "PASS: page edit/add/delete, nested routes, worker errors/recovery, shared state, path confinement, responsive health"
