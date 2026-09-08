"""Render a long native checkpoint using the package's existing isolated startup probe."""

import argparse
import hashlib
import json
import os
from pathlib import Path

from profile_windows_startup import measure


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-hours", type=int, default=720)
    parser.add_argument("--expected-work-version", type=int, default=0)
    args = parser.parse_args()
    content = args.checkpoint.resolve(strict=True).read_bytes()
    envelope = json.loads(content)
    expected_hours = envelope["world_time"]["elapsed_hours"]
    fixture = envelope["bootstrap"]["fixture_data"]
    if expected_hours != args.expected_hours or expected_hours < 168 or not fixture["resident_daily_life"]["food_access"].get("subsistence"):
        raise ValueError("Expected a native integrated checkpoint of the specified age (at least seven days)")
    if args.expected_work_version and fixture.get("work_rules", {}).get("version") != args.expected_work_version:
        raise ValueError("Checkpoint does not contain the requested work rules")
    # This is the test-only path selected by world_bootstrap.gd, never the manual player save.
    isolated = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CHRONICLE_GODOT/tests/world_runtime_probe/day7.json"
    original = isolated.read_bytes() if isolated.exists() else None
    isolated.parent.mkdir(parents=True, exist_ok=True)
    try:
        isolated.write_bytes(content)
        sample = measure(args.executable.resolve(strict=True), "day7")
        if sample["elapsed_hours"] != expected_hours or not sample["save_exists"]:
            raise AssertionError("The packaged UI did not load the supplied native world")
    finally:
        if original is None:
            isolated.unlink(missing_ok=True)
        else:
            isolated.write_bytes(original)
    report = {
        "passed": bool(sample["ok"]),
        "checkpoint_sha256": hashlib.sha256(content).hexdigest(),
        "checkpoint": str(args.checkpoint),
        "sample": sample,
        "scope": "Actual packaged renderer loads the specified native world with enabled controls. The existing probe label 'day7' means a minimum age, not this world's age. Read-only UI check; no UI wait or human play in this probe. Original test checkpoint restored byte-for-byte."
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"HOUSEHOLD_PACKAGED_SAVE_RESULT PASS: {expected_hours} hours, {sample['process_to_frame_ms']:.2f} ms to frame")


if __name__ == "__main__":
    main()
