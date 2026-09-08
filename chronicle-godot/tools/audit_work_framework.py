"""Audit committed work/maintenance/trade ancestry without advancing the world."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from audit_resident_life import audit as audit_life


def audit(path: Path) -> dict:
    content = path.read_bytes()
    envelope = json.loads(content)
    stores = envelope["stores"]
    facts = stores["facts"]
    index = {fact["fact_id"]: fact for fact in facts}
    initial = envelope["bootstrap"]["fixture_data"]
    initial_people = [p for p in initial["entities"] if p.get("type") == "person"
                      and "generated_resident" in p.get("tags", [])]

    def ancestry(fact):
        pending = list(fact.get("source_fact_ids", []))
        seen = set()
        while pending:
            key = pending.pop()
            if key in seen or key not in index:
                continue
            seen.add(key)
            pending.extend(index[key].get("source_fact_ids", []))
        return seen

    ancestors = {fact["fact_id"]: ancestry(fact) for fact in facts if fact.get("fact_type") in {
        "npc_livelihood_produced", "npc_work_maintained", "work_supply_purchased",
        "resident_activity_changed", "resident_food_purchased", "food_hauling_stocked",
        "npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}}
    production = [f for f in facts if f.get("fact_type") == "npc_livelihood_produced"]
    purchases = [f for f in facts if f.get("fact_type") == "work_supply_purchased"]
    repairs = [f for f in facts if f.get("fact_type") == "npc_work_maintained"]
    shortfalls = [f for f in facts if f.get("fact_type") == "work_supply_unmet"]
    meals = [f for f in facts if f.get("fact_type") in {
        "npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}]
    decisions = [f for f in facts if f.get("choice_version") == 1]
    chains = []
    for cause in purchases + repairs:
        if cause.get("fact_type") == "work_supply_purchased":
            physical_ids = {item["item_instance_id"] for item in stores["items"]
                            if item["item_def_id"] == cause["fields"]["item_def_id"] and (
                                item.get("provenance", {}).get("created_by_fact_id") == cause["fact_id"] or any(
                                    h.get("event_type") == "transferred" and h.get("fact_id") == cause["fact_id"]
                                    and h.get("to_holder", {}).get("id") == cause["actor_id"]
                                    for h in item.get("history", [])))}
        else:
            physical_ids = {row["item_instance_id"] for row in cause.get("repairs", [])}
        # Descendants retain physical identity through legal stack splitting.
        for _ in range(len(stores["items"])):
            descendants = {item["item_instance_id"] for item in stores["items"]
                           if physical_ids.intersection(item.get("provenance", {}).get("parent_item_instance_ids", []))}
            if descendants <= physical_ids:
                break
            physical_ids.update(descendants)
        uses = [f for f in production if f.get("actor_id") == cause["actor_id"]
                and any(tool["item_instance_id"] in physical_ids for tool in f.get("tools_used", []))
                and cause["fact_id"] in ancestors[f["fact_id"]]]
        for use in uses:
            downstream = [f for f in meals if use["fact_id"] in ancestors[f["fact_id"]]]
            delivered = [f for f in facts if f.get("fact_type") == "food_hauling_stocked"
                         and use["fact_id"] in ancestors[f["fact_id"]]]
            suppliers = [index[key] for key in ancestors[cause["fact_id"]]
                         if index[key].get("fact_type") == "npc_livelihood_produced"
                         and index[key].get("actor_id") != cause["actor_id"]
                         and any(p["item_def_id"] == cause.get("fields", {}).get("item_def_id")
                                 for p in index[key].get("products", []))]
            chains.append({
                "structure": "produced_tool>paid_purchase>productive_use>meal" if cause in purchases
                else "limited_repair>productive_use>meal",
                "cause_fact_id": cause["fact_id"], "worker_id": cause["actor_id"],
                "supplier_id": cause.get("target_id"),
                "supplier_production_fact_ids": [f["fact_id"] for f in suppliers],
                "causal_tool_instance_ids": sorted(physical_ids),
                "use_fact_id": use["fact_id"], "used_tools": use["tools_used"],
                "haul_fact_ids": [f["fact_id"] for f in delivered],
                "meal_fact_ids": [f["fact_id"] for f in downstream],
                "meal_recipients": sorted({f.get("target_id", "") for f in downstream}),
            })
    revenue_followups = []
    for purchase in purchases:
        for fact in facts:
            if fact.get("fact_type") == "resident_food_purchased" and fact.get("actor_id") == purchase.get("target_id") \
                    and purchase["fact_id"] in ancestors[fact["fact_id"]]:
                revenue_followups.append({"work_sale": purchase["fact_id"], "seller_food_purchase": fact["fact_id"]})
    repair_after_refusal = [f["fact_id"] for f in repairs if any(
        s["fact_id"] in ancestors[f["fact_id"]] and s["actor_id"] == f["actor_id"] for s in shortfalls)]
    life = audit_life(path)
    # Work item inputs are consumed, unlike retained tools. Account for them by definition.
    created = Counter()
    consumed = Counter()
    remaining = Counter()
    for item in initial.get("initial_items", []):
        created[item["item_def_id"]] += item["quantity"]
    for fact in production:
        for item in fact.get("products", []):
            created[item["item_def_id"]] += item["quantity"]
    for fact in production + repairs:
        for item in fact.get("item_inputs", []):
            consumed[item["item_def_id"]] += item["quantity"]
    for fact in meals:
        item_id = fact.get("item_instance_id", "")
        item = next((i for i in stores["items"] if i["item_instance_id"] == item_id), {})
        if item:
            consumed[item["item_def_id"]] += 1
    for item in stores["items"]:
        remaining[item["item_def_id"]] += item["quantity"]
    work_ids = {p["item_def_id"] for f in production for p in f.get("products", []) if f.get("recipe_id")}
    # Food accounting is handled by the existing audit; this audit explicitly checks nonfood work outputs.
    definitions = json.loads((Path(__file__).resolve().parents[1] / "data/sim/raw/item_defs/basic_item_defs.json").read_text(encoding="utf-8"))
    food_ids = {d["item_def_id"] for d in definitions["item_defs"] if "food" in d.get("tags", [])}
    nonfood_balance = {key: created[key] - consumed[key] - remaining[key] for key in sorted(work_ids - food_ids)}
    return {
        "checkpoint": str(path), "sha256": hashlib.sha256(content).hexdigest(),
        "scope": "Passive committed-fact ancestry. Correlation or citations alone are not exclusive causal attribution; compare ablations.",
        "seed": initial.get("challenge_seed"), "elapsed_hours": envelope["world_time"]["elapsed_hours"],
        "initial_conditions": {key: dict(Counter(p.get("states", {}).get(key) for p in initial_people))
                               for key in ("occupation_id", "temperament", "hunger")},
        "test_injections": [f["fact_id"] for f in facts if f.get("fact_type") == "test_injection"],
        "work_purchases": len(purchases), "work_purchase_spend": sum(f["fields"]["total_price"] for f in purchases),
        "maintenance_cycles": len(repairs), "work_supply_failures": dict(Counter(f.get("reason") for f in shortfalls)),
        "production_by_recipe": dict(Counter(f.get("recipe_id", "legacy") for f in production)),
        "decision_kinds": dict(Counter(f["chosen_candidate"].split(":", 1)[0] for f in decisions)),
        "repairs_after_supply_refusal": repair_after_refusal,
        "chains": chains, "structures_with_meals": dict(Counter(c["structure"] for c in chains if c["meal_fact_ids"])),
        "seller_revenue_food_purchase_links": revenue_followups,
        "food_balance_remainder": life["food_balance_remainder"],
        "currency_balance_remainder": life["initial_currency"] - life["remaining_currency"],
        "nonfood_work_balance_remainders": nonfood_balance,
        "meals": life["consumed_meals"], "meals_by_elapsed_day": life["meals_by_elapsed_day"],
        "longest_meal_gap_hours": max(p["longest_meal_gap_hours"] for p in life["residents"]),
        "minimum_resident_meals": min(p["meals"] for p in life["residents"]),
        "hauling_orders": life["hauling_orders"], "hauling_paid_fees": life["hauling_paid_fees"],
        "residents": life["residents"],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.checkpoint)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key not in {"chains", "residents"}}, ensure_ascii=True))
