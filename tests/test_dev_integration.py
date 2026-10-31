import http.client
import json
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import unittest


class DevelopmentIntegrationTests(unittest.TestCase):
    def test_real_build_page_fixture_failure_recovery_and_shutdown(self):
        repository = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="leanwebstudy-watch-test-") as directory:
            root = Path(directory)
            for name in (
                "LeanWebStudy.lean", "Main.lean", "lakefile.lean",
                "lake-manifest.json", "lean-toolchain",
            ):
                shutil.copy2(repository / name, root / name)
            for name in ("LeanWebStudy", "Pages", "native", "tools"):
                shutil.copytree(repository / name, root / name, ignore=shutil.ignore_patterns("__pycache__"))
            (root / ".lake").mkdir()
            (root / ".lake/packages").symlink_to(repository / ".lake/packages", target_is_directory=True)
            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            with (root / "watcher.log").open("w+") as log:
                process = subprocess.Popen(
                    ["python3", str(root / "tools/dev.py"), "--port", str(port)],
                    stdout=log, stderr=subprocess.STDOUT,
                )

                def request(path):
                    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
                    try:
                        connection.request("GET", path)
                        response = connection.getresponse()
                        return response.status, response.read().decode()
                    finally:
                        connection.close()

                def wait_for(phase, revision):
                    deadline = time.monotonic() + 120
                    saw_progress = False
                    while time.monotonic() < deadline:
                        self.assertIsNone(process.poll(), "Watcher exited prematurely")
                        try:
                            code, body = request("/__dev/status")
                            state = json.loads(body)
                        except (OSError, http.client.HTTPException):
                            time.sleep(0.1)
                            continue
                        if state["phase"] == phase and state["revision"] == revision:
                            return state
                        saw_progress = saw_progress or state["phase"] in {"building", "starting"}
                        if phase == "ready" and state["phase"] == "error" and saw_progress:
                            self.fail(state["message"])
                        time.sleep(0.1)
                    self.fail(f"Timed out waiting for {phase} revision {revision}")

                try:
                    wait_for("ready", 1)
                    self.assertIn("user-2@example.invalid", request("/sqlite/users")[1])

                    page = root / "Pages/sqlite/users.lean"
                    original = page.read_text()
                    page.write_text(original.replace("SQLite users", "saved-v2"))
                    wait_for("ready", 2)
                    self.assertIn("saved-v2", request("/sqlite/users")[1])

                    fixture = root / "LeanWebStudy/SampleData.lean"
                    fixture.write_text(fixture.read_text().replace(
                        "user-{id}@example.invalid", "updated-{id}@example.invalid"
                    ))
                    wait_for("ready", 3)
                    body = request("/sqlite/users")[1]
                    self.assertIn("updated-2@example.invalid", body)
                    self.assertNotIn("user-2@example.invalid", body)

                    page.write_text("invalid Lean source\n")
                    failure = wait_for("error", 3)
                    self.assertIn("lean", failure["message"])
                    self.assertEqual(request("/sqlite/users")[0], 503)
                    page.write_text(original.replace("SQLite users", "recovered"))
                    wait_for("ready", 4)
                    self.assertIn("recovered", request("/sqlite/users")[1])

                    # Rapid saves collapse into a single successful revision.
                    for label in ("rapid-1", "rapid-2", "rapid-final"):
                        page.write_text(original.replace("SQLite users", label))
                        time.sleep(0.03)
                    wait_for("ready", 5)
                    self.assertIn("rapid-final", request("/sqlite/users")[1])

                    added = root / "Pages/new.lean"
                    added.write_text(
                        'import LeanWebStudy.Page\n'
                        'def main : IO Unit := LeanWebStudy.Page.run fun _ => pure "<p>added</p>"\n'
                    )
                    wait_for("ready", 6)
                    self.assertIn("<p>added</p>", request("/new")[1])
                    added.unlink()
                    wait_for("ready", 7)
                    code, body = request("/new")
                    self.assertEqual(code, 404)
                    self.assertIn("location.reload()", body)
                finally:
                    process.send_signal(signal.SIGTERM)
                    try:
                        process.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                        self.fail("Watcher failed to cleanly shut down")
                    log.seek(0)
                    output = log.read()
                    if process.returncode != 0:
                        print(output)
                    else:
                        print("\n".join(
                            line for line in output.splitlines() if line.startswith("[dev]")
                        ))
                self.assertEqual(process.returncode, 0)
                with self.assertRaises(OSError):
                    request("/__dev/status")


if __name__ == "__main__":
    unittest.main()
