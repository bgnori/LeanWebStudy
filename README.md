# LeanWebStudy

A separate Lean 4 application that consumes [MapleSQL](https://github.com/bgnori/MapleSQL)
and serves dynamically generated web content backed by SQLite.

## Requirements

- VS Code with the **Lean 4** extension.
- [Elan](https://github.com/leanprover/elan) and the toolchain pinned in
  [lean-toolchain](lean-toolchain): **Lean 4.35.0**.
- Linux with a C compiler and the SQLite development library. On Debian/Ubuntu:
  `sudo apt-get install build-essential libsqlite3-dev`.

This version supplies `Std.Async` and `Std.Http.Server`; no third-party HTTP
package or Mathlib is needed. MapleSQL is pinned to a Git commit and built with
the application's toolchain. Its own repository remains unchanged.

## Build, test, and run

Open this folder in VS Code, then use its integrated terminal:

```sh
lake update
lake build
lake test
lake exe leanwebstudy
```

Visit <http://127.0.0.1:8080>. Refreshing the page changes its request counter.
Use `lake exe leanwebstudy 18080` to select a different port. The server binds
only to loopback; this is a local development scaffold, not a production deployment.
Stop it with Ctrl+C.

| Route | Result |
| --- | --- |
| `GET /` | HTML generated per request, including users read from SQLite |
| `GET /health` | JSON health check |
| `GET /api/query` | MapleSQL-generated SQL, separate parameters, and executed result rows |

Unknown paths return 404. Non-GET requests return 405 with `Allow: GET`.
HTTP transport, SQL-generation, and database failures are logged to stderr.
Failed database requests return HTTP 500 without exposing SQLite error details.
The shared request counter and database connection are protected by mutexes,
while the standard HTTP server handles connections asynchronously.
Dynamic responses disable caching.

## SQLite backend

At startup, the server opens one SQLite `:memory:` connection, creates the
`users` table, and inserts Alice, Bob, Carol, and Dave (IDs 1 through 4).
All requests share that connection: data lasts until the process exits and is
recreated on restart. No database file is written. Connection setup or seeding
failures stop startup rather than running without a working database.

The native bridge links against the system SQLite library. It prepares one
statement at a time, binds MapleSQL parameters with `sqlite3_bind_int64` or
`sqlite3_bind_text`, executes it, and finalizes the statement even on failure.
SQL and parameter values are never interpolated. Integer parameters outside
SQLite's signed 64-bit range are rejected. Result cells currently support
`INTEGER` and `TEXT`; `NULL`, `REAL`, and `BLOB` produce explicit errors.
The connection is closed when its Lean-managed handle is released.

The SQL endpoint uses the current request counter as the `id > ?` parameter
and includes `rows` as arrays of column values (`id`, `name`). For example,
request ID 3 returns:

```json
{"requestId":3,"sql":"SELECT * FROM \"users\" WHERE \"id\" > ?","params":[3],"rows":[[4,"Dave"]]}
```

From request ID 4 onward, this endpoint returns empty rows; the top page always reads
and displays all four seeded users, with names HTML-escaped.

```sh
curl -i http://127.0.0.1:8080/
curl -fsS http://127.0.0.1:8080/api/query
bash tests/http-smoke.sh
```

The HTTP smoke test requires Bash, curl, and jq, and starts and stops its own
server on port 18080 (`bash tests/http-smoke.sh 18081` selects another port).
It verifies database-backed HTML, executed results and SQL/parameter separation,
404/405 behavior, 32 concurrent queries with unique IDs, and port validation.
`lake test` also tests text binding, integer limits, statement errors and recovery,
HTML escaping, and isolation between in-memory connections.
CI installs SQLite, then runs the build, Lean tests, and HTTP smoke test.

User mutation APIs, durable storage, authentication, and a production reverse
proxy/TLS setup are intentionally not implemented yet.