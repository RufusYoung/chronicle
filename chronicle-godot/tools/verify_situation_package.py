"""Compare source and Windows package by playing the same natural continuity save."""

import argparse
import hashlib
import json
import os
from pathlib import Path

from agent_play import ChronicleClient, PROJECT


SAVE_ROOT = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CHRONICLE_GODOT/agent_play/play/echo_realm"
TRUTH_KEYS = ("stores", "session", "world_time", "rng_states", "world_log", "bootstrap", "definition_manifest")


def play(packaged: bool, source_slot: str, binary: str | None) -> dict:
    trace = []
    with ChronicleClient(packaged=packaged, godot=binary if packaged else None, timeout=120) as game:
        def request(command, **fields):
            result = game.request(command, **fields)
            if not result.get("ok"):
                raise AssertionError(result)
            return result

        request("start", mode="play", scenario="echo_realm", seed=81001,
                economy_variant="world_situation_v2")
        current = request("load", slot=source_slot)
        observations = [current["observation"]]

        def act(choice):
            nonlocal current
            current = request("act", choice_id=choice["choice_id"], confirm=True)
            trace.append({"choice_id": choice["choice_id"], "label": choice["label"],
                          "time": current["observation"]["time"],
                          "feedback": current["observation"]["feedback"]})
            observations.append(current["observation"])

        gift = next(c for c in current["choices"]
                    if c.get("intent") == "give" and c.get("clear_slots") and c["enabled"])
        subject = gift["subject_id"]
        act(gift)
        assert "防护" in current["observation"]["feedback"]["body"]
        heard = False
        for _ in range(12):
            choices = [c for c in current["choices"] if c["enabled"]]
            update = next((c for c in choices if c.get("intent") == "aftermath"
                           and c["subject_id"] == subject), None)
            if update:
                act(update)
                heard = True
                break
            follow = next((c for c in choices if c.get("intent") == "follow"
                           and c["subject_id"] == subject), None)
            wait = next((c for c in choices if c.get("intent") == "wait" and c["minutes"] == 60), None)
            assert follow or wait, "No legal route to the next observation"
            act(follow or wait)
        assert heard, "No personally known follow-up reached"
        assert "穿戴" in current["observation"]["feedback"]["body"]
        slot = "situation_verified_package" if packaged else "situation_verified_source"
        request("save", slot=slot, overwrite=True)
        native = json.loads((SAVE_ROOT / f"{slot}.json").read_text(encoding="utf-8"))
        assert request("load", slot=slot)["observation"] == current["observation"]
        if packaged:
            request("save", slot="situation_startup_continued", overwrite=True)
        return {"trace": trace, "observations": observations,
                "native": {key: native[key] for key in TRUTH_KEYS}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-slot", default="situation_interest_v2_81001")
    parser.add_argument("--binary", default=str(PROJECT.parent / "builds/h1-windows/Chronicle.exe"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source_path = SAVE_ROOT / f"{args.source_slot}.json"
    envelope = json.loads(source_path.read_text(encoding="utf-8"))
    assert not any(f.get("fact_type") == "test_injection" for f in envelope["stores"]["facts"])
    source = play(False, args.source_slot, None)
    package = play(True, args.source_slot, args.binary)
    assert source == package, "Public observations or complete native truth differ between source and package"
    result = {"ok": True, "evidence_kind": "legal_code_agent_not_human_play",
              "source_slot": args.source_slot, "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
              "steps": len(source["trace"]), "compared_native_keys": TRUTH_KEYS,
              "trace": source["trace"], "manual_saves_modified": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"ok": True, "steps": result["steps"], "evidence": str(args.output)}))


if __name__ == "__main__":
    main()
