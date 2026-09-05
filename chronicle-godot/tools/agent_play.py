"""Persistent, screen-free Chronicle client using only the Python standard library."""

from __future__ import annotations

import argparse
from collections import deque
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import sys
import threading
import uuid


PREFIX = b"CHRONICLE_AGENT_JSON\t"
PROJECT = Path(__file__).resolve().parents[1]


def find_godot() -> str:
    configured = os.environ.get("CHRONICLE_GODOT")
    if configured:
        return configured
    for name in ("Godot_v4.6.3-stable_win64_console.exe", "godot", "godot4"):
        found = shutil.which(name)
        if found:
            return found
    raise FileNotFoundError("Set CHRONICLE_GODOT to a Godot 4.6 console executable.")


class ChronicleClient:
    """One process, one ordered caller. A timeout closes the session, never retries."""

    def __init__(self, *, godot: str | None = None, timeout: float = 120.0, packaged: bool = False):
        self.timeout = timeout
        self.messages: queue.Queue[dict | None] = queue.Queue()
        self.diagnostics: deque[str] = deque(maxlen=40)
        self.session_id = ""
        self.revision = 0
        binary = godot or find_godot()
        if packaged:
            binary = shutil.which(binary) or str(Path(binary).resolve())
        command = [binary, "--headless"]
        command += (["--", "--agent-stdio"] if packaged else
                    ["--path", str(PROJECT), "--script", "res://scripts/agent/agent_stdio_runner.gd"])
        self.process = subprocess.Popen(
            command,
            cwd=str(Path(binary).resolve().parent) if packaged else None,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        self.readers = [
            threading.Thread(target=self._read_output, daemon=True),
            threading.Thread(target=self._read_errors, daemon=True),
        ]
        for reader in self.readers:
            reader.start()
        try:
            hello = self._receive()
            if hello.get("event") != "hello":
                raise RuntimeError(f"Unexpected handshake: {hello}")
            self.session_id = hello["session"]["session_id"]
            self.revision = hello["session"]["revision"]
        except BaseException:
            self.close()
            raise

    def _read_output(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            if line.startswith(PREFIX):
                try:
                    self.messages.put(json.loads(line[len(PREFIX):]))
                except (ValueError, UnicodeError) as error:
                    self.diagnostics.append(str(error))
                    break
            else:
                self.diagnostics.append(line.decode("utf-8", errors="replace").rstrip())
        self.messages.put(None)

    def _read_errors(self) -> None:
        assert self.process.stderr is not None
        for line in self.process.stderr:
            self.diagnostics.append(line.decode("utf-8", errors="replace").rstrip())

    def _receive(self) -> dict:
        try:
            message = self.messages.get(timeout=self.timeout)
        except queue.Empty as error:
            self.close()
            raise TimeoutError("Godot reply timed out; outcome unknown. Do not replay a mutation in a new session.") from error
        if message is None:
            self.close()
            raise RuntimeError("Godot closed its output:\n" + "\n".join(self.diagnostics))
        return message

    def send(self, request: dict) -> dict:
        """Send a fully specified request, including an old request for dedup testing."""
        payload = json.dumps(request, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
        if not 1 <= len(payload) <= 65536:
            raise ValueError("Request must fit in 1..65536 UTF-8 bytes")
        if self.process.poll() is not None:
            raise RuntimeError("Godot process is no longer running")
        assert self.process.stdin is not None
        try:
            self.process.stdin.write(f"{len(payload):08d}".encode("ascii") + payload)
            self.process.stdin.flush()
            result = self._receive()
        except BaseException:
            self.close()
            raise
        # A cached old receipt must not rewind the client's current control revision.
        self.revision = max(self.revision, result.get("revision", self.revision))
        return result

    def request(self, command: str, **arguments) -> dict:
        payload = {"protocol": 1, "command": command, "request_id": str(uuid.uuid4()),
                   "session_id": self.session_id, "expected_revision": self.revision}
        payload.update(arguments)
        return self.send(payload)

    def close(self) -> None:
        if self.process.stdin is not None and not self.process.stdin.closed:
            try:
                self.process.stdin.close()
            except OSError:
                pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            if os.name == "nt":
                # The Godot console executable may be a wrapper with an engine child.
                subprocess.run(["taskkill", "/PID", str(self.process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                               timeout=10, check=False)
            else:
                self.process.kill()
            self.process.wait(timeout=5)
        for reader in self.readers:
            if reader is not threading.current_thread():
                reader.join(timeout=2)
        for pipe in (self.process.stdout, self.process.stderr):
            if pipe is not None:
                pipe.close()

    def __enter__(self) -> ChronicleClient:
        return self

    def __exit__(self, *_exc) -> None:
        self.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--packaged", action="store_true", help="Use an exported Chronicle executable via its built-in agent entry.")
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    with ChronicleClient(godot=args.godot, timeout=args.timeout, packaged=args.packaged) as game:
        print(json.dumps({"event": "client_ready", "session_id": game.session_id}, ensure_ascii=False), flush=True)
        for line in sys.stdin:
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or "command" not in request:
                    raise ValueError("Provide a JSON object with command")
                command = request.pop("command")
                response = game.request(command, **request)
            except (ValueError, TypeError) as error:
                response = {"ok": False, "client_error": str(error)}
            print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
