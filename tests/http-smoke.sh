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

check_content_type() {
  local expected="$1" count
  count="$(grep -ic '^content-type:' "$work/headers" || true)"
  [[ "$count" == 1 ]] || fail "Expected exactly one Content-Type header, got $count"
  tr -d '\r' <"$work/headers" | grep -Fxi "content-type: $expected" >/dev/null ||
    fail "Expected Content-Type: $expected"
}

check_status() {
  local expected="$1"
  shift
  local actual
  actual="$(curl -sS --max-time 30 -D "$work/headers" -o "$work/body" \
    -w '%{http_code}' "$@")"
  [[ "$actual" == "$expected" ]] || fail "Expected HTTP $expected, got $actual"
  if [[ "$expected" != 200 ]]; then
    check_content_type 'text/plain; charset=utf-8'
  elif [[ "$*" == *"$base/api/query"* || "$*" == *"$base/api/cat/current"* ||
      "$*" == *"$base/health"* ]]; then
    check_content_type 'application/json; charset=utf-8'
  else
    check_content_type 'text/html; charset=utf-8'
  fi
}

check_status 200 "$base/health"

check_status 200 "$base/"
grep -qi '^cache-control: no-store' "$work/headers" || fail "Dynamic cache policy"
grep -q 'href="/sqlite/">MapleSQLで操作するSQLite' "$work/body" ||
  fail "Combined MapleSQL and SQLite feature index link"
if grep -q 'href="/maplesql/"' "$work/body"; then
  fail "MapleSQL should not have a separate feature page"
fi
grep -q 'href="/templates/"' "$work/body" || fail "Template feature index link"
grep -q 'href="/chat-ws/"' "$work/body" || fail "ws-lean chat comparison link"
grep -q 'href="/cat/">IRT / Computerized Adaptive Testing デモ' "$work/body" ||
  fail "IRT CAT feature index link"
grep -q 'href="/board/">掲示板 Webアプリ' "$work/body" || fail "Bulletin board feature index link"
if grep -q 'SQLiteのユーザー一覧' "$work/body"; then
  fail "Root page should be the feature index, not the SQLite example"
fi
check_status 200 "$base/?ignored=value"
grep -q 'LeanWebStudy' "$work/body" || fail "Root index did not reload"
check_status 200 "$base/sqlite/"
grep -q 'MapleSQLで操作するSQLite' "$work/body" || fail "Combined feature page title"
grep -q 'MapleSQLでSQL文とパラメーターを生成' "$work/body" ||
  fail "MapleSQL and SQLite integration explanation"
grep -q '<li>1: Leanne Graham <span>(user-1@example.invalid)</span></li>' "$work/body" ||
  fail "SQLite users on combined page"
check_demo() {
  grep -q '元データのスキーマ' "$work/body" || fail "Source schema"
  grep -q 'geo: { lat: string, lng: string }' "$work/body" || fail "Nested source field types"
  grep -q 'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE)' "$work/body" ||
    fail "SQLite schema"
  grep -q 'MIT License' "$work/body" || fail "Dataset license"
  grep -q '7ae4432ac3f60e7226a899c25e04826207d07098/data.json' "$work/body" ||
    fail "Pinned dataset source"
  grep -q 'MapleSQL.Statement.select' "$work/body" || fail "Actual MapleSQL statement"
  grep -q 'SELECT \* FROM &quot;users&quot; WHERE &quot;id&quot; &gt; ?' "$work/body" ||
    fail "Actual generated SQL"
  grep -q '<pre><code>\[3\]</code></pre>' "$work/body" || fail "Bound parameters"
  grep -q '\[4,&quot;Patricia Lebsack&quot;,&quot;user-4@example.invalid&quot;\]' "$work/body" ||
    fail "Executed result"
  grep -q 'SELECT &quot;email&quot; FROM &quot;users&quot; WHERE &quot;name&quot; = ?' "$work/body" ||
    fail "Email-only SELECT with bound name"
  grep -q '<pre><code>\[&quot;Leanne Graham&quot;\]</code></pre>' "$work/body" ||
    fail "Bound duplicate name"
  grep -q '<pre><code>\[\[&quot;user-1@example.invalid&quot;\],\[&quot;user-2@example.invalid&quot;\]\]</code></pre>' \
    "$work/body" || fail "Exactly two email-only result rows"
}
check_demo
grep -q 'href="/api/query"' "$work/body" || fail "Parameterized query API link"
check_status 200 "$base/sqlite/users"
grep -q '1: Leanne Graham' "$work/body" || fail "SQLite users example"
for user in '1: Leanne Graham' '2: Leanne Graham' '3: Clementine Bauch' \
  '4: Patricia Lebsack' '5: Chelsey Dietrich' '6: Mrs. Dennis Schulist' \
  '7: Kurtis Weissnat' '8: Nicholas Runolfsdottir V' '9: Glenna Reichert' \
  '10: Clementina DuBuque'; do
  id="${user%%:*}"
  grep -q "<li>$user <span>(user-$id@example.invalid)</span></li>" "$work/body" ||
    fail "Missing database user or generated email: $user"
done
check_demo
check_status 200 "$base/templates/"
grep -q 'HTMLテンプレート' "$work/body" || fail "Template feature index"
check_status 404 "$base/maplesql/"
check_status 404 "$base/maplesql/parameterized-query"

check_status 200 "$base/api/query"
jq -e '.requestId == 6 and .sql == "SELECT * FROM \"users\" WHERE \"id\" > ?" and
  .params == [6] and .rows == [[7,"Kurtis Weissnat","user-7@example.invalid"],
    [8,"Nicholas Runolfsdottir V","user-8@example.invalid"],
    [9,"Glenna Reichert","user-9@example.invalid"],
    [10,"Clementina DuBuque","user-10@example.invalid"]]' "$work/body" >/dev/null ||
  fail "SQL, bound parameters, or database result"

check_status 200 "$base/cat/"
grep -q '3パラメータ・ロジスティックモデル' "$work/body" || fail "CAT page model explanation"
check_status 200 "$base/api/cat/current"
jq -e '.items | length == 30' "$work/body" >/dev/null || fail "CAT SQLite item pool"
jq -e '.responses | length == 0' "$work/body" >/dev/null || fail "CAT initial response history"
cat_seen='[]'
for attempt in $(seq 1 10); do
  cat_item="$(jq -r '.nextItem.id' "$work/body")"
  [[ "$cat_item" != "null" ]] || fail "CAT ended before ten questions"
  cat_seen="$(jq -cn --argjson seen "$cat_seen" --argjson item "$cat_item" '$seen + [$item]')"
  correct="$((attempt % 2))"
  actual="$(curl -sS --max-time 10 -H "Origin: $base" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data "itemId=$cat_item&correct=$correct" -o "$work/body" -w '%{http_code}' \
    "$base/api/cat/answer")"
  [[ "$actual" == 200 ]] || fail "CAT answer $attempt returned HTTP $actual"
  jq -e --argjson count "$attempt" '.responses | length == $count' "$work/body" >/dev/null ||
    fail "CAT response history after question $attempt"
done
jq -e 'length == 10 and (unique | length) == 10' <<<"$cat_seen" >/dev/null ||
  fail "CAT must select ten unique items"
jq -e '.finished and .nextItem == null and (.responses | length == 10)' "$work/body" >/dev/null ||
  fail "CAT completion after ten answers"
actual="$(curl -sS --max-time 10 -H "Origin: $base" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'itemId=1&correct=1' -o "$work/body" -w '%{http_code}' \
  "$base/api/cat/answer")"
[[ "$actual" == 409 ]] || fail "Completed CAT run must reject more answers"
actual="$(curl -sS --max-time 10 -H "Origin: $base" -X POST \
  -o "$work/body" -w '%{http_code}' "$base/api/cat/reset")"
[[ "$actual" == 200 ]] || fail "CAT reset returned HTTP $actual"
jq -e '.responses | length == 0' "$work/body" >/dev/null || fail "CAT reset did not clear history"
actual="$(curl -sS --max-time 10 -H 'Origin: https://example.invalid' -X POST \
  -o "$work/body" -w '%{http_code}' "$base/api/cat/reset")"
[[ "$actual" == 403 ]] || fail "CAT reset must reject a foreign origin"

check_status 404 "$base/missing"
check_status 405 -X POST "$base/"
grep -qi '^allow: GET' "$work/headers" || fail "405 Allow header"

seq 1 32 | xargs -P 8 -I '{}' curl -fsS --max-time 5 "$base/api/query" \
  >"$work/parallel.json"
jq -se 'length == 32 and
  ([.[].requestId] | sort) == [range(8; 40)] and
  all(.[]; .params == [.requestId] and .sql == "SELECT * FROM \"users\" WHERE \"id\" > ?" and
    ([.rows[][0]] == [range(.requestId + 1; 11)]) and
    all(.rows[]; length == 3 and .[2] == ("user-" + (.[0] | tostring) + "@example.invalid")))' \
  "$work/parallel.json" >/dev/null || fail "Concurrent request IDs or SQL parameters"

if .lake/build/bin/leanwebstudy 65536 >"$work/body" 2>&1; then
  fail "Out-of-range port was accepted"
fi
grep -q 'Port must be between 1 and 65535' "$work/body" || fail "Port error message"

check_status 200 "$base/board/"
grep -q 'みんなの掲示板' "$work/body" || fail "Bulletin board page title"
grep -q '<form action="/board/" method="post">' "$work/body" ||
  fail "lean-html form must submit a POST to the board"
actual="$(curl -sS --max-time 5 -D "$work/headers" -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'author=Test <admin>' \
  --data-urlencode 'message=<script>alert(1)</script> & "safe" to the SQLite server' "$base/board/")"
[[ "$actual" == 303 ]] || fail "Expected bulletin board POST redirect, got $actual"
tr -d '\r' <"$work/headers" | grep -Fxi 'location: /board/' >/dev/null ||
  fail "POST must redirect back to the board"
check_status 200 "$base/board/"
grep -q '投稿一覧（1件）' "$work/body" || fail "GET must show the SQLite-backed post count"
grep -q 'Test &lt;admin&gt;' "$work/body" || fail "Post author must be escaped by lean-html"
grep -qF '&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;safe&quot; to the SQLite server' "$work/body" ||
  fail "Post body must be escaped by lean-html"
if grep -q '<script>alert(1)</script>' "$work/body"; then
  fail "Posted content must not render as executable markup"
fi

actual="$(curl -sS --max-time 5 -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'author=   ' --data-urlencode 'message=invalid' "$base/board/")"
[[ "$actual" == 400 ]] || fail "Empty bulletin board author must be rejected"
check_status 200 "$base/board/"
grep -q '投稿一覧（1件）' "$work/body" || fail "Invalid post must not be stored"

check_status 200 "$base/wiki/"
grep -q '知識を、みんなで育てる。' "$work/body" || fail "Wiki landing page"
grep -q 'Wikiへようこそ' "$work/body" || fail "Seeded wiki articles"
grep -q 'href="/wiki/new"' "$work/body" || fail "Wiki create link"
check_status 200 "$base/wiki/welcome"
grep -q 'このWikiはLean 4、lean-html、Lithe、MapleSQL、SQLiteで作られています。' "$work/body" ||
  fail "Wiki article detail"
check_status 404 "$base/wiki/not-a-real-article"
check_status 200 "$base/wiki/new"
grep -q 'form action="/wiki/create" method="post"' "$work/body" ||
  fail "Wiki create form"

actual="$(curl -sS --max-time 5 -D "$work/headers" -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'slug=sample-article' \
  --data-urlencode 'title=安全な記事' \
  --data-urlencode 'content=<script>alert(1)</script> & plain text' "$base/wiki/create")"
[[ "$actual" == 303 ]] || fail "Expected wiki create redirect, got $actual"
tr -d '\r' <"$work/headers" | grep -Fxi "location: /wiki/sample-article" >/dev/null ||
  fail "Wiki create must redirect to the new article"
check_status 200 "$base/wiki/sample-article"
grep -q '安全な記事' "$work/body" || fail "Created wiki article title"
grep -qF '&lt;script&gt;alert(1)&lt;/script&gt; &amp; plain text' "$work/body" ||
  fail "Wiki content must be escaped as plain text"
if grep -q '<script>alert(1)</script>' "$work/body"; then
  fail "Wiki content must not render as executable markup"
fi

check_status 200 "$base/wiki/edit/sample-article"
grep -q 'form action="/wiki/save" method="post"' "$work/body" ||
  fail "Wiki edit form"
actual="$(curl -sS --max-time 5 -D "$work/headers" -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'slug=sample-article' \
  --data-urlencode 'title=更新した記事' \
  --data-urlencode 'content=Updated body' "$base/wiki/save")"
[[ "$actual" == 303 ]] || fail "Expected wiki update redirect, got $actual"
check_status 200 "$base/wiki/sample-article"
grep -q '更新した記事' "$work/body" || fail "Wiki article update"
grep -q 'Updated body' "$work/body" || fail "Wiki article body update"

actual="$(curl -sS --max-time 5 -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'slug=sample-article' --data-urlencode 'title=Duplicate' \
  --data-urlencode 'content=Duplicate body' "$base/wiki/create")"
[[ "$actual" == 409 ]] || fail "Duplicate wiki slug must return HTTP 409"
actual="$(curl -sS --max-time 5 -D "$work/headers" -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'slug=sample-article' "$base/wiki/delete")"
[[ "$actual" == 303 ]] || fail "Expected wiki delete redirect, got $actual"
tr -d '\r' <"$work/headers" | grep -Fxi "location: /wiki/" >/dev/null ||
  fail "Wiki delete must redirect to the article list"
check_status 404 "$base/wiki/sample-article"

actual="$(curl -sS --max-time 5 -o "$work/body" -w '%{http_code}' \
  --data-urlencode 'slug=Invalid_Slug' --data-urlencode 'title=Invalid' \
  --data-urlencode 'content=Invalid body' "$base/wiki/create")"
[[ "$actual" == 400 ]] || fail "Invalid wiki slug must be rejected"

echo "PASS: CAT 3PL and adaptive flow, bulletin board, SQLite Wiki CRUD and escaping, SQLite HTML and SQL JSON, health, 404/405, concurrent queries, port validation"
