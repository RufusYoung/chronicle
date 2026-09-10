"""Bounded legal agent play of world danger; no state edits or roll overrides."""

import argparse
import json
from pathlib import Path

from agent_play import ChronicleClient


def play(*, packaged=False, seed=81001, tactic="withdraw", hours=72):
    if not 24 <= hours <= 168:
        raise ValueError("Comparison horizon must be 24..168 elapsed hours")
    transcript = []
    with ChronicleClient(packaged=packaged) as game:
        def request(operation, **payload):
            response = game.request(operation, **payload)
            transcript.append({"request": {"op": operation, **payload}, "response": response})
            if not response.get("ok"):
                raise RuntimeError(json.dumps(response, ensure_ascii=False))
            return response

        response = request("start", mode="play", scenario="echo_realm", seed=seed,
                           economy_variant="world_danger_v1")
        for route_hint in (".network.", "commons_to_terrace_farming"):
            choice = next(c for c in response["choices"] if c["kind"] == "travel" and route_hint in c["id"])
            response = request("act", choice_id=choice["choice_id"])
        assert response["observation"]["risk"]["active"], "Expected a present territorial threat"
        start_hour = response["observation"]["time"]["elapsed_hours"]
        # Deliberately risky legal play tests an actual failure/recovery route, not injected damage.
        steps = ["attack", "withdraw"] if tactic == "withdraw" else ["guard", "guard", "attack", "guard", "attack"]
        rounds = 0
        for approach in steps:
            matches = [c for c in response["choices"] if c["kind"] == "combat_encounter" and c["id"].endswith(":" + approach)]
            if not matches:
                break
            response = request("act", choice_id=matches[0]["choice_id"])
            rounds += 1
            if rounds == 1:
                slot = "world_danger_legal_" + tactic
                request("save", slot=slot, overwrite=True)
                response = request("load", slot=slot)
        assert rounds >= 2, "Must exercise continuous combat, not one encounter roll"
        assert response["observation"]["time"]["elapsed_hours"] >= start_hour + rounds
        for _ in range(6):
            choices = [c for c in response["choices"] if c["kind"] == "combat_encounter" and c["id"].endswith(":withdraw")]
            if not choices:
                break
            response = request("act", choice_id=choices[0]["choice_id"])
        exits = [c for c in response["choices"] if c["kind"] == "travel" and c["enabled"]]
        assert exits, "Combat exit must restore real travel choices"
        injured = response["observation"]["player"]["injury"]
        response = request("act", choice_id=exits[0]["choice_id"])
        rested = 0
        if tactic == "withdraw":
            assert injured == "combat_bruising", "Risky legal action should demonstrate persistent injury"
            for _ in range(12):
                choice = next(c for c in response["choices"] if c["kind"] == "recovery" and c["enabled"])
                response = request("act", choice_id=choice["choice_id"])
                rested += 1
            assert response["observation"]["player"]["injury"] == "none", "Twelve real recovery hours should heal the bruise"
            assert response["observation"]["player"]["food_count"] == 0, "Recovery consumes finite starting rations"

        # Align both legal policies at the same elapsed world hour for read-only causal audit.
        while response["observation"]["time"]["elapsed_hours"] < hours:
            choice = next(c for c in response["choices"] if c["kind"] == "wait")
            response = request("act", choice_id=choice["choice_id"])
        request("save", slot="world_danger_outcome_" + tactic, overwrite=True)
        return {"evidence_kind": "legal_code_agent_play", "human_ui_play": False, "test_injection": False,
                "seed": seed, "tactic": tactic, "rounds": rounds, "rest_hours": rested,
                "final_player": response["observation"]["player"], "final_time": response["observation"]["time"],
                "transcript": transcript}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--seed", type=int, default=81001)
    parser.add_argument("--hours", type=int, default=72)
    parser.add_argument("--tactic", choices=["withdraw", "guard_attack"], default="withdraw")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = play(packaged=args.packaged, seed=args.seed, tactic=args.tactic, hours=args.hours)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k != "transcript"}, ensure_ascii=False))
