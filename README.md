# LeanWebStudy

A separate Lean 4 application that consumes [MapleSQL](https://github.com/bgnori/MapleSQL)
and serves dynamically generated web content backed by SQLite.

## Two tracks in this repository

The application study and its derived WebSocket library research have separate
documentation entry points:

- **[Web application study (Japanese)](docs/application-study/README.md)**:
  building Lean applications with HTTP, HTML, SQLite, and real-time examples.
- **[Std-extension WebSocket development (Japanese)](docs/std-websocket/README.md)**:
  upgrade integration, lifecycle contracts, proofs, and prototypes. This grew
  out of the application's integration difficulties; it is not a completed
  replacement for the existing application transports.

Start with the **[documentation map (Japanese)](docs/README.md)** to choose a
track. If successful, the WebSocket work is intended to become an independent
project and a candidate for an upstream Lean PR; neither has happened yet.
The source packages and test runner are still shared. The instructions below
remain the application setup and usage guide.

For definitions and classifications of project, web, and Lean terminology, see the
[project glossary (Japanese)](docs/application-study/glossary.md).

## Requirements

- VS Code with the **Lean 4** extension.
- [Elan](https://github.com/leanprover/elan) and the toolchain pinned in
  [lean-toolchain](lean-toolchain): **Lean 4.35.0**.
- Linux with a C compiler, SQLite and libwebsockets development libraries. On Debian/Ubuntu:
  `sudo apt-get install build-essential libsqlite3-dev libwebsockets-dev`.

## VS Code Dev Container

To keep development builds from using all of the host's resources, open this
repository in its Dev Container. The container is limited to 2 CPUs and 4 GiB
of memory, with no additional swap. Its image includes the pinned Lean
toolchain and the system build prerequisites; `lake update` runs after the
container is created. The preview ports 8080 and 18080 are forwarded.

These Docker resource limits apply when the Dev Container is run by a
Docker-compatible local environment. If a build runs out of memory, adjust the
`runArgs` limits in `.devcontainer/devcontainer.json`.

HTTP serving uses `Std.Async` and `Std.Http.Server`; [Lithe](https://github.com/JoshuaPurtell/lithe)
provides route registration and dispatch. The optional Lithe Rust server shim is
not used. Mathlib is not needed. MapleSQL is pinned to a Git commit and built
with the application's toolchain. Its own repository remains unchanged.

## Build, test, and run

Open this folder in VS Code, then use its integrated terminal:

```sh
lake update
lake build
lake test
lake exe leanwebstudy
```

Visit <http://127.0.0.1:8080> for the page index. Select a feature to open
its index and individual examples.
Use `lake exe leanwebstudy 18080` to select a different port. The server binds
only to loopback; this is a local development scaffold, not a production deployment.
Stop it with Ctrl+C.

| Route | Result |
| --- | --- |
| `GET /` | Index of the feature pages |
| `GET /sqlite/` | MapleSQL-generated queries executed against SQLite, with user data |
| `GET /sqlite/users` | SQLite users example |
| `GET /templates/` | HTML template examples index |
| `GET /templates/lean-html` | lean-html template example |
| `GET /board/` | SQLite-backed bulletin board page |
| `POST /board/` | Validate and store a bulletin board post |
| `GET /wiki/`, `/wiki/{slug}` | SQLite-backed wiki index and article |
| `GET /wiki/new`, `/wiki/edit/{slug}` | Wiki article editor |
| `POST /wiki/create`, `/wiki/save`, `/wiki/delete` | Create, update, and delete wiki articles |
| `GET /chat/` | Real-time WebSocket chat page |
| `GET /chat-ws/` | Equivalent ws-lean WebSocket chat for comparison |
| `GET /chat-same-port/` | same-port-websocket chat using the HTTP port |
| `GET /chat-sse/` | SSE chat page (server events + HTTP POST messages) |
| `GET /chat-sse/events` | Server-Sent Events chat stream |
| `POST /chat-sse/send` | Validate and broadcast a chat message |
| `GET /ws-echo/socket` | WebSocket echo on the HTTP port (StdExt upgrade API) |
| `GET /chat-same-port/socket` | same-port-websocket chat on the HTTP port |
| `GET /pong/` | WebSocket real-time two-player Pong |
| `GET /orderbook/` | Interactive limit order book and matching engine demo |
| `GET /cat/` | IRT 3PL computerized adaptive testing demo with 30 SQLite items and 10 adaptive questions |
| `GET /api/cat/current` | CAT item pool, saved responses, EAP ability estimate, and next selected item |
| `POST /api/cat/answer` | Save an answer and update the ability estimate and next item |
| `POST /api/cat/reset` | Clear the shared CAT response history |
| `GET /shop/` | Japanese EC storefront demo |
| `GET /shop/products/`, `/shop/products/{slug}` | Product list and product details |
| `GET /shop/cart/` | Example cart page |
| `POST /shop/cart/add` | Add a product to the SQLite-backed cart |
| `GET /shop/checkout/` | Example checkout confirmation |
| `POST /shop/orders` | Store an order and its items, then clear the cart |
| `GET /shop/order-complete/` | Example order-completion page |
| `GET /shop/admin/` | Store-management dashboard |
| `GET /shop/admin/inventory/` | Shared inventory and stock controls |
| `GET /shop/admin/orders/` | New orders, payment confirmation, and shipping controls |
| `GET /shop/admin/orders/processed/` | Shipped and delivered orders |
| `POST /shop/admin/inventory/update` | Update product stock |
| `POST /shop/admin/orders/status` | Confirm payment or update delivery status |
| `GET /api/orderbook` | Current in-memory bids, asks, and recent trades |
| `POST /api/orderbook/reset` | Reset the demo order book to its initial synthetic orders |
| `POST /api/orderbook/orders` | Submit a limit order; match by price-time priority |
| `GET /chat/endpoint` | WebSocket port metadata for the development preview |
| `GET /chat-ws/endpoint` | ws-lean listener port metadata for the development preview |
| `GET /health` | JSON health check |
| `GET /api/query` | MapleSQL-generated SQL, separate parameters, and executed result rows |

The `/health`, `/api/query`, and `/board/` routes and the dynamic page fallback
are registered with Lithe. Unknown paths return 404. Unsupported methods return
405 with an `Allow` header; the board also accepts POST.
HTTP transport, SQL-generation, and database failures are logged to stderr.
Failed database requests return HTTP 500 without exposing SQLite error details.
The shared request counter and database connection are protected by mutexes,
while the standard HTTP server handles connections asynchronously.
Dynamic responses disable caching.
The chat uses libwebsockets through a native C bridge, with Lean JSON validation.
Messages and recent history travel over WebSocket, not HTTP polling or POST.
Open `/chat/` in two tabs to try it. A loopback-only ephemeral WebSocket port is
started in the same process. `/chat-ws/` provides the equivalent chat using
ws-lean's HTTP/1.1 handshake, framing, and message decoders on Std.Async TCP.
It shares the validation and browser client with `/chat/`, but has independent
history and broadcasts. The pinned ws-lean HTTP/1.1 modules build unchanged with
Lean 4.35.0; its aggregate `Ws` target does not (see the compatibility details below).
The development preview tunnels `/chat/socket`, `/chat-ws/socket`,
and `/pong/socket` through its stable port. Pong exchanges paddle positions and
the player-1-authoritative ball state over WebSocket; open `/pong/` in two tabs
or devices to play. See [technology trade-offs and protocol (Japanese)](docs/application-study/websocket-chat.md)
for setup, limits, reconnection behavior, and local-only restrictions, and the
[WebSocket risk/return and cost/return report (Japanese)](docs/application-study/websocket-risk-return-report.md)
for the analysis distilled from these implementations.
The alternative `/chat-sse/` uses an HTTP event stream for server-to-browser
updates and POST for sending; its latest 50 messages are in-memory and EventSource
handles reconnection. The four chat implementations are independent and local-only.
`/chat-same-port/` uses the `same-port-websocket` upgrade API directly on the
HTTP server port, without a separate WebSocket listener or port discovery. Its
chat messages and recent history are independent from the other implementations.
The same-port `/ws-echo/socket` protocol demonstrator is covered by `tests/test_ws_std.py`.
Its current implementation,
separate lifecycle prototype, limitations, and next steps are described in the
[WebSocket development track (Japanese)](docs/std-websocket/README.md);
the prototype is not yet wired into the live transport.
The order book starts with synthetic bids and asks, matches crossing limit
orders by price then order ID (FIFO), and keeps the latest 20 trades in memory.
Prices are accepted to two decimal places and quantities are whole numbers.
The `/cat/` page stores 30 synthetic 3PL item parameter sets and its shared
10-answer demo run in the in-memory SQLite database. It estimates ability with
EAP under a standard normal prior and chooses the unused item with the greatest
Fisher information at the current estimate. The displayed item difficulty is
the synthetic pool parameter, not a live item-calibration estimate; the demo
does not contain question text. CAT response history is shared by all visitors
and remains until the reset control is used or the server restarts.
Its page includes repeatable buy-pressure, sell-pressure, whipsaw, and
depth-building scenarios; each resets the book before submitting its sequence.
It is a single, unauthenticated learning demo with no balances, cancellation,
or persistence; do not use it for real trading.
The `/shop/` demo uses lean-html templates and a separate Lean page source for
each route. Ordinary HTML links and forms provide full-page navigation:
storefront → product list → product detail → cart → checkout → completion,
without browser JavaScript. Products, cart contents, orders, and order items use
MapleSQL-generated statements and the shared in-memory SQLite database. They are
cleared when the server restarts. The unauthenticated, local-only management
pages under `/shop/admin/` share that same database. They update inventory,
payment confirmation, and new/shipped/delivered order state; order placement
decrements stock and rejects insufficient inventory. Checkout does not perform
real payment, shipping, or email delivery.
The HTTP adapter preserves Lithe's Content-Type without adding another:
HTML pages use `text/html; charset=utf-8`, JSON endpoints use
`application/json; charset=utf-8`, and text errors use `text/plain; charset=utf-8`.
Lithe response streams are bridged to the standard server's chunked HTTP bodies
for SSE delivery.

## Save-to-preview development loop

Start the development watcher once from the project root:

```sh
python3 tools/dev.py
# Optional: python3 tools/dev.py --port 18080 --pages /absolute/path/to/pages
```

This requires Python 3.10 or newer (standard library only; on Debian/Ubuntu,
`sudo apt-get install python3`), Lake, and the normal build prerequisites.
Open <http://127.0.0.1:8080> and keep editing: saved Lean/native source changes
automatically trigger `lake build`, checks of all page sources, server restart,
and browser reload after a successful health check. No manual terminal commands
or browser refresh are needed. The URL and scroll position are retained on reload;
form contents and other browser-local state are not preserved.

The preview URL stays available while the backend restarts. An on-page status
shows when the displayed view is outdated, a build/startup fails, or the watcher
disconnects. Build/page-check diagnostics are also printed in the terminal.
Failed updates do not advance the preview revision; save a corrected source to
retry. A new tab opened during an update receives a waiting page that
automatically recovers. Browser JavaScript must be enabled.

This first stage deliberately rebuilds/restarts for **every** watched change,
including page-only edits. Rapid saves are debounced, and changes during a build
or startup cause another build rather than publishing that outdated result.
Each successful cycle prints `Updated in ...s` to guide later optimization.
All backend restarts recreate the in-memory SQLite database, reset the counter,
and clear the in-memory chat history.
The old page stays visible in an already-open browser, but the old backend is
stopped before building to avoid mixing old server code with new shared modules.

Watched inputs are `.lean`, `.c`, `.h`, `lake-manifest.json`, and `lean-toolchain`
under the project and selected page directory. `.lake`, `.git`, and Python caches
are excluded. Saved dependency configuration changes trigger a build, not
`lake update`; dependency resolution remains an explicit operation. Changes
inside dependency checkouts are not watched. Page checks type-check, but do not
execute `main`; runtime failures still appear when requesting the page and are
logged by the backend.

File monitoring uses standard-library polling (250ms waits between scans, with
a 300ms debounce), chosen to avoid extra dependencies, not because Lake requires
polling. Lake checks rebuild requirements when invoked but has no built-in
watch command in the pinned version. External OS notifications such as Linux
inotify, or watchdog/watchfiles, are alternatives. Browser status polling is
separate. See the [design rationale (Japanese)](docs/application-study/module-reload.md)
for trade-offs and the measurement-driven optimization policy.

The watcher is a loopback-only, GET/HEAD development preview proxy with
`/chat/socket`, `/chat-ws/socket`, and `/pong/socket` WebSocket tunnels, not a
production server. It reserves `/__dev/status` and injects a small polling client
only in preview HTML. Normal `lake exe leanwebstudy` behavior is unchanged.
Do not run multiple watchers/builds against the same checkout concurrently.
Stop with Ctrl+C; the owned backend and build processes are stopped too.

```sh
python3 -m unittest discover -s tests -p 'test_dev*.py'
```

The integration test uses a temporary project with separate application build
outputs and verifies real page/fixture updates, error recovery, rapid saves,
page addition/deletion, and watcher shutdown.

## Page routing and live reload

Pages are loaded from the `Pages/` directory by default. Each feature has an
`index.lean` at its route, with individual examples beneath it:

- `/sqlite/` and `/sqlite/users` (MapleSQL and SQLite)
- `/templates/` and `/templates/lean-html`
- `/board/` (SQLite-backed bulletin board)
- `/wiki/` and `/wiki/{slug}` (SQLite-backed wiki)
- `/chat/` (WebSocket real-time chat)
- `/chat-ws/` (equivalent ws-lean chat with separate history)
- `/pong/` (WebSocket two-player Pong)

For example, `/blog/` runs `Pages/blog/index.lean`, and `/blog/new` runs
`Pages/blog/new.lean`. Both `/blog` and `/blog/` open the directory index.
Page sources are reloaded on each request, so edits do not require restarting
the server.

To use a different page directory:

```sh
lake exe leanwebstudy 8080 --dev /absolute/path/to/pages
```

The URL path is case-sensitive; segments may contain ASCII letters, digits,
underscores, and hyphens. Query strings do not affect page selection.
Missing or deleted pages return 404, including a missing directory index.
`/health` and `/api/query` remain server-owned; non-GET requests still return 405.

A page is a Lean source module with a `main` entry point:

```lean
import LeanWebStudy.Page

def main : IO Unit :=
  LeanWebStudy.Page.run fun context =>
    pure (s!"<h1>Hello, request {context.requestId}</h1>" ++ context.usersHtml)
```

Every request starts a fresh `lake env lean --run <page>` worker that type-checks
and executes the current source. No page registration, server rebuild, or
server restart is required for editing, adding, or deleting these page files.
Run the server from this project's root with Lake and the pinned toolchain
available. Imported dependencies still use built `.olean` files: changing
helpers imported by a page requires `lake build` for those modules. This is
source reloading in isolated processes, **not** native hot replacement within
the server's Lean runtime.

Without the watcher, SQLite rendering, server-side helpers, or fixture changes
require rebuilding and restarting the server; rebuilding does not update an already running process or
reseed its in-memory database. See the [module reload investigation (Japanese)](docs/application-study/module-reload.md)
for the update boundaries, verified behavior, and troubleshooting steps.

The server sends a JSON context on stdin containing `requestId`, the URL `path`,
HTML-escaped `usersHtml`, `sqliteDemoHtml` (source attribution, source/SQLite
schemas, MapleSQL statements, generated SQL, separate parameters, and actual
query results) queried/rendered using its existing SQLite connection,
`boardPosts` for the bulletin board, and `wikiArticles` for the Wiki.
Optional context fields default for older context producers.
`Page.run` returns the HTML as a JSON string on stdout; use stderr for page
diagnostics. The counter and database remain in the server and survive page
changes and worker failures. Workers do not inherit the live database handle;
other data access must be explicitly added to the server/context interface.
Use `LeanWebStudy.Page.escapeHtml` for any additional untrusted text.
Compilation, rendering, and protocol failures produce HTTP 500 and diagnostics
on server stderr, without exposing compiler output in the HTTP response.
Page responses, including errors and missing pages, use `no-store`.

The bulletin board page uses a lean-html form to submit posts with HTTP POST.
Lithe parses and validates the form, MapleSQL generates parameterized INSERT
and SELECT statements, and SQLite stores the posts in the server's shared
in-memory database. GET renders the latest posts with lean-html's automatic
text escaping. The page uses POST-Redirect-GET; posts are visible to all
visitors of this server and are cleared when the server restarts. This sample
accepts names up to 24 characters and messages up to 500 characters, and does
not include authentication or CSRF protection.

## SQLite Wiki

The sample Wiki at `/wiki/` lists three starter articles and supports reading,
creating, editing, and deleting articles. It uses the repository's existing Lean
4 page workers and lean-html DSL; Lithe handles form routes, MapleSQL generates
parameterized statements, and SQLite stores each article's slug, title, and
plain-text content. Article text is escaped by lean-html and is not interpreted
as HTML. Slugs use lowercase ASCII letters, numbers, and hyphens; titles are
limited to 120 characters and content to 10,000 characters.

Like the bulletin board, Wiki data is stored in the shared in-memory SQLite
database, is visible to every visitor, and is cleared when the server restarts.
This is an instructional sample, not a production CMS: it has no authentication,
authorization, CSRF protection, revision history, or durable storage.

## HTML templating

The project is written in Lean 4, so template engines for other language
runtimes (such as Jinja, EJS, or Handlebars) cannot be used directly by its
page workers. The existing Lean-native option found for composing HTML is
[lean-html](https://github.com/paulbutcher/lean-html), included as a pinned Lake
dependency. It is an embedded, typed HTML DSL rather than a separate
`{{variable}}` template-file engine:

| Option | Lean 4 compatible | Approach | Main trade-off |
| --- | --- | --- | --- |
| [lean-html](https://github.com/paulbutcher/lean-html) | Yes | Typed HTML nodes composed in Lean | Checks element content models and escapes text/attributes, but markup remains Lean source |
| Mustache / Handlebars / Jinja / EJS | No native Lean implementation found | Text templates rendered by their respective runtimes | Would require a separate runtime or a new integration layer |
| String concatenation/interpolation | Built in | Construct HTML as `String` | Flexible, but tag structure and escaping are the caller's responsibility |

The [lean-html sample](Pages/templates/lean-html.lean) shows a full page
composed from typed elements and inserts request context as text. It uses
automatic escaping instead of `Node.unsafeRaw`; retain that default for
untrusted content. `lake update` resolves the pinned dependency before building.

Workers run on dedicated tasks so compilation or a slow renderer does not block
health checks. This approach prioritizes a simple Lean-compatible development
cycle over latency: each page request incurs process startup and type-checking.
There is no worker timeout or concurrency cap, and worker-local state is reset
on every request. Page code is trusted local code with the server user's
permissions, not sandboxed; do not enable this mode for untrusted pages or
production traffic. Paths cannot traverse outside the page directory, including
through symlinks.

```sh
bash tests/dev-pages-smoke.sh
```

This test uses port 18082 by default and verifies edits, additions, deletions,
nested routes, error recovery, state preservation, path confinement, and health
checks during a slow page request, all without restarting its server.

## SQLite backend

At startup, the server opens one SQLite `:memory:` connection, creates the
`users`, `posts`, and `wiki_articles` tables, and inserts ten synthetic users
(IDs 1 through 10) and three starter Wiki articles. All requests share that
connection: data lasts until the process exits and is recreated on restart.
No database file is written. Connection setup or seeding failures stop startup
rather than running without a working database.

### Dummy data provenance and schemas

The fixture in [SampleData.lean](LeanWebStudy/SampleData.lean) adapts the `id`/`name`
projection of `users` from [JSONPlaceholder's data.json](https://github.com/typicode/jsonplaceholder/blob/7ae4432ac3f60e7226a899c25e04826207d07098/data.json),
pinned to commit `7ae4432ac3f60e7226a899c25e04826207d07098`.
Its [seed.js](https://github.com/typicode/jsonplaceholder/blob/7ae4432ac3f60e7226a899c25e04826207d07098/seed.js)
uses Faker to generate fictional users, not a real customer dataset.
JSONPlaceholder is MIT-licensed; the copyright notice and full license are
preserved in [data/LICENSE-jsonplaceholder](data/LICENSE-jsonplaceholder).
Use, modification, redistribution, and commercial use are permitted subject to
the MIT notice requirement; there is no warranty. Fictional names may
coincidentally match real people and must not be treated as verified identities.

ID 2's name is changed to `Leanne Graham`, matching ID 1, to demonstrate a
non-unique name lookup. Each row gets a locally generated email
`user-{id}@example.invalid`; `.invalid` is a reserved non-resolving domain
([RFC 2606](https://www.rfc-editor.org/rfc/rfc2606.html)).
Source email addresses are discarded, not reused. Phone numbers, postal
addresses, websites, companies, and images are not imported or contacted.
Email addresses are displayed as escaped text, not mailto links; no email is sent.
The fixture is compiled locally: neither startup nor page rendering
downloads data or executes external source code.
To reproduce the adapted fixture without downloading unrelated records to disk:

```sh
curl --fail --silent --show-error \
  https://raw.githubusercontent.com/typicode/jsonplaceholder/7ae4432ac3f60e7226a899c25e04826207d07098/data.json |
  jq '.users | map({id, name: (if .id == 2 then "Leanne Graham" else .name end),
    email: ("user-" + (.id | tostring) + "@example.invalid")})'
```

Both `/sqlite/` and `/sqlite/users` display the original users object structure
(including nested address/company fields and their types) and the actual DDL:

```sql
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE)
```

The mapping is `users[].id → users.id` and `users[].name → users.name` (except ID 2).
`email` is generated from the ID; all other source fields are discarded.
Names may repeat; IDs and emails are unique. Pages show the actual MapleSQL INSERT/SELECT
statements, generated SQL, bound parameters, and executed SELECT results.
The page demo always selects `id > 3`, so it continues to show seven results
regardless of the request counter. MapleSQL constructs SQL and parameters; the
SQLite bridge handles execution. MapleSQL does not validate the database schema.

The second SELECT example uses `SelectItem.named "email"` and a bound name:

```sql
SELECT "email" FROM "users" WHERE "name" = ?
```

With `params = ["Leanne Graham"]`, the actual result is
`[["user-1@example.invalid"], ["user-2@example.invalid"]]`: exactly two rows,
each containing only the email column. Both SQLite pages display the statement,
generated SQL, parameters, and executed result. The name is never interpolated
into SQL.

The native bridge links against the system SQLite library. It prepares one
statement at a time, binds MapleSQL parameters with `sqlite3_bind_int64` or
`sqlite3_bind_text`, executes it, and finalizes the statement even on failure.
SQL and parameter values are never interpolated. Integer parameters outside
SQLite's signed 64-bit range are rejected. Result cells currently support
`INTEGER` and `TEXT`; `NULL`, `REAL`, and `BLOB` produce explicit errors.
The connection is closed when its Lean-managed handle is released.

The SQL endpoint uses the current request counter as the `id > ?` parameter
and includes `rows` as arrays of column values (`id`, `name`, `email`). For example,
request ID 9 returns:

```json
{"requestId":9,"sql":"SELECT * FROM \"users\" WHERE \"id\" > ?","params":[9],"rows":[[10,"Clementina DuBuque","user-10@example.invalid"]]}
```

From request ID 10 onward, this endpoint returns empty rows; both SQLite pages
always query and display all ten seeded users, with names HTML-escaped.

```sh
curl -i http://127.0.0.1:8080/
curl -fsS http://127.0.0.1:8080/api/query
bash tests/http-smoke.sh
```

The HTTP smoke test requires Bash, curl, and jq, and starts and stops its own
server on port 18080 (`bash tests/http-smoke.sh 18081` selects another port).
It verifies database-backed HTML, bulletin board POST/GET persistence and escaping, executed results and SQL/parameter separation,
404/405 behavior, 32 concurrent queries with unique IDs, and port validation.
`lake test` also tests text binding, integer limits, statement errors and recovery,
HTML escaping, and isolation between in-memory connections.
CI installs SQLite and libwebsockets, then runs the build, Lean tests, HTTP smoke
tests, watcher tests, and WebSocket/SSE chat tests.

User mutation APIs, durable storage, authentication, and a production reverse
proxy/TLS setup are intentionally not implemented yet.