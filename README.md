# LeanWebStudy

A separate Lean 4 application that consumes [MapleSQL](https://github.com/bgnori/MapleSQL)
and prepares for dynamically generated web content.

## Requirements

- VS Code with the **Lean 4** extension.
- [Elan](https://github.com/leanprover/elan) and the toolchain pinned in
  [lean-toolchain](lean-toolchain): **Lean 4.35.0**.

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
| `GET /` | HTML generated per request |
| `GET /health` | JSON health check |
| `GET /api/query` | MapleSQL-generated SQL and a separate parameter array |

Unknown paths return 404. Non-GET requests return 405 with `Allow: GET`.
HTTP transport and SQL-generation failures are logged to stderr.
The shared request counter is protected by a mutex, while the standard HTTP
server handles connections asynchronously. Dynamic responses disable caching.

```sh
curl -i http://127.0.0.1:8080/
curl -fsS http://127.0.0.1:8080/api/query
bash tests/http-smoke.sh
```

The HTTP smoke test requires Bash, curl, and jq, and starts and stops its own
server on port 18080 (`bash tests/http-smoke.sh 18081` selects another port).
It verifies dynamic responses, SQL/parameter separation, 404/405 behavior,
32 concurrent requests with unique IDs, and port validation.
CI runs the build, Lean tests, and HTTP smoke test.

The SQL endpoint uses the current request counter as a runtime parameter.
It only generates SQL; DB connections, execution, authentication, and a
production reverse proxy/TLS setup are intentionally not implemented yet.