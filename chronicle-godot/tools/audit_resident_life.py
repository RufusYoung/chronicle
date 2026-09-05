"""Read a native checkpoint without running or modifying its world."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def audit(path: Path) -> dict:
    content = path.read_bytes()
    envelope = json.loads(content)
    stores = envelope["stores"]
    fixture = envelope["bootstrap"]["fixture_data"]
    definitions = json.loads((Path(__file__).resolve().parents[1] /
                             "data/sim/raw/item_defs/basic_item_defs.json").read_text(encoding="utf-8"))
    food_ids = {row["item_def_id"] for row in definitions["item_defs"]
                if "food" in row.get("tags", []) and "consume" in row.get("capabilities", [])}
    people = [row for row in stores["entities"].values()
              if "generated_resident" in row.get("tags", []) and
              stores["states"].get(row["id"], {}).get("alive", True)]
    states = [stores["states"][row["id"]] for row in people]
    facts = stores["facts"]
    production = [row for row in facts if row.get("fact_type") == "npc_livelihood_produced"]
    produced_food = sum(product["quantity"] for row in production for product in row.get("products", [])
                        if product["item_def_id"] in food_ids)
    meals = [row for row in facts if row.get("fact_type") in
             {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}]
    initial_food = sum(row["quantity"] for row in fixture.get("initial_items", [])
                       if row["item_def_id"] in food_ids)
    remaining_food = sum(row["quantity"] for row in stores["items"] if row["item_def_id"] in food_ids)
    purchases = [row for row in facts if row.get("fact_type") == "resident_food_purchased"]
    cross_purchases = [row for row in purchases if row.get("buyer_settlement_id") and
                       row.get("buyer_settlement_id") != row.get("seller_settlement_id")]
    purchase_ids = {row["fact_id"] for row in purchases}
    deliveries = [row for row in facts if row.get("fact_type") == "household_food_delivered"]
    delivery_ids = {row["fact_id"] for row in deliveries}
    meal_counts = Counter(row.get("target_id") for row in meals)
    wages = Counter()
    for row in facts:
        if row.get("fact_type") == "npc_wage_paid":
            wages[row.get("target_id")] += row.get("amount", 0)
    currency = sum(row["quantity"] for row in stores["items"] if row["item_def_id"] == "item.copper_coin")
    return {
        "checkpoint": str(path), "sha256": hashlib.sha256(content).hexdigest(),
        "rule_version": fixture.get("resident_daily_life", {}).get("version", 0),
        "food_access_config": fixture.get("resident_daily_life", {}).get("food_access", {}),
        "scope": "Offline checkpoint audit; counts are observations, not a sustainable economy acceptance.",
        "resident_count": len(people), "hunger": dict(Counter(row.get("hunger") for row in states)),
        "activity": dict(Counter(row.get("daily_activity", "legacy") for row in states)),
        "initial_food_portions": initial_food, "produced_food_portions": produced_food,
        "consumed_meals": len(meals), "remaining_food_portions": remaining_food,
        "food_balance_remainder": initial_food + produced_food - len(meals) - remaining_food,
        "food_balance_scope": "Valid for passive fixture meals; other consumption/transfers must be audited separately.",
        "initial_currency": fixture.get("economic_generation_result", {}).get("initial_currency_total"),
        "remaining_currency": currency,
        "food_purchases": len(purchases), "cross_settlement_food_purchases": len(cross_purchases),
        "purchased_portions": sum(row.get("fields", {}).get("quantity", 0) for row in purchases),
        "cross_settlement_purchased_portions": sum(row.get("fields", {}).get("quantity", 0) for row in cross_purchases),
        "food_sales_income": sum(row.get("fields", {}).get("total_price", 0) for row in purchases),
        "meals_citing_purchases": sum(bool(set(row.get("source_fact_ids", [])) & purchase_ids) for row in meals),
        "family_deliveries": len(deliveries),
        "deliveries_citing_purchases": sum(bool(set(row.get("source_fact_ids", [])) & purchase_ids) for row in deliveries),
        "meals_citing_deliveries": sum(bool(set(row.get("source_fact_ids", [])) & delivery_ids) for row in meals),
        "purchasing_failures": dict(Counter(row.get("reason") for row in facts if row.get("fact_type") == "resident_food_purchase_unmet")),
        "steady_meals_per_day_reference": sum(24 / (max(row.get("hunger_interval_hours", 6), 1) * 2) for row in states),
        "demand_scope": "Reference only: one hunger step per configured interval, two relieved per meal. Not observed consumption.",
        "fact_counts": dict(Counter(row.get("fact_type") for row in facts)),
        "residents": [{"id": person["id"], "name": person.get("display_name"),
                       "location": state.get("location_id"), "home": state.get("home_location_id"),
                       "workplace": state.get("workplace_id"), "occupation": state.get("occupation_id"),
                       "activity": state.get("daily_activity"), "hunger": state.get("hunger"),
                       "temperament": state.get("temperament"), "household_id": state.get("household_id"),
                       "meals": meal_counts[person["id"]],
                       "wages_received": wages[person["id"]],
                       "food_purchase_spend": sum(row.get("fields", {}).get("total_price", 0) for row in purchases
                                                  if row.get("actor_id") == person["id"]),
                       "food": sum(row["quantity"] for row in stores["items"] if row["item_def_id"] in food_ids and
                                   row.get("holder") == {"kind": "entity", "id": person["id"]}),
                       "coins": sum(row["quantity"] for row in stores["items"] if row["item_def_id"] == "item.copper_coin" and
                                    row.get("holder") == {"kind": "entity", "id": person["id"]}),
                       "family_deliveries_received": sum(row.get("target_id") == person["id"] for row in deliveries),
                       "production_cycles": state.get("livelihood_cycle_count", 0)}
                      for person, state in zip(people, states)]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = audit(args.checkpoint)
    encoded = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key not in {"residents", "fact_counts"}},
                     ensure_ascii=True, indent=2))
