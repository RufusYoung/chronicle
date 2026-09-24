"""Replay legal short-adventure choices in source/package; compare native world truth."""

import argparse
import json
import os
from pathlib import Path
import time

from agent_play import ChronicleClient

TRUTH = ("bootstrap", "definition_manifest", "stores", "session", "world_time", "rng_states", "world_log")
SAVES = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CHRONICLE_GODOT/agent_play/play/echo_realm"


def play(output, packaged, policy, seed):
    trace = []
    with ChronicleClient(packaged=packaged, timeout=90) as game:
        def request(command, **arguments):
            result = game.request(command, **arguments)
            trace.append({"command": command, "arguments": arguments, "response": result})
            if not result.get("ok"):
                raise AssertionError(result)
            return result

        state = request("start", mode="play", scenario="echo_realm", seed=seed,
                        economy_variant="world_adventure_v2")

        def act(choice_id):
            nonlocal state
            assert any(c["choice_id"] == choice_id and c["enabled"] for c in state["choices"]), choice_id
            state = request("act", choice_id=choice_id)

        act("travel/generated_route.echo_landing.commons_to_fishery")
        act("player_life/adventure:shore_box:" + ("reach" if policy == "risk" else "hook"))
        if policy == "risk":
            feedback = json.dumps(state["observation"]["feedback"], ensure_ascii=False)
            assert "掷骰" in feedback
            assert not any(c["id"].startswith("adventure:shore_box:") for c in state["choices"])
        elif policy == "cave":
            act("travel/journey_route.generated_location.echo_landing.landing.journey_location.lake_cave")
            act("player_life/adventure:cave_marks:skip")
            act("player_life/adventure:cave_bundle:rope")
            assert "磨损1" in json.dumps(state["observation"]["feedback"], ensure_ascii=False)
        else:
            act("travel/generated_route.echo_landing.fishery_to_commons")
            route = next(c for c in state["choices"] if c["kind"] == "travel" and "车" in c["label"])
            act(route["choice_id"])
            act("player_life/adventure:road_cord:collect")
            route = next(c for c in state["choices"] if c["kind"] == "travel" and c["id"].endswith("_to_commons"))
            act(route["choice_id"])
            route = next(c for c in state["choices"] if c["kind"] == "travel" and "客舍" in c["label"])
            act(route["choice_id"])
            for _ in range(24):
                choice = next((c for c in state["choices"] if c["id"] == "adventure:return_cord:return" and c["enabled"]), None)
                if choice:
                    act(choice["choice_id"])
                    break
                act(next(c["choice_id"] for c in state["choices"] if c["kind"] == "wait" and c["enabled"]))
            else:
                raise AssertionError("No physical, funded host met within 24 hours")
            for _ in range(24):
                choice = next((c for c in state["choices"] if c["id"] == "adventure:night_talk:listen" and c["enabled"]), None)
                if choice:
                    act(choice["choice_id"])
                    break
                act(next(c["choice_id"] for c in state["choices"] if c["kind"] == "wait" and c["enabled"]))
            else:
                raise AssertionError("No night conversation within 24 hours")
            act("player_life/service:drink")
            assert "2铜币" in json.dumps(state["observation"]["feedback"], ensure_ascii=False)

        slot = f"journey_parity_{policy}_{seed}_{int(packaged)}_{time.time_ns()}"
        request("save", slot=slot)
        native = json.loads((SAVES / (slot + ".json")).read_text(encoding="utf-8"))
        assert request("load", slot=slot)["observation"] == state["observation"]
    name = f"{policy}_{seed}_{'package' if packaged else 'source'}"
    (output / (name + ".trace.json")).write_text(json.dumps(trace, ensure_ascii=False), encoding="utf-8")
    (output / (name + ".native.json")).write_text(json.dumps(native, ensure_ascii=False), encoding="utf-8")
    return native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    cases = []
    for seed, policy in ((81001, "risk"), (89037, "cave"), (81001, "night")):
        source = play(args.output, False, policy, seed)
        if not args.source_only:
            package = play(args.output, True, policy, seed)
            for key in TRUTH:
                assert source[key] == package[key], (seed, policy, key)
        cases.append({"seed": seed, "policy": policy, "passed": True,
                      "game_hours": source["world_time"]["elapsed_hours"]})
        print(seed, policy, "PASS", flush=True)
    report = {"passed": True, "cases": cases, "source_only": args.source_only,
              "scope": "Scripted legal public choices, no injected state/dice, not human play or a fun verdict.",
              "truth_keys": [] if args.source_only else list(TRUTH)}
    (args.output / "result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
