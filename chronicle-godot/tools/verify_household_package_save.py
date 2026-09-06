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
    args = parser.parse_args()
    content = args.checkpoint.resolve(strict=True).read_bytes()
    envelope = json.loads(content)
    expected_hours = envelope["world_time"]["elapsed_hours"]
    if expected_hours != 720 or not envelope["bootstrap"]["fixture_data"]["resident_daily_life"]["food_access"].get("subsistence"):
        raise ValueError("Expected a native integrated thirty-day checkpoint")
    # This is the test-only path selected by world_bootstrap.gd, never the manual player save.
    isolated = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CHRONICLE_GODOT/tests/world_runtime_probe/day7.json"
    original = isolated.read_bytes() if isolated.exists() else None
    isolated.parent.mkdir(parents=True, exist_ok=True)
    try:
        isolated.write_bytes(content)
        sample = measure(args.executable.resolve(strict=True), "day7")
        if sample["elapsed_hours"] != expected_hours or not sample["save_exists"]:
            raise AssertionError("The packaged UI did not load the supplied thirty-day world")
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
        "scope": "Actual packaged renderer loads a thirty-day native world with enabled controls. The existing probe label 'day7' means a minimum age, not this world's age. Read-only UI check; no UI wait or human play in this probe. Original test checkpoint restored byte-for-byte."
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"HOUSEHOLD_PACKAGED_SAVE_RESULT PASS: {expected_hours} hours, {sample['process_to_frame_ms']:.2f} ms to frame")


if __name__ == "__main__":
    main()
