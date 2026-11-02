"""Real WebSocket integration tests using only Python's standard library."""

import base64
import hashlib
import http.client
import importlib.util
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import threading
import time
from urllib.parse import urlencode
import unittest
import uuid
from http.server import ThreadingHTTPServer


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("chat_dev", ROOT / "tools/dev.py")
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class WebSocket:
    def __init__(self, port, origin, path="/chat/socket", protocol="leanwebstudy-chat",
                 initial_bytes=b""):
        self.socket = socket.create_connection(("127.0.0.1", port), timeout=3)
        self.socket.settimeout(3)
        key = base64.b64encode(os.urandom(16)).decode()
        headers = [
            f"GET {path} HTTP/1.1", f"Host: 127.0.0.1:{port}",
            "Upgrade: websocket", "Connection: Upgrade",
            f"Sec-WebSocket-Key: {key}", "Sec-WebSocket-Version: 13",
        ]
        if protocol is not None:
            headers.append(f"Sec-WebSocket-Protocol: {protocol}")
        if origin is not None:
            headers.append(f"Origin: {origin}")
        self.socket.sendall(("\r\n".join(headers) + "\r\n\r\n").encode() + initial_bytes)
        head = bytearray()
        try:
            while not head.endswith(b"\r\n\r\n"):
                head.extend(self.read(1))
                if len(head) > 16384:
                    raise AssertionError("Oversized handshake")
            expected = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
            ).digest())
            if not head.startswith(b"HTTP/1.1 101 ") or expected.lower() not in head.lower():
                raise ConnectionError(f"Upgrade rejected: {head!r}")
        except BaseException:
            self.socket.close()
            raise

    def read(self, size):
        data = bytearray()
        while len(data) < size:
            chunk = self.socket.recv(size - len(data))
            if not chunk:
                raise ConnectionError("WebSocket disconnected")
            data.extend(chunk)
        return bytes(data)

    @staticmethod
    def frame_bytes(data, opcode=1, final=True):
        mask = os.urandom(4)
        size = len(data)
        header = bytes([(0x80 if final else 0) | opcode])
        if size < 126:
            header += bytes([0x80 | size])
        elif size < 65536:
            header += bytes([0x80 | 126]) + struct.pack("!H", size)
        else:
            header += bytes([0x80 | 127]) + struct.pack("!Q", size)
        return header + mask + bytes(
            value ^ mask[index % 4] for index, value in enumerate(data)
        )

    def send_frame(self, data, opcode=1, final=True):
        self.socket.sendall(self.frame_bytes(data, opcode, final))

    def send(self, author="Ada", message="こんにちは", **fields):
        request = {"type": "message", "author": author, "message": message,
                   "requestId": str(uuid.uuid4()), **fields}
        self.send_frame(json.dumps(request, ensure_ascii=False).encode())
        return request

    def frame(self):
        first, second = self.read(2)
        if second & 0x80:
            raise AssertionError("Server frames must not be masked")
        size = second & 0x7f
        if size == 126:
            size = struct.unpack("!H", self.read(2))[0]
        elif size == 127:
            size = struct.unpack("!Q", self.read(8))[0]
        return first & 0x0f, self.read(size)

    def event(self):
        opcode, data = self.frame()
        if opcode != 1:
            raise AssertionError(f"Expected text event, got opcode {opcode}: {data!r}")
        return json.loads(data)

    def close(self):
        self.socket.close()


class SSEClient:
    def __init__(self, port):
        self.connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        self.connection.request("GET", "/chat-sse/events")
        self.response = self.connection.getresponse()
        if self.response.status != 200:
            raise ConnectionError(f"SSE stream rejected: {self.response.status}")
        if self.response.getheader("Content-Type") != "text/event-stream; charset=utf-8":
            self.connection.close()
            raise AssertionError("SSE response must use the event-stream content type")
        self.buffer = bytearray()

    def event(self):
        while b"\n\n" not in self.buffer:
            chunk = self.response.read1(65536)
            if not chunk:
                raise ConnectionError("SSE stream disconnected")
            self.buffer.extend(chunk)
        raw, remainder = self.buffer.split(b"\n\n", 1)
        self.buffer = bytearray(remainder)
        fields = {}
        for line in raw.decode().splitlines():
            if not line or line.startswith(":"):
                continue
            name, _, value = line.partition(":")
            fields[name] = value.lstrip()
        return fields

    def close(self):
        self.connection.close()


class ChatTests(unittest.TestCase):
    page_path = "/chat/"
    socket_path = "/chat/socket"

    @classmethod
    def setUpClass(cls):
        cls.log = tempfile.TemporaryFile(mode="w+")
        with socket.socket() as reservation:
            reservation.bind(("127.0.0.1", 0))
            cls.http_port = reservation.getsockname()[1]
        cls.process = subprocess.Popen(
            [str(ROOT / ".lake/build/bin/leanwebstudy"), str(cls.http_port)],
            cwd=ROOT, stdout=cls.log, stderr=cls.log,
        )
        cls.origin = f"http://127.0.0.1:{cls.http_port}"
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                if cls.process.poll() is not None:
                    raise RuntimeError("Chat server exited during startup")
                try:
                    status, data = cls.request(cls.page_path + "endpoint")
                    if status == 200:
                        cls.port = json.loads(data)["port"]
                        break
                except (OSError, http.client.HTTPException):
                    pass
                time.sleep(0.05)
            else:
                raise RuntimeError("Chat server did not become ready")
        except BaseException:
            cls.tearDownClass()
            raise

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        try:
            cls.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            cls.process.kill()
            cls.process.wait()
        cls.log.seek(0)
        output = cls.log.read()
        cls.log.close()
        if cls.process.returncode not in (0, -15):
            raise AssertionError(f"Chat server failed:\n{output}")

    @classmethod
    def request(cls, path, method="GET"):
        connection = http.client.HTTPConnection("127.0.0.1", cls.http_port, timeout=30)
        try:
            connection.request(method, path)
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def connect(self, port=None, origin=None):
        client = WebSocket(port or self.port, origin or self.origin, self.socket_path)
        self.addCleanup(client.close)
        history = client.event()
        self.assertEqual(history["type"], "history")
        return client, history["messages"]

    def connect_sse(self, port=None):
        client = SSEClient(port or self.http_port)
        self.addCleanup(client.close)
        history = client.event()
        self.assertIn("id", history)
        self.assertEqual(json.loads(history["data"])["type"], "history")
        return client, json.loads(history["data"])["messages"]

    def test_sse_chat_history_post_broadcast_and_validation(self):
        first, _ = self.connect_sse()
        second, _ = self.connect_sse()
        body = urlencode({
            "author": "  Ada  ", "message": "SSE says hello",
            "requestId": "sse-test-1",
        })
        connection = http.client.HTTPConnection(
            "127.0.0.1", self.http_port, timeout=5
        )
        connection.request(
            "POST", "/chat-sse/send", body=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Origin": self.origin,
            },
        )
        response = connection.getresponse()
        self.assertEqual(response.status, 202)
        self.assertTrue(json.loads(response.read())["accepted"])
        connection.close()

        one = first.event()
        two = second.event()
        self.assertEqual(one["id"], two["id"])
        message = json.loads(one["data"])
        self.assertEqual(message["type"], "message")
        self.assertEqual(message["author"], "Ada")
        self.assertEqual(message["message"], "SSE says hello")
        self.assertEqual(message["requestId"], "sse-test-1")

        third, history = self.connect_sse()
        self.assertEqual(history[-1]["id"], message["id"])
        self.assertEqual(self.request("/chat-sse/events", "POST")[0], 405)
        self.assertEqual(self.request("/chat-sse/", "POST")[0], 405)
        status, page = self.request("/chat-sse/")
        self.assertEqual(status, 200)
        self.assertIn(b"new EventSource", page)
        self.assertIn(b"/chat-sse/send", page)

        connection = http.client.HTTPConnection(
            "127.0.0.1", self.http_port, timeout=5
        )
        connection.request(
            "POST", "/chat-sse/send",
            body=urlencode({"author": " ", "message": "bad", "requestId": "bad"}),
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Origin": self.origin,
            },
        )
        response = connection.getresponse()
        self.assertEqual(response.status, 400)
        connection.close()

        connection = http.client.HTTPConnection(
            "127.0.0.1", self.http_port, timeout=5
        )
        connection.request(
            "POST", "/chat-sse/send",
            body=urlencode({"author": "Ada", "message": "no origin", "requestId": "no-origin"}),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        self.assertEqual(connection.getresponse().status, 403)
        connection.close()

    def test_pong_roles_validation_broadcast_and_disconnect_presence(self):
        first = WebSocket(self.port, self.origin, "/pong/socket", "leanwebstudy-pong")
        self.addCleanup(first.close)
        self.assertEqual(first.event(), {"type": "welcome", "player": 1})
        self.assertEqual(first.event(), {"type": "players", "count": 1})

        second = WebSocket(self.port, self.origin, "/pong/socket", "leanwebstudy-pong")
        self.addCleanup(second.close)
        self.assertEqual(second.event(), {"type": "welcome", "player": 2})
        self.assertEqual(second.event(), {"type": "players", "count": 2})
        self.assertEqual(first.event(), {"type": "players", "count": 2})

        paddle = {"type": "paddle", "y": 123}
        second.send_frame(json.dumps(paddle).encode())
        event = {"type": "update", "player": 2, "event": paddle}
        self.assertEqual(first.event(), event)
        self.assertEqual(second.event(), event)

        ball = {"type": "ball", "x": 400, "y": 225, "left": 1, "right": 0}
        first.send_frame(json.dumps(ball).encode())
        event = {"type": "update", "player": 1, "event": ball}
        self.assertEqual(first.event(), event)
        self.assertEqual(second.event(), event)

        first.send_frame(b'{"type":"paddle","y":371}')
        self.assertEqual(first.event()["type"], "error")
        second.send_frame(json.dumps(ball).encode())
        self.assertEqual(second.event()["type"], "error")
        first.close()
        self.assertEqual(second.event(), {"type": "players", "count": 1})

        third = WebSocket(self.port, self.origin, "/pong/socket", "leanwebstudy-pong")
        self.addCleanup(third.close)
        self.assertEqual(third.event(), {"type": "welcome", "player": 1})
        self.assertEqual(third.event(), {"type": "players", "count": 2})
        self.assertEqual(second.event(), {"type": "players", "count": 2})

    def test_broadcast_history_order_reconnect_and_fifty_message_limit(self):
        first, _ = self.connect()
        second, _ = self.connect()
        sent = first.send(author="  Ada  ", message="<script>こんにちは & ' \"</script>")
        started = time.monotonic()
        event = first.event()
        self.assertEqual(second.event(), event)
        self.assertLess(time.monotonic() - started, 1.0, "Delivery must be real-time, not polling")
        self.assertEqual(event["author"], "Ada")
        self.assertEqual(event["message"], sent["message"])
        self.assertEqual(event["requestId"], sent["requestId"])
        reconnect, history = self.connect()
        self.assertEqual(history[-1], event)
        reconnect.close()
        ids = []
        for index in range(55):
            second.send(message=f"ordered-{index}")
            received = first.event()
            self.assertEqual(second.event(), received)
            ids.append(received["id"])
        self.assertEqual(ids, list(range(ids[0], ids[0] + 55)))
        _, history = self.connect()
        self.assertEqual(len(history), 50)
        self.assertEqual([entry["id"] for entry in history], ids[-50:])
        self.assertEqual(history[-1]["message"], "ordered-54")

    def test_validation_character_and_byte_limits_do_not_broadcast(self):
        sender, _ = self.connect()
        receiver, _ = self.connect()
        sender.send(author="😀" * 24, message="界" * 500)
        valid = sender.event()
        self.assertEqual(valid["type"], "message")
        self.assertEqual(receiver.event(), valid)
        for fields in (
            {"author": " "}, {"author": "界" * 25}, {"message": ""},
            {"message": "界" * 501}, {"type": "unknown"}, {"author": 12},
            {"requestId": ""}, {"requestId": "x" * 65},
        ):
            sender.send(**fields)
            self.assertEqual(sender.event()["type"], "error")
        for raw in (b"not JSON", b"[]", b"{}", b'{"type":"message"}'):
            sender.send_frame(raw)
            self.assertEqual(sender.event()["type"], "error")
        sender.send(message="after-errors")
        recovered = sender.event()
        self.assertEqual(recovered["id"], valid["id"] + 1)
        self.assertEqual(receiver.event(), recovered, "Invalid messages must not be broadcast")
        oversized, _ = self.connect()
        oversized.send_frame(b"x" * 8193)
        opcode, data = oversized.frame()
        self.assertEqual(opcode, 8)
        self.assertEqual(struct.unpack("!H", data[:2])[0], 1009)

    def test_fragmentation_ping_pong_binary_utf8_and_close(self):
        client, _ = self.connect()
        request = json.dumps({
            "type": "message", "requestId": "fragmented",
            "author": "Ada", "message": "日本語",
        }, ensure_ascii=False).encode()
        split = request.index("日".encode()) + 1
        client.send_frame(request[:split], final=False)
        client.send_frame(b"ping-during-fragments", opcode=9)
        self.assertEqual(client.frame(), (10, b"ping-during-fragments"))
        client.send_frame(request[split:], opcode=0)
        self.assertEqual(client.event()["message"], "日本語")
        for data, opcode, expected_code in ((b"binary", 2, 1003), (b"\xff", 1, 1007)):
            other, _ = self.connect()
            other.send_frame(data, opcode=opcode)
            close_opcode, payload = other.frame()
            self.assertEqual(close_opcode, 8)
            self.assertEqual(struct.unpack("!H", payload[:2])[0], expected_code)
        client.send_frame(struct.pack("!H", 1000), opcode=8)
        self.assertEqual(client.frame()[0], 8)

    def test_origin_path_and_http_methods(self):
        for origin in ("http://evil.invalid", None, self.origin + ".evil.invalid"):
            with self.assertRaises((ConnectionError, OSError)):
                WebSocket(self.port, origin, self.socket_path)
        with self.assertRaises((ConnectionError, OSError)):
            WebSocket(self.port, self.origin, path="/other")
        with self.assertRaises((ConnectionError, OSError)):
            WebSocket(self.port, self.origin, path="/pong/socket")
        for protocol in (None, "other-protocol"):
            with self.assertRaises((ConnectionError, OSError)):
                WebSocket(self.port, self.origin, self.socket_path, protocol=protocol)
        self.assertEqual(self.request(self.page_path + "endpoint", "POST")[0], 405)
        self.assertEqual(self.request(self.page_path, "POST")[0], 405)
        status, page = self.request(self.page_path)
        self.assertEqual(status, 200)
        self.assertIn(f'content="{self.port}"'.encode(), page)
        self.assertIn(b"new WebSocket", page)
        self.assertIn(b"text.textContent", page)
        self.assertIn(self.socket_path.encode(), page)
        self.assertIn(b'href="/chat/"', page)
        self.assertIn(b'href="/chat-ws/"', page)
        self.assertNotIn(b"fetch(", page)
        status, alias = self.request(self.page_path.rstrip("/"))
        self.assertEqual(status, 200)
        self.assertIn(self.socket_path.encode(), alias)
        self.assertIn(f'content="{self.port}"'.encode(), alias)
        status, page = self.request("/pong/")
        self.assertEqual(status, 200)
        self.assertIn("通信対戦 Pong".encode(), page)
        self.assertIn(b"/pong/socket", page)
        self.assertIn(b"leanwebstudy-pong", page)

    def test_connection_limit(self):
        clients = []
        for _ in range(64):
            client, _ = self.connect()
            clients.append(client)
        with self.assertRaises((ConnectionError, OSError)):
            WebSocket(self.port, self.origin, self.socket_path)
        clients[0].send(message="at-connection-limit")
        for client in clients:
            self.assertEqual(client.event()["message"], "at-connection-limit")
        for client in clients:
            client.close()
        deadline = time.monotonic() + 5
        while True:
            try:
                replacement, _ = self.connect()
                replacement.send(message="connection-slot-reused")
                self.assertEqual(replacement.event()["message"], "connection-slot-reused")
                replacement.close()
                break
            except (ConnectionError, OSError):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.05)

    def test_preview_tunnel_same_origin_broadcast_and_shutdown(self):
        development = dev.Development(ROOT, ROOT / "Pages")
        development.backend_port = self.http_port
        development.publish("ready", "test")
        preview = ThreadingHTTPServer(("127.0.0.1", 0), dev.handler_for(development))
        thread = threading.Thread(target=preview.serve_forever)
        thread.start()
        def cleanup():
            development.shutdown.set()
            preview.shutdown()
            preview.server_close()
            thread.join()
        self.addCleanup(cleanup)
        port = preview.server_port
        origin = f"http://127.0.0.1:{port}"
        client, _ = self.connect(port, origin)
        direct, _ = self.connect()
        client.send(message="through-preview")
        self.assertEqual(client.event(), direct.event())
        sse, _ = self.connect_sse(port)
        body = urlencode({
            "author": "Preview", "message": "sse-through-preview",
            "requestId": "preview-sse-1",
        })
        post = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        post.request(
            "POST", "/chat-sse/send", body=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Origin": origin,
            },
        )
        response = post.getresponse()
        self.assertEqual(response.status, 202)
        response.read()
        post.close()
        self.assertEqual(json.loads(sse.event()["data"])["message"], "sse-through-preview")
        post = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
        post.request(
            "POST", "/chat-sse/send", body=body,
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
                "Origin": "http://evil.invalid",
            },
        )
        self.assertEqual(post.getresponse().status, 403)
        post.close()
        pong = WebSocket(port, origin, "/pong/socket", "leanwebstudy-pong")
        self.addCleanup(pong.close)
        self.assertEqual(pong.event(), {"type": "welcome", "player": 1})
        self.assertEqual(pong.event(), {"type": "players", "count": 1})
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
        try:
            connection.request("GET", self.page_path)
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertIn(b'<meta name="leanwebstudy-chat-port" content="">', response.read())
        finally:
            connection.close()
        with self.assertRaises((ConnectionError, OSError)):
            WebSocket(port, "http://evil.invalid", self.socket_path)
        development.shutdown.set()
        with self.assertRaises(ConnectionError):
            client.read(1)


class WsLeanChatTests(ChatTests):
    page_path = "/chat-ws/"
    socket_path = "/chat-ws/socket"
    test_pong_roles_validation_broadcast_and_disconnect_presence = None
    test_sse_chat_history_post_broadcast_and_validation = None

    def test_idle_ping_pong_timeout_and_incomplete_upgrade_deadline(self):
        responsive, _ = self.connect()
        silent, _ = self.connect()
        incomplete = socket.create_connection(("127.0.0.1", self.port), timeout=3)
        self.addCleanup(incomplete.close)
        incomplete.sendall(b"GET /chat-ws/socket HTTP/1.1\r\n")
        responsive.socket.settimeout(35)
        silent.socket.settimeout(35)
        incomplete.settimeout(12)
        self.assertEqual(incomplete.recv(1), b"")
        opcode, payload = responsive.frame()
        self.assertEqual(opcode, 9)
        responsive.send_frame(payload, opcode=10)
        responsive.send(message="alive-after-ping")
        self.assertEqual(responsive.event()["message"], "alive-after-ping")
        self.assertEqual(silent.frame()[0], 9)
        self.assertEqual(silent.event()["message"], "alive-after-ping")
        opcode, payload = silent.frame()
        self.assertEqual(opcode, 8)
        self.assertEqual(struct.unpack("!H", payload[:2])[0], 1001)
        responsive.send(message="still-responsive")
        self.assertEqual(responsive.event()["message"], "still-responsive")

    def test_large_history_and_concurrent_publisher_order(self):
        first, _ = self.connect()
        for index in range(50):
            first.send(message="界" * 499 + str(index % 10))
            self.assertEqual(first.event()["type"], "message")
        second, history = self.connect()
        self.assertEqual(len(history), 50)
        self.assertGreater(len(json.dumps(history, ensure_ascii=False).encode()), 8192)
        failures = []

        def publish(client, name):
            try:
                for index in range(15):
                    client.send(author=name, message=f"concurrent-{index}")
            except BaseException as error:
                failures.append(error)

        threads = [threading.Thread(target=publish, args=(first, "first")),
                   threading.Thread(target=publish, args=(second, "second"))]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=5)
            self.assertFalse(thread.is_alive())
        self.assertEqual(failures, [])
        received = [first.event() for _ in range(30)]
        self.assertEqual([second.event() for _ in range(30)], received)
        ids = [entry["id"] for entry in received]
        self.assertEqual(ids, list(range(ids[0], ids[0] + 30)))

    def test_upgrade_preserves_initial_frame_and_close_ignores_trailing_data(self):
        observer, _ = self.connect()
        request = json.dumps({"type": "message", "author": "Ada",
                              "message": "coalesced", "requestId": "initial"}).encode()
        client = WebSocket(self.port, self.origin, self.socket_path,
                           initial_bytes=WebSocket.frame_bytes(request))
        self.addCleanup(client.close)
        self.assertEqual(client.event()["type"], "history")
        self.assertEqual(client.event(), observer.event())
        before_close = json.loads(request)
        before_close["message"] = "before-close"
        after_close = {**before_close, "message": "must-not-be-published"}
        client.socket.sendall(
            WebSocket.frame_bytes(json.dumps(before_close).encode()) +
            WebSocket.frame_bytes(struct.pack("!H", 1000), opcode=8) +
            WebSocket.frame_bytes(json.dumps(after_close).encode()))
        self.assertEqual(client.frame()[0], 8)
        self.assertEqual(observer.event()["message"], "before-close")
        observer.send(message="after-peer-close")
        self.assertEqual(observer.event()["message"], "after-peer-close")

    def test_independent_history_and_broadcast(self):
        client, _ = self.connect()
        status, data = self.request("/chat/endpoint")
        self.assertEqual(status, 200)
        other = WebSocket(json.loads(data)["port"], self.origin)
        self.addCleanup(other.close)
        other.event()
        client.send(message="ws-lean-only")
        other.send(message="libwebsockets-only")
        self.assertEqual(client.event()["message"], "ws-lean-only")
        self.assertEqual(other.event()["message"], "libwebsockets-only")
        _, history = self.connect()
        self.assertEqual(history[-1]["message"], "ws-lean-only")
        self.assertNotIn("libwebsockets-only", [entry["message"] for entry in history])


if __name__ == "__main__":
    unittest.main()
