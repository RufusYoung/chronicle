"""Measure new-process launch through the packaged, rendered ready-frame marker."""

import argparse
import json
from pathlib import Path
import queue
import subprocess
import threading
import time


def measure(executable, profile):
    args = [str(executable), "--rendering-method", "gl_compatibility", "--", "--startup-probe"]
    if profile == "day7":
        args.append("--startup-probe-day7")
    began = time.perf_counter()
    process = subprocess.Popen(args, cwd=executable.parent, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    lines = queue.Queue()

    def read_output():
        for line in iter(process.stdout.readline, b""):
            lines.put((time.perf_counter(), line.decode("utf-8", errors="replace").rstrip()))
        lines.put((time.perf_counter(), None))

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    output = []
    sample = None
    try:
        while True:
            remaining = 30 - (time.perf_counter() - began)
            if remaining <= 0:
                raise TimeoutError("No controllable rendered frame within 30 seconds")
            arrived, line = lines.get(timeout=remaining)
            if line is None:
                break
            output.append(line)
            if line.startswith("CHRONICLE_FIRST_CONTROLLABLE_FRAME "):
                sample = json.loads(line.split(" ", 1)[1])
                sample["process_to_frame_ms"] = (arrived - began) * 1000
        process.wait(timeout=5)
        if process.returncode or not sample or not sample.get("ok"):
            raise RuntimeError("Startup probe failed: " + "\n".join(output))
        if any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in output):
            raise RuntimeError("Engine errors: " + "\n".join(output))
        sample["output"] = output
        return sample
    finally:
        if process.poll() is None:
            process.kill()
            process.wait(timeout=5)
        reader.join(timeout=5)
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3, choices=range(1, 11))
    options = parser.parse_args()
    rows = []
    for profile in ("initial", "day7"):
        for _ in range(options.runs):
            sample = measure(options.executable.resolve(strict=True), profile)
            rows.append(sample)
            print(f"{profile}: {sample['process_to_frame_ms']:.2f} ms", flush=True)
    passed = all(row["process_to_frame_ms"] <= 10000 for row in rows)
    options.output.parent.mkdir(parents=True, exist_ok=True)
    options.output.write_text(json.dumps({"passed": passed, "rows": rows,
        "scope": "Fresh process through actual first drawn, enabled UI; OS file/shader caches not flushed. Same development machine, not clean-machine acceptance."},
        ensure_ascii=False, indent=2), encoding="utf-8")
    print("WINDOWS_STARTUP_RESULT " + ("PASS" if passed else "FAIL"))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
