#!/usr/bin/env python3
"""Local-only build/watch/restart proxy for LeanWebStudy."""

import argparse
import hashlib
import html
import http.client
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


CLIENT = r"""
(() => {
  const revision = __REVISION__;
  const badge = document.createElement("div");
  badge.setAttribute("role", "status");
  badge.style.cssText = "position:fixed;bottom:12px;right:12px;z-index:2147483647;" +
    "background:#222;color:white;padding:10px;max-width:90vw;max-height:50vh;" +
    "overflow:auto;white-space:pre-wrap;font:13px monospace";
  document.body.appendChild(badge);
  history.scrollRestoration = "manual";
  const key = "leanwebstudy-scroll:" + location.href;
  const saved = sessionStorage.getItem(key);
  if (saved !== null) {
    sessionStorage.removeItem(key);
    try {
      const [x, y] = JSON.parse(saved);
      const restore = () => requestAnimationFrame(() =>
        requestAnimationFrame(() => scrollTo(x, y)));
      if (document.readyState === "complete") restore();
      else addEventListener("load", restore, {once: true});
    } catch (error) { console.error("Cannot restore preview position", error); }
  }
  async function poll() {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 2500);
    try {
      const response = await fetch("/__dev/status", {
        cache: "no-store", signal: controller.signal
      });
      if (!response.ok) throw new Error("Status HTTP " + response.status);
      const status = await response.json();
      if (status.phase === "ready" && status.revision !== revision) {
        sessionStorage.setItem(key, JSON.stringify([scrollX, scrollY]));
        location.reload();
        return;
      }
      badge.hidden = status.phase === "ready";
      badge.textContent = status.phase === "error"
        ? "Update failed; this view is NOT current.\n" + status.message
        : "Updating; this view is NOT current.\n" + status.message;
    } catch (error) {
      badge.hidden = false;
      badge.textContent = "Development watcher disconnected; freshness unknown.\n" + error;
    } finally {
      clearTimeout(timeout);
    }
    setTimeout(poll, 500);
  }
  poll();
})();
"""


def snapshot(root, pages):
    """Hash watched inputs, including additions/deletions and external pages."""
    def scan_error(error):
        raise error

    files = set()
    for directory in (root, pages):
        for base, directories, names in os.walk(directory, onerror=scan_error):
            directories[:] = [
                name for name in directories
                if name not in {".lake", ".git", "__pycache__"}
            ]
            for name in names:
                path = Path(base) / name
                if path.suffix in {".lean", ".c", ".h"} or name in {
                    "lake-manifest.json", "lean-toolchain"
                }:
                    files.add(path)
    result = {}
    for path in sorted(files):
        try:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            result[str(path)] = (path.stat().st_mtime_ns, digest)
        except FileNotFoundError:
            # An atomic save or deletion will be observed by the next scan.
            continue
    return result


def stop_process(process):
    if process is None:
        return
    # Each owned command gets its own process group, including Lean workers.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()


class Development:
    def __init__(self, root, pages):
        self.root = root
        self.pages = pages
        self.lock = threading.Lock()
        self.shutdown = threading.Event()
        self.state = {"phase": "building", "revision": 0, "message": "Initial build"}
        self.backend = None
        self.command = None
        self.backend_port = None

    def status(self):
        with self.lock:
            return dict(self.state)

    def publish(self, phase, message, advance=False):
        with self.lock:
            self.state["phase"] = phase
            self.state["message"] = message
            if advance:
                self.state["revision"] += 1
        print(f"[dev] {phase}: {message}", flush=True)

    def run_command(self, args):
        process = subprocess.Popen(
            args, cwd=self.root, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, start_new_session=True,
        )
        self.command = process
        try:
            while True:
                try:
                    output, _ = process.communicate(timeout=0.25)
                    break
                except subprocess.TimeoutExpired:
                    if self.shutdown.is_set():
                        stop_process(process)
        finally:
            self.command = None
        if output:
            print(output, end="" if output.endswith("\n") else "\n", flush=True)
        if process.returncode:
            raise RuntimeError(
                f"{' '.join(args)} exited {process.returncode}\n{output[-12000:]}"
            )

    def start_backend(self):
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            self.backend_port = reservation.getsockname()[1]
        self.backend = subprocess.Popen(
            [str(self.root / ".lake/build/bin/leanwebstudy"),
             str(self.backend_port), "--dev", str(self.pages)],
            cwd=self.root, start_new_session=True,
        )
        deadline = time.monotonic() + 15
        while not self.shutdown.is_set() and time.monotonic() < deadline:
            if self.backend.poll() is not None:
                raise RuntimeError(f"Server exited {self.backend.returncode} during startup")
            connection = http.client.HTTPConnection(
                "127.0.0.1", self.backend_port, timeout=0.5
            )
            try:
                connection.request("GET", "/health")
                response = connection.getresponse()
                healthy = response.status == 200 and json.loads(response.read()) == {
                    "status": "ok"
                }
            except (OSError, http.client.HTTPException, ValueError):
                healthy = False
            finally:
                connection.close()
            if healthy and self.backend.poll() is None:
                return
            self.shutdown.wait(0.1)
        raise RuntimeError("Server did not become healthy within 15 seconds")

    def rebuild(self, inputs):
        started = time.monotonic()
        self.publish("building", "Building and checking pages")
        # Do not let old server code consume newly built shared interfaces.
        stop_process(self.backend)
        self.backend = None
        try:
            self.run_command(["lake", "build"])
            for page in sorted(self.pages.rglob("*.lean")):
                if self.shutdown.is_set():
                    return
                self.run_command(["lake", "env", "lean", str(page)])
            if self.shutdown.is_set():
                return
            if snapshot(self.root, self.pages) != inputs:
                self.publish("building", "Changed during build; rebuilding latest sources")
                return
            self.publish("starting", "Waiting for server health check")
            self.start_backend()
            if snapshot(self.root, self.pages) != inputs:
                stop_process(self.backend)
                self.backend = None
                self.publish("building", "Changed during startup; rebuilding latest sources")
                return
            self.publish(
                "ready", f"Updated in {time.monotonic() - started:.2f}s", advance=True
            )
        except (OSError, RuntimeError, ValueError) as error:
            stop_process(self.backend)
            self.backend = None
            self.publish("error", str(error))

    def watch(self):
        try:
            observed = snapshot(self.root, self.pages)
            self.rebuild(observed)
            while not self.shutdown.wait(0.25):
                current = snapshot(self.root, self.pages)
                if current != observed:
                    self.publish("building", "Saved changes detected")
                    # Debounce until inputs have been quiet for one interval.
                    while not self.shutdown.wait(0.3):
                        latest = snapshot(self.root, self.pages)
                        if latest == current:
                            break
                        current = latest
                    if self.shutdown.is_set():
                        break
                    observed = current
                    self.rebuild(observed)
                elif self.backend is not None and self.backend.poll() is not None:
                    code = self.backend.returncode
                    stop_process(self.backend)
                    self.backend = None
                    self.publish("error", f"Server exited {code}; save a source to retry")
        except (OSError, RuntimeError, ValueError) as error:
            self.publish("error", f"Watcher stopped: {error}")
        finally:
            stop_process(self.command)
            stop_process(self.backend)


def handler_for(development):
    class Preview(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            if self.path.split("?", 1)[0] == "/__dev/status":
                return
            print("[preview] " + format % args, flush=True)

        def send_body(self, status, content_type, body, headers=()):
            self.send_response(status)
            for name, value in headers:
                self.send_header(name, value)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(body)

        def html(self, status, body, state, headers=()):
            script = CLIENT.replace("__REVISION__", str(state["revision"]))
            injection = ('<script>' + script + '</script>').encode()
            position = body.lower().rfind(b"</body>")
            body = (body[:position] + injection + body[position:]
                    if position >= 0 else body + injection)
            self.send_body(status, "text/html; charset=utf-8", body, headers)

        def do_GET(self):
            state = development.status()
            path = self.path.split("?", 1)[0]
            if path == "/__dev/status":
                self.send_body(
                    200, "application/json; charset=utf-8",
                    json.dumps(state).encode(),
                )
                return
            if state["phase"] != "ready":
                self.html(
                    503, b"<!doctype html><html><head><title>Development preview</title>"
                    b"</head><body><h1>Development preview</h1>"
                    b"<p>Waiting for a successful update.</p></body></html>", state,
                )
                return
            connection = http.client.HTTPConnection(
                "127.0.0.1", development.backend_port, timeout=60
            )
            try:
                connection.request("GET", self.path, headers={"Accept-Encoding": "identity"})
                response = connection.getresponse()
                body = response.read()
                content_type = response.getheader("Content-Type", "application/octet-stream")
                headers = [
                    (name, value) for name, value in response.getheaders()
                    if name.lower() not in {
                        "content-type", "content-length", "cache-control", "connection",
                        "transfer-encoding", "keep-alive",
                    }
                ]
            except (OSError, http.client.HTTPException) as error:
                print(f"[preview] Backend request failed: {error}", file=sys.stderr, flush=True)
                self.html(502, b"<html><body><h1>Backend request failed</h1></body></html>", state)
                return
            finally:
                connection.close()
            if content_type.lower().startswith("text/html"):
                self.html(response.status, body, state, headers)
            elif response.status >= 400:
                # Error pages also need a reload client to recover on the next save.
                self.html(
                    response.status,
                    ("<html><body><pre>" + html.escape(body.decode("utf-8", errors="replace"))
                     + "</pre></body></html>").encode(), state, headers,
                )
            else:
                self.send_body(response.status, content_type, body, headers)

        def do_HEAD(self):
            self.do_GET()

        def reject_method(self):
            self.send_body(
                405, "text/plain; charset=utf-8", b"Only GET and HEAD are supported\n",
                [("Allow", "GET, HEAD")],
            )

        do_POST = reject_method
        do_PUT = reject_method
        do_DELETE = reject_method
        do_PATCH = reject_method
        do_OPTIONS = reject_method

    return Preview


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8080, help="Stable preview port")
    parser.add_argument("--pages", type=Path, default=Path("Pages"))
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    root = Path(__file__).resolve().parents[1]
    pages = (root / args.pages).resolve()
    if not pages.is_dir():
        parser.error(f"Page directory is not a directory: {pages}")
    development = Development(root, pages)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler_for(development))
    server.daemon_threads = True
    worker = threading.Thread(target=development.watch)

    def interrupt(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupt)
    try:
        print(f"[dev] Preview: http://127.0.0.1:{args.port} (pages: {pages})", flush=True)
        worker.start()
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        development.shutdown.set()
        server.server_close()
        if worker.ident is not None:
            worker.join()


if __name__ == "__main__":
    main()
