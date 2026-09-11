"""Legal same-save policy branches. Hidden stores are read only after each run."""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path

from agent_play import ChronicleClient


def play(output, *, seed=81001, hours=72, packaged=False, godot=None, policies=None):
    if not 48 <= hours <= 168:
        raise ValueError("Use a bounded 48..168 hour horizon")
    output.mkdir(parents=True, exist_ok=True)
    saves = Path(os.environ["APPDATA"]) / "Godot/app_userdata/CHRONICLE_GODOT/agent_play/play/echo_realm"
    summaries = {}
    with ChronicleClient(packaged=packaged, godot=godot) as game:
        def request(command, **args):
            response = game.request(command, **args)
            if not response.get("ok"):
                raise RuntimeError(json.dumps(response, ensure_ascii=False))
            return response

        request("start", mode="play", scenario="echo_realm", seed=seed, economy_variant="player_life_v1")
        base_slot = f"rf6_base_{seed}"
        request("save", slot=base_slot, overwrite=True)
        base_bytes = (saves / (base_slot + ".json")).read_bytes()
        (output / "common_start.json").write_bytes(base_bytes)
        for policy in policies or ("observer", "prepared", "direct_risk", "local_help"):
            response = request("load", slot=base_slot)
            records = []
            stage = "forage" if policy in {"prepared", "local_help"} else "danger"
            rounds = 0
            visited_danger = False
            at_danger_site = False
            tool_stage = "earn"
            tool_cycles = 0
            for step in range(hours * 2):
                observation = response["observation"]
                time = observation["time"]
                elapsed = time["elapsed_hours"]
                if elapsed >= hours:
                    break
                player = observation["player"]
                choices = [c for c in response["choices"] if c["enabled"]]

                def choose(kind, fragment=""):
                    return next((c for c in choices if c["kind"] == kind and fragment in c["id"]), None)

                choice = None
                if policy == "observer":
                    choice = choose("wait")
                elif choose("player_life", "continue"):
                    choice = choose("player_life", "continue")
                elif choose("combat_encounter"):
                    visited_danger = True
                    approach = ("attack" if rounds == 0 else "withdraw") if policy == "direct_risk" else ("guard" if rounds % 3 < 2 else "attack")
                    choice = choose("combat_encounter", ":" + approach)
                    rounds += 1
                elif policy == "tool_life":
                    def travel_to(fragment):
                        return choose("travel", fragment) or choose("travel", "to_commons")

                    if player.get("hunger") in {"high", "extreme"}:
                        choice = choose("player_life", "eat")
                    if choice is None and player.get("fatigue", 0) >= 6:
                        choice = choose("player_life", "rest")
                    if choice is None:
                        choice = choose("player_life", "inquire:")
                    if tool_stage == "earn" and player.get("coins", 0) >= 6:
                        tool_stage = "buy"
                    rope = next((i for i in player.get("inventory", []) if i["definition_id"] == "item.fiber_rope"), None)
                    if tool_stage == "buy" and rope:
                        tool_stage = "use"
                    if tool_stage == "use" and rope and rope.get("condition", {}).get("durability") == 0:
                        tool_stage = "repair"
                    if tool_stage == "repair" and rope and rope.get("condition", {}).get("durability", 0) > 0:
                        tool_stage = "craft"
                    if tool_stage == "craft" and sum(i["quantity"] for i in player.get("inventory", []) if i["definition_id"] == "item.fiber_rope") > 1:
                        tool_stage = "done"
                    if choice is None and tool_stage == "earn":
                        at_food = any(c["id"].startswith("gather:") for c in response["choices"])
                        if not at_food:
                            choice = travel_to("commons_to_fishery")
                        elif player["food_count"] < 4:
                            choice = choose("player_life", "gather:")
                        else:
                            choice = choose("player_life", "help:")
                    elif choice is None and tool_stage in {"buy", "repair", "craft"}:
                        at_shop = any(c["id"] == "work:recipe.reed_cordage" for c in response["choices"])
                        if not at_shop:
                            choice = travel_to("commons_to_reed_craft")
                        elif tool_stage == "buy":
                            choice = next((c for c in choices if c["kind"] == "player_life" and c["id"].startswith("buy:") and "纤维绳索" in c["label"]), None)
                        elif tool_stage == "repair":
                            choice = choose("player_life", "repair:")
                        else:
                            choice = choose("player_life", "work:recipe.reed_cordage")
                    elif choice is None and tool_stage in {"use", "done"}:
                        at_food = any(c["id"] == "work:recipe.net_fishing" for c in response["choices"])
                        if not at_food:
                            choice = travel_to("commons_to_fishery")
                        elif tool_stage == "use" or player["food_count"] < 4:
                            choice = choose("player_life", "work:recipe.net_fishing") or choose("player_life", "gather:")
                            if choice and choice["id"] == "work:recipe.net_fishing":
                                tool_cycles += 1
                    if choice and choice.get("hours", 1) > hours - elapsed:
                        choice = None
                else:
                    if visited_danger and stage == "danger":
                        stage = "leave_danger"
                    if stage == "leave_danger":
                        choice = choose("travel")
                        if choice:
                            stage = "forage"
                            at_danger_site = False
                    if choice is None and player.get("hunger") in {"high", "extreme"}:
                        choice = choose("player_life", "eat")
                    if choice is None and policy == "local_help":
                        choice = choose("player_life", "inquire:")
                    if choice is None and (player.get("fatigue", 0) >= 6 or
                                           (player.get("injury") != "none" and player.get("food_count", 0) > 0)):
                        choice = choose("player_life", "rest")
                    if choice is None and stage == "forage":
                        if policy == "prepared" and not visited_danger and player["food_count"] >= 6:
                            if 6 <= time["hour"] <= 8:
                                stage = "danger"
                        elif policy == "local_help" and hours - elapsed >= 4:
                            choice = choose("player_life", "help:")
                            if choice is None and player["food_count"] < 4:
                                choice = choose("player_life", "buy:")
                        if choice is None and stage == "forage" and player["food_count"] < 4 and hours - elapsed >= 4:
                            choice = choose("player_life", "gather:")
                        at_food_site = any(c["kind"] == "player_life" and c["id"].startswith("gather:") for c in response["choices"])
                        if choice is None and stage == "forage" and not at_food_site:
                            choice = choose("travel", "commons_to_fishery") or choose("travel", "to_commons") or choose("travel", ".network.")
                        if choice is None and policy == "prepared" and not visited_danger and player["food_count"] < 6 and hours - elapsed >= 4:
                            choice = choose("player_life", "gather:")
                    if choice is None and stage == "danger":
                        if not at_danger_site:
                            choice = choose("travel", "commons_to_terrace_farming") or choose("travel", "to_commons") or choose("travel", ".network.")
                            if choice and "commons_to_terrace_farming" in choice["id"]:
                                at_danger_site = True
                        if elapsed > 48 and choice is None:
                            stage = "leave_danger"
                choice = choice or choose("wait")
                if choice is None:
                    raise AssertionError(f"No legal continuation for {policy} at {elapsed}")
                record = {"before_time": time, "before_player": player, "location": observation["location"],
                          "offered": [{k: c.get(k) for k in ("choice_id", "label", "kind", "enabled")} for c in response["choices"]],
                          "selected": choice["choice_id"]}
                response = request("act", choice_id=choice["choice_id"])
                record["after_time"] = response["observation"]["time"]
                record["feedback"] = response["observation"].get("feedback", {})
                record["witnessed_followups"] = response["observation"].get("player_life_followups", [])
                records.append(record)
                if rounds == 1 and choice["kind"] == "combat_encounter":
                    slot = f"rf6_midfight_{seed}_{policy}"
                    request("save", slot=slot, overwrite=True)
                    response = request("load", slot=slot)
            assert response["observation"]["time"]["elapsed_hours"] == hours, "Branches must align exactly"
            slot = f"rf6_outcome_{seed}_{policy}"
            request("save", slot=slot, overwrite=True)
            raw = (saves / (slot + ".json")).read_bytes()
            (output / f"{policy}.native.json").write_bytes(raw)
            envelope = json.loads(raw)
            stores = envelope["stores"]
            facts = stores["facts"]
            assert not any(f.get("fact_type") == "test_injection" for f in facts)
            people = {i: s for i, s in stores["states"].items() if i.startswith("generated_resident.")}
            balances = Counter()
            for item in stores["items"]:
                if item["item_def_id"] == "item.copper_coin":
                    balances[item["holder"]["id"]] += item["quantity"]
            summary = {"seed": seed, "policy": policy, "elapsed_hours": hours, "legal_actions": len(records),
                       "player": response["observation"]["player"], "combat_rounds": rounds,
                       "player_facts": dict(Counter(f.get("fact_type", "") for f in facts if f.get("actor_id") == "player")),
                       "tool_stage": tool_stage if policy == "tool_life" else None,
                       "production": [f for f in facts if f.get("actor_id") == "player" and f.get("fact_type") in {"npc_livelihood_produced", "npc_work_maintained"}],
                       "hunger": dict(Counter(s.get("hunger", "none") for s in people.values())),
                       "resident_states": people, "save_sha256": hashlib.sha256(raw).hexdigest(),
                       "currency_balances": dict(balances), "total_coins": sum(balances.values()),
                       "hired_work": [f for f in facts if f.get("actor_id") == "player" and f.get("employer_id") and f.get("fact_type") == "npc_livelihood_produced"],
                       "witnessed_followups": response["observation"].get("player_life_followups", []),
                       "same_start_sha256": hashlib.sha256(base_bytes).hexdigest(),
                       "evidence_kind": "legal_code_agent_play", "test_injection": False, "human_ui_play": False}
            summaries[policy] = summary
            (output / f"{policy}.transcript.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({k: summary[k] for k in ("seed", "policy", "elapsed_hours", "combat_rounds", "player_facts", "hunger", "total_coins")}, ensure_ascii=False), flush=True)
        assert not any("SCRIPT ERROR" in line for line in game.diagnostics), list(game.diagnostics)
    baseline_policy = "observer" if "observer" in summaries else next(iter(summaries))
    baseline = summaries[baseline_policy]["resident_states"]
    for policy, summary in summaries.items():
        summary["changed_residents"] = {i: {k: [baseline[i].get(k), s.get(k)] for k in
            ("health", "hunger", "fatigue", "location_id", "daily_activity", "livelihood_cycle_count") if baseline[i].get(k) != s.get(k)}
            for i, s in summary["resident_states"].items() if i in baseline and s != baseline[i]}
        summary["changed_residents"] = {i: changes for i, changes in summary["changed_residents"].items() if changes}
        summary["changed_balances"] = {i: [summaries[baseline_policy]["currency_balances"].get(i, 0), coins]
            for i, coins in summary["currency_balances"].items()
            if i != "player" and coins != summaries[baseline_policy]["currency_balances"].get(i, 0)}
    (output / "comparison.json").write_text(json.dumps(summaries, ensure_ascii=False, indent=2), encoding="utf-8")
    return summaries


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=81001)
    parser.add_argument("--hours", type=int, default=72)
    parser.add_argument("--packaged", action="store_true")
    parser.add_argument("--godot")
    parser.add_argument("--policies", nargs="+", choices=("observer", "prepared", "direct_risk", "local_help", "tool_life"))
    args = parser.parse_args()
    play(args.output, seed=args.seed, hours=args.hours, packaged=args.packaged, godot=args.godot, policies=args.policies)
