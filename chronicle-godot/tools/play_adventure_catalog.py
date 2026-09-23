"""Bounded legal acquisition audit, not autonomous NPC or human-play evidence."""

import argparse
import json
import os
from pathlib import Path
import time

from agent_play import ChronicleClient


RECIPES = {
    "reed_quarterstaff": "reed_quarterstaff",
    "woven_sap": "woven_sap",
    "reed_buckler": "reed_buckler",
    "light_reed_mantle": "light_reed_mantle",
    "knotted_fiber_whip": "knotted_whip",
    "woven_reed_vest": "reed_vest",
    "rescue_harness": "rescue_harness",
    "casting_snare": "casting_snare",
    "trail_sandals": "trail_sandals",
    "braced_reed_sleeve": "braced_reed_sleeve",
    "bound_reed_pike": "bound_reed_pike",
    "layered_reed_cuirass": "layered_reed_cuirass",
}


class CatalogPolicy:
    def __init__(self):
        self.refueling = True

    def choose(self, response):
        view = response["observation"]
        player = view["player"]
        enabled = [row for row in response["choices"] if row["enabled"]]

        def pick(fragment, kind="player_life"):
            return next((row for row in enabled if row["kind"] == kind
                         and row.get("wrapped_action_id", row["id"]).startswith(fragment)), None)

        def travel(fragment):
            return next((row for row in enabled if row["kind"] == "travel"
                         and fragment in row["id"]), None) or next(
                (row for row in enabled if row["kind"] == "travel" and "to_commons" in row["id"]), None)

        if pick("continue"):
            return pick("journey_block") or pick("continue")
        combat = pick("", "combat_encounter")
        if combat:
            return next(row for row in enabled if row["kind"] == "combat_encounter" and row["id"].endswith(":withdraw"))
        if player["hunger"] in {"high", "extreme"} and pick("eat"):
            return pick("eat")
        if player["fatigue"] >= 6:
            return pick("rest_block") or pick("rest")
        if not 6 <= view["time"]["hour"] < 18:
            return pick("rest_block") or pick("rest")
        self.refueling = (self.refueling or player["food_count"] < 2) and player["food_count"] < 6
        if self.refueling:
            return pick("gather:") or travel("commons_to_fishery")
        if not any(row["id"] == "work:recipe.hand_twist_cord" for row in response["choices"]):
            return travel("commons_to_reed_craft")
        # Maintain an actual worn tool; a refused repair is not bypassed.
        repair = next((row for row in enabled if row["id"].startswith("repair:")
                       and "fiber_gear" not in row["id"]), None)
        if repair:
            return repair
        owned = {item["definition_id"].removeprefix("item.") for item in player["inventory"]}
        for item, recipe in RECIPES.items():
            if item not in owned and pick("work:recipe." + recipe):
                return pick("work:recipe." + recipe)
        return pick("work:recipe.hand_twist_cord") or pick("", "wait")


def play(args):
    args.output.mkdir(parents=True, exist_ok=False)
    began = time.perf_counter()
    controller = CatalogPolicy()
    records = []
    with ChronicleClient(packaged=args.packaged) as game:
        response = game.request("start", mode="play", scenario="echo_realm", seed=args.seed,
                                economy_variant="world_adventure_v1")
        if not response.get("ok"):
            raise RuntimeError(response)
        if args.resume_slot:
            response = game.request("load", slot=args.resume_slot)
            if not response.get("ok"):
                raise RuntimeError(response)
        for step in range(args.hours * 2):
            observation = response["observation"]
            owned = {item["definition_id"].removeprefix("item.") for item in observation["player"]["inventory"]}
            if set(RECIPES) <= owned or observation["time"]["elapsed_hours"] >= args.hours:
                break
            choice = controller.choose(response)
            if choice is None:
                raise RuntimeError("No legal policy continuation")
            record = {"before": observation, "offered": response["choices"], "selected": choice["choice_id"]}
            response = game.request("act", choice_id=choice["choice_id"])
            record["after"] = response
            records.append(record)
            with (args.output / "transcript.jsonl").open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")
            if not response.get("ok"):
                raise RuntimeError(response)
            print(f"{step:03} h{response['observation']['time']['elapsed_hours']:03} {choice['label']}", flush=True)
        observation = response["observation"]
        owned = {item["definition_id"].removeprefix("item.") for item in observation["player"]["inventory"]}
        slot = f"catalog_{args.seed}_{time.time_ns()}"
        saved = game.request("save", slot=slot)
        if not saved.get("ok"):
            raise RuntimeError(saved)
        native = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CHRONICLE_GODOT/agent_play/play/echo_realm" / (slot + ".json")
        (args.output / "final.native.json").write_bytes(native.read_bytes())
        restored = game.request("load", slot=slot)
        if not restored.get("ok"):
            raise RuntimeError(restored)
        summary = {
            "seed": args.seed, "packaged": args.packaged, "real_seconds": time.perf_counter() - began,
            "saved_slot": slot, "continued_from_slot": args.resume_slot,
            "scope": "Goal-driven legal AI play using public choices; not passive NPC or human play.",
            "elapsed_hours": observation["time"]["elapsed_hours"], "actions": len(records),
            "obtained": sorted(set(RECIPES) & owned), "missing": sorted(set(RECIPES) - owned),
            "native_public_restore_exact": restored["observation"] == response["observation"],
            "end_player": response["observation"]["player"],
            "features": response["observation"]["equipment_journal"]["features"],
        }
        summary["passed"] = not summary["missing"] and summary["native_public_restore_exact"]
        (args.output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, ensure_ascii=False), flush=True)
        return 0 if summary["passed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=81001)
    parser.add_argument("--hours", type=int, default=168, choices=range(48, 337))
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--resume-slot", help="Continue a real existing play save without editing its world")
    raise SystemExit(play(parser.parse_args()))
