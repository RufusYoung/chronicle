"""Describe integration outcomes from native saves, without equating counts with acceptance."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def hour(record):
    return int(record.get("day", 0)) * 24 + int(record.get("hour", 0))


def equipment_chains(items, gear, facts, by_id):
    chains = []
    for item in items:
        if item["item_def_id"] not in gear:
            continue
        ident = item["item_instance_id"]
        production = by_id.get(item.get("provenance", {}).get("created_by_fact_id"), {})
        history = item.get("history", [])
        worn = [e for e in history if e.get("event_type") == "durability_changed" and e["to"] < e["from"]]
        repaired = [e for e in history if e.get("event_type") == "durability_changed" and e["to"] > e["from"]]
        modified = [f for f in facts if any(
            m.get("source_kind") == "equipment" and m.get("source_id") == ident
            for m in f.get("modifier_explanations", []))]
        purchases = [f for f in facts if f.get("fact_type") == "work_supply_purchased"
                     and f.get("goods_source_item_instance_id") == ident]
        purchased_then_modified = [f["fact_id"] for f in modified if any(
            f.get("actor_id") == p.get("actor_id") and hour(f) > hour(p) for p in purchases)]
        wear_hours = [hour(by_id[e["fact_id"]]) for e in worn if e["fact_id"] in by_id]
        repair_hours = [hour(by_id[e["fact_id"]]) for e in repaired if e["fact_id"] in by_id]
        chains.append({"item_id": ident, "definition": item["item_def_id"], "holder": item["holder"],
                       "production_fact": production.get("fact_id"),
                       "production_inputs": production.get("resource_inputs", []),
                       "production_tools": production.get("tools_used", []),
                       "equipped": [e for e in history if e.get("event_type") == "equipped"],
                       "combat_modifier_facts": [f["fact_id"] for f in modified],
                       "purchase_facts": [p["fact_id"] for p in purchases],
                       "purchased_then_modifier_facts": purchased_then_modified,
                       "wear": worn, "repairs": repaired,
                       "repair_inputs": [by_id.get(e["fact_id"], {}).get("resource_inputs", []) for e in repaired],
                       "used_after_repair": bool(repair_hours and any(t > min(repair_hours) for t in wear_hours)),
                       "durability": item.get("condition", {}).get("durability")})
    return chains


def audit(path):
    raw = path.read_bytes()
    data = json.loads(raw.decode("utf-8-sig"))
    stores = data["stores"]
    facts = stores["facts"]
    states = stores["states"]
    by_id = {f["fact_id"]: f for f in facts}
    counts = Counter(f.get("fact_type", "") for f in facts)
    gear = {d["item_def_id"] for d in data["bootstrap"]["fixture_data"]["integration_rules"]["item_defs"]}
    purchases = [f for f in facts if f.get("fact_type") == "work_supply_purchased"]
    equipped = [f for f in facts if f.get("fact_type") == "resident_equipped"]
    start = hour(data["bootstrap"]["fixture_data"].get("world_time", {"day": 1, "hour": 8}))
    end = hour(data["world_time"])
    people = []
    for ident, state in states.items():
        if not ident.startswith("generated_resident."):
            continue
        own = [f for f in facts if f.get("actor_id") == ident]
        meals = [f for f in facts if (f.get("actor_id") == ident and f.get("fact_type") == "npc_self_meal") or
                 (f.get("target_id") == ident and f.get("fact_type") in ("npc_household_shared_food", "npc_cross_household_shared_food"))]
        meal_hours = sorted({hour(f) for f in meals})
        boundaries = [start] + meal_hours + [end]
        people.append({"id": ident, "health": state.get("health"), "hunger": state.get("hunger"),
                       "activity": state.get("daily_activity"), "meals": len(meals),
                       "last_meal": max(meal_hours, default=None),
                       "maximum_meal_gap_hours": max(b-a for a, b in zip(boundaries, boundaries[1:])),
                       "current_meal_gap_hours": end - max(meal_hours, default=start),
                       "injuries": sum(f.get("fact_type") == "actor_injured_during_combat" for f in own)})
    replies = [f for f in facts if f.get("fact_type") == "community_observation" and f.get("topic") == "aid_reply"]
    heard = [f for f in facts if f.get("fact_type") == "community_message_heard" and f.get("topic") == "aid_reply"]
    counters = [f for f in facts if f.get("payload", {}).get("delivery_request", {}).get("negotiation_reply_id")]
    resumed = [f for f in facts if f.get("fact_type") == "food_hauling_stocked" and f.get("negotiation_reply_id")]
    references = []
    for f in equipped + purchases + replies + counters + resumed:
        missing = [s for s in f.get("source_fact_ids", []) if s not in by_id]
        if missing:
            references.append({"fact_id": f["fact_id"], "missing": missing})
    initial_money = sum(int(i.get("quantity", 1)) for i in data["bootstrap"]["fixture_data"].get("initial_items", [])
                        if i.get("item_def_id") == "item.copper_coin")
    current_money = sum(int(i.get("quantity", 1)) for i in stores["items"] if i.get("item_def_id") == "item.copper_coin")
    report = {"save": str(path), "save_sha256": hashlib.sha256(raw).hexdigest(), "world_time": data["world_time"], "counts": counts,
              "copper_coins": {"initial": initial_money, "current_including_escrow": current_money,
                               "conserved": initial_money == current_money},
              "gear_definitions": sorted(gear), "work_supply_purchases": purchases,
              "equipment_purchases": [f for f in purchases if f.get("fields", {}).get("item_def_id") in gear], "equipped": equipped,
              "equipment_chains": equipment_chains(stores["items"], gear, facts, by_id),
              "recipes": Counter(f.get("recipe_id") for f in facts if f.get("recipe_id")),
              "replies": replies, "heard_replies": len(heard), "counterproposals": counters,
              "negotiated_deliveries": resumed, "people": people,
              "broken_sources": references, "test_injections": counts["test_injection"],
              "boundary": "Passive observations; inspect causal chains and ablations before accepting a phase."}
    result = path.parent / "result.json"
    if result.exists():
        probe = json.loads(result.read_text(encoding="utf-8-sig"))
        report["extreme_person_hours"] = probe.get("extreme_person_hours")
        report["activity_hours"] = probe.get("activity_hours")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("save", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.save)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"sources_ok": not report["broken_sources"], "equipped": len(report["equipped"]),
                      "purchases": len(report["equipment_purchases"]), "replies": len(report["replies"]),
                      "negotiated_deliveries": len(report["negotiated_deliveries"]),
                      "coins_conserved": report["copper_coins"]["conserved"],
                      "extreme_person_hours": report.get("extreme_person_hours")}, ensure_ascii=False))
    raise SystemExit(bool(report["broken_sources"]) or not report["copper_coins"]["conserved"])
