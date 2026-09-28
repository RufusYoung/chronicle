"""Legal, bounded adventure routes without farming; preserves full protocol evidence."""

import argparse
import json
import os
from pathlib import Path
import time

from agent_play import ChronicleClient
from verify_journey_package import TRUTH, SAVES


def play(output, packaged, seed, policy):
    trace = []
    sales = 0
    name = f"{seed}_{policy}_{'package' if packaged else 'source'}"
    diagnostic = output / (name + ".attempt.jsonl")
    with ChronicleClient(packaged=packaged, timeout=90) as game:
        def request(command, **arguments):
            result = game.request(command, **arguments)
            trace.append({"command": command, "arguments": arguments, "response": result})
            with diagnostic.open("a", encoding="utf-8") as log:
                log.write(json.dumps(trace[-1], ensure_ascii=False) + "\n")
            assert result.get("ok"), result
            return result

        state = request("start", mode="play", scenario="echo_realm", seed=seed,
                        economy_variant="world_adventure_v3")

        def act(choice_id):
            nonlocal state
            assert any(c["choice_id"] == choice_id and c["enabled"] for c in state["choices"]), choice_id
            state = request("act", choice_id=choice_id)

        def take(identifier):
            act(next(c["choice_id"] for c in state["choices"] if c["id"] == identifier and c["enabled"]))

        def ready_meal():
            if state["observation"]["player"]["hunger"] in ("medium", "high", "extreme"):
                choices = [c for c in state["choices"] if c["id"].startswith("eat") and c["enabled"]]
                if choices:
                    act(max(choices, key=lambda c: c.get("satiation_hours", 0))["choice_id"])

        def sell_and_ask():
            nonlocal sales
            for _ in range(4):
                offers = [c for c in state["choices"] if c["id"].startswith("sell_food:") and c["enabled"]]
                if not offers:
                    break
                before = state["observation"]["player"]["coins"]
                act(offers[0]["choice_id"])
                assert state["observation"]["player"]["coins"] > before
                assert "收到" in state["observation"]["feedback"]["title"]
                sales += 1
            talk = next((c for c in state["choices"] if c["id"].startswith("ask_local:") and c["enabled"]), None)
            if talk:
                act(talk["choice_id"])
                assert not any(c["id"].startswith("ask_local:") for c in state["choices"])

        if policy == "cave":
            take("generated_route.echo_landing.commons_to_fishery")
            take("adventure:shore_box:hook")
            take("journey_route.generated_location.echo_landing.landing.journey_location.lake_cave")
            take("adventure:cave_marks:read")
            safe = next(c for c in state["choices"] if c["id"] == "adventure:cave_bundle:ledge")
            take(safe["id"] if safe["enabled"] else "adventure:cave_bundle:rope")
            take("journey_route.journey_location.lake_cave.generated_location.echo_landing.landing")
            sell_and_ask()
            ready_meal()
            take("generated_route.echo_landing.fishery_to_commons")
        else:
            take("generated_route.echo_landing.commons_to_watch_service")
            take("adventure:beacon_marks:study")
            take("journey_route.generated_location.echo_landing.watch_post.journey_location.old_beacon")
            take("adventure:beacon_climb:known")
            take("adventure:beacon_view:remember")
            take("journey_route.journey_location.old_beacon.generated_location.echo_landing.watch_post")
            ready_meal()
            take("generated_route.echo_landing.watch_service_to_commons")
        take("generated_route.echo_landing.commons_to_road_carting")
        take("adventure:road_cord:collect")
        sell_and_ask()
        ready_meal()
        take("generated_route.echo_landing.road_carting_to_commons")
        take(next(c["id"] for c in state["choices"] if c["kind"] == "travel" and "客舍" in c["label"]))
        for _ in range(6):
            wanted = next((c for c in state["choices"] if c["id"] == "adventure:return_cord:return" and c["enabled"]), None)
            if wanted:
                take(wanted["id"])
                break
            ready_meal()
            take("rest")
        else:
            raise AssertionError("No funded host within a bounded six-hour visit")
        sell_and_ask()
        ready_meal()
        night = next((c for c in state["choices"] if c["id"] == "adventure:night_talk:listen" and c["enabled"]), None)
        if night:
            take(night["id"])
        assert sales > 0, "No sale along the actual adventure route"
        assert not any(t.get("arguments", {}).get("choice_id", "").startswith(("player_life/gather:", "player_life/work:", "player_life/help:")) for t in trace)
        assert state["observation"]["player"]["health"] > 40
        slot = f"experience_{seed}_{policy}_{int(packaged)}_{os.getpid()}"
        request("save", slot=slot)
        native = json.loads((SAVES / (slot + ".json")).read_text(encoding="utf-8"))
        assert request("load", slot=slot)["observation"] == state["observation"]
        # Same next legal action after restore also exercises the persisted minute remainder.
        take("rest")
        request("save", slot=slot, overwrite=True)
        continued = json.loads((SAVES / (slot + ".json")).read_text(encoding="utf-8"))
    (output / (name + ".trace.json")).write_text(json.dumps(trace, ensure_ascii=False), encoding="utf-8")
    (output / (name + ".native.json")).write_text(json.dumps(native, ensure_ascii=False), encoding="utf-8")
    summary = {"seed": seed, "policy": policy, "sales": sales, "actions": sum(t["command"] == "act" for t in trace),
               "hours": state["observation"]["time"]["elapsed_hours"], "food": state["observation"]["player"]["food_count"],
               "coins": state["observation"]["player"]["coins"], "health": state["observation"]["player"]["health"]}
    return continued, summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    began = time.monotonic()
    for seed, policy in ((81001, "cave"), (89037, "beacon")):
        source, summary = play(args.output, False, seed, policy)
        if not args.source_only:
            package, _ = play(args.output, True, seed, policy)
            for key in TRUTH:
                assert source[key] == package[key], (seed, policy, key)
        results.append(summary)
        print(summary, flush=True)
    (args.output / "result.json").write_text(json.dumps({"passed": True, "source_only": args.source_only,
        "seconds": time.monotonic() - began, "cases": results,
        "scope": "Scripted legal agent play, not human fun or an RF6 acceptance verdict."}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
