import base64
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "dev", Path(__file__).resolve().parents[1] / "tools/dev.py"
)
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class WatchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.pages = self.root / "Pages"
        self.pages.mkdir()
        self.page = self.pages / "index.lean"
        self.page.write_text("def main : IO Unit := pure ()")
        self.development = dev.Development(self.root, self.pages)

    def test_snapshot_edits_additions_deletions_external_pages_and_exclusions(self):
        initial = dev.snapshot(self.root, self.pages)
        self.page.write_text("def main : IO Unit := IO.println \"new\"")
        self.assertNotEqual(initial, dev.snapshot(self.root, self.pages))
        (self.root / ".lake").mkdir()
        (self.root / ".lake/ignored.lean").write_text("ignored")
        edited = dev.snapshot(self.root, self.pages)
        (self.root / ".lake/ignored.lean").write_text("changed")
        self.assertEqual(edited, dev.snapshot(self.root, self.pages))
        added = self.pages / "new.lean"
        added.write_text("new")
        self.assertNotEqual(edited, dev.snapshot(self.root, self.pages))
        added.unlink()
        self.assertEqual(edited, dev.snapshot(self.root, self.pages))
        with tempfile.TemporaryDirectory() as external:
            outside = Path(external)
            (outside / "index.lean").write_text("external")
            self.assertIn(str(outside / "index.lean"), dev.snapshot(self.root, outside))

    def test_build_and_check_before_start_and_publish(self):
        events = []
        with patch.object(self.development, "run_command", side_effect=events.append), \
                patch.object(self.development, "start_backend", side_effect=lambda: events.append("start")):
            self.development.rebuild(dev.snapshot(self.root, self.pages))
        self.assertEqual(events, [
            ["lake", "build"], ["lake", "env", "lean", str(self.page)], "start"
        ])
        self.assertEqual(self.development.status()["phase"], "ready")
        self.assertEqual(self.development.status()["revision"], 1)

    def test_unchanged_source_save_can_retry_failed_startup(self):
        initial = dev.snapshot(self.root, self.pages)
        modified = self.page.stat().st_mtime_ns + 1
        os.utime(self.page, ns=(modified, modified))
        self.assertNotEqual(initial, dev.snapshot(self.root, self.pages))

    def test_scan_errors_are_not_silently_ignored(self):
        def inaccessible(*args, **kwargs):
            kwargs["onerror"](PermissionError("Cannot read source directory"))
        with patch.object(dev.os, "walk", side_effect=inaccessible):
            with self.assertRaisesRegex(PermissionError, "Cannot read source"):
                dev.snapshot(self.root, self.pages)

    def test_build_failure_is_explicit_and_does_not_start(self):
        with patch.object(self.development, "run_command", side_effect=RuntimeError("compile error")), \
                patch.object(self.development, "start_backend") as start:
            self.development.rebuild(dev.snapshot(self.root, self.pages))
        start.assert_not_called()
        self.assertEqual(self.development.status()["phase"], "error")
        self.assertIn("compile error", self.development.status()["message"])
        self.assertEqual(self.development.status()["revision"], 0)

    def test_page_failure_is_not_a_successful_update(self):
        with patch.object(self.development, "run_command", side_effect=[None, RuntimeError("page error")]), \
                patch.object(self.development, "start_backend") as start:
            self.development.rebuild(dev.snapshot(self.root, self.pages))
        start.assert_not_called()
        self.assertEqual(self.development.status()["phase"], "error")

    def test_edit_during_build_never_publishes_stale_success(self):
        def edit(args):
            self.page.write_text("newer source")
        with patch.object(self.development, "run_command", side_effect=edit), \
                patch.object(self.development, "start_backend") as start:
            self.development.rebuild(dev.snapshot(self.root, self.pages))
        start.assert_not_called()
        self.assertEqual(self.development.status()["phase"], "building")
        self.assertEqual(self.development.status()["revision"], 0)

    def test_start_failure_and_recovery(self):
        inputs = dev.snapshot(self.root, self.pages)
        with patch.object(self.development, "run_command"), \
                patch.object(self.development, "start_backend", side_effect=RuntimeError("port error")):
            self.development.rebuild(inputs)
        self.assertEqual(self.development.status()["phase"], "error")
        with patch.object(self.development, "run_command"), \
                patch.object(self.development, "start_backend"):
            self.development.rebuild(inputs)
        self.assertEqual(self.development.status()["phase"], "ready")
        self.assertEqual(self.development.status()["revision"], 1)

    def test_shutdown_interrupts_command(self):
        timer = threading.Timer(0.1, self.development.shutdown.set)
        timer.start()
        self.addCleanup(timer.join)
        with self.assertRaises(RuntimeError):
            self.development.run_command(["sleep", "30"])
        self.assertIsNone(self.development.command)


class Backend(BaseHTTPRequestHandler):
    def do_GET(self):
        code, content_type, body = (
            (404, "text/plain; charset=utf-8", b"missing <page>")
            if self.path == "/missing" else
            (200, "application/json", b'{"status":"ok"}')
            if self.path == "/health" else
            (200, "text/html; charset=utf-8", b"<html><body>current</body></html>")
        )
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.development = dev.Development(Path("."), Path("Pages"))
        self.backend = self.serve(Backend)
        self.development.backend_port = self.backend.server_port
        self.preview = self.serve(dev.handler_for(self.development))

    def serve(self, handler):
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        def cleanup():
            server.shutdown()
            server.server_close()
            thread.join()
        self.addCleanup(cleanup)
        return server

    def request(self, path, method="GET", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.preview.server_port)
        connection.request(method, path, headers=headers or {})
        response = connection.getresponse()
        result = response.status, response.getheaders(), response.read()
        connection.close()
        return result

    def test_status_is_available_during_failure_and_build(self):
        self.development.publish("error", "compiler <error>")
        code, headers, body = self.request("/__dev/status")
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)["message"], "compiler <error>")
        self.assertIn(("Cache-Control", "no-store"), headers)
        code, _, body = self.request("/sqlite/users?x=1")
        self.assertEqual(code, 503)
        self.assertIn(b'fetch("/__dev/status"', body)

    def test_same_port_websocket_tunnels_without_endpoint_discovery(self):
        class UpgradeBackend(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):
                self.server.request_paths.append(self.path)
                key = self.headers.get("Sec-WebSocket-Key")
                if self.path != "/chat-same-port/socket" or key is None:
                    self.send_error(404)
                    return
                accept = base64.b64encode(hashlib.sha1(
                    (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
                ).digest()).decode()
                self.send_response_only(101)
                self.send_header("Upgrade", "websocket")
                self.send_header("Connection", "Upgrade")
                self.send_header("Sec-WebSocket-Accept", accept)
                self.end_headers()
                self.wfile.flush()
                self.close_connection = True

            def log_message(self, *args):
                pass

        backend = self.serve(UpgradeBackend)
        backend.request_paths = []
        self.development.backend_port = backend.server_port
        self.development.publish("ready", "test")
        key = base64.b64encode(os.urandom(16)).decode()
        with socket.create_connection(
                ("127.0.0.1", self.preview.server_port), timeout=5) as client:
            client.sendall((
                "GET /chat-same-port/socket HTTP/1.1\r\n"
                f"Host: 127.0.0.1:{self.preview.server_port}\r\n"
                f"Origin: http://127.0.0.1:{self.preview.server_port}\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Key: {key}\r\n"
                "Sec-WebSocket-Version: 13\r\n\r\n"
            ).encode())
            response = bytearray()
            while not response.endswith(b"\r\n\r\n"):
                chunk = client.recv(1)
                self.assertTrue(chunk, "WebSocket proxy closed before handshake")
                response.extend(chunk)
        self.assertTrue(response.startswith(b"HTTP/1.1 101 "))
        self.assertEqual(backend.request_paths, ["/chat-same-port/socket"])

    def test_success_injects_generation_and_keeps_json_unchanged(self):
        self.development.publish("ready", "done", advance=True)
        code, headers, body = self.request("/")
        self.assertEqual(code, 200)
        self.assertIn(b"const revision = 1;", body)
        self.assertLess(body.index(b"<script>"), body.index(b"</body>"))
        self.assertEqual(sum(name.lower() == "content-type" for name, _ in headers), 1)
        code, _, body = self.request("/health")
        self.assertEqual(code, 200)
        self.assertEqual(body, b'{"status":"ok"}')

    def test_missing_pages_can_recover_and_unsupported_methods_are_explicit(self):
        self.development.publish("ready", "done", advance=True)
        code, _, body = self.request("/missing")
        self.assertEqual(code, 404)
        self.assertIn(b"missing &lt;page&gt;", body)
        self.assertIn(b"location.reload()", body)
        code, headers, _ = self.request("/", "POST")
        self.assertEqual(code, 405)
        self.assertIn(("Allow", "GET, HEAD"), headers)

    def test_websocket_origin_upgrade_and_discovery_failures_are_explicit(self):
        self.development.publish("ready", "done")
        origin = f"http://127.0.0.1:{self.preview.server_port}"
        for path in ("/chat/socket", "/chat-ws/socket"):
            with self.subTest(path=path):
                code, _, _ = self.request(path, headers={"Origin": "http://evil.invalid"})
                self.assertEqual(code, 403)
                code, _, _ = self.request(path, headers={"Origin": origin})
                self.assertEqual(code, 426)
                code, _, body = self.request(
                    path, headers={"Origin": origin, "Upgrade": "websocket"}
                )
                self.assertEqual(code, 502)
                self.assertIn(b"WebSocket tunnel failed", body)


if __name__ == "__main__":
    unittest.main()
