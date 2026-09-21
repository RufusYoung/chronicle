"""Summarize frozen integration runs without treating event totals as acceptance."""

import argparse
import json
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def summarize(root):
    rows = []
    manifests = []
    for path in sorted(root.glob("*/*.audit.json")):
        if not path.name.startswith("canon_integration_"):
            continue
        data = read(path)
        config = read(path.parent / "run_configuration.json")
        results = read(path.parent / "results.json")
        if isinstance(results, dict):
            results = [results]
        manifests.append(read(path.parent / "runtime_manifest.json"))
        chains = data["equipment_chains"]
        people = data["people"]
        rows.append({
            "case": path.stem.removesuffix(".audit"),
            "seed": config["Seeds"][0],
            "ablation": config.get("OnlyAblation", ""),
            "native_runner_passed": all(r["Passed"] for r in results),
            "elapsed_hours": data["world_time"]["elapsed_hours"],
            "save_sha256": data["save_sha256"],
            "coins": data["copper_coins"],
            "sources_valid": not data["broken_sources"],
            "test_injections": data["test_injections"],
            "gear_purchases": len(data["equipment_purchases"]),
            "gear_selections": len(data["equipped"]),
            "gear_modifier_applications": sum(len(c["combat_modifier_facts"]) for c in chains),
            "produced_purchased_and_used": [c["item_id"] for c in chains
                if c["production_fact"] and c["purchased_then_modifier_facts"]],
            "produced_used_repaired_used_again": [c["item_id"] for c in chains
                if c["production_fact"] and c["equipped"] and c["combat_modifier_facts"]
                and c["used_after_repair"] and all(c["repair_inputs"])],
            "repair_cycles": sum(len(c["repairs"]) for c in chains),
            "refusals": data["counts"].get("community_aid_withheld", 0),
            "replies": len(data["replies"]),
            "heard_replies": data["heard_replies"],
            "counterproposals": len(data["counterproposals"]),
            "negotiated_deliveries": len(data["negotiated_deliveries"]),
            "all_deliveries": data["counts"].get("food_hauling_stocked", 0),
            "extreme_person_hours": data.get("extreme_person_hours"),
            "minimum_final_health": min(p["health"] for p in people),
            "maximum_meal_gap_hours": max(p["maximum_meal_gap_hours"] for p in people),
            "maximum_current_meal_gap_hours": max(p["current_meal_gap_hours"] for p in people),
            "injuries": data["counts"].get("actor_injured_during_combat", 0),
        })
    natural = [r for r in rows if not r["ablation"]]
    checks = {
        "same_runtime": bool(manifests) and all(m == manifests[0] for m in manifests),
        "three_natural_worlds": len(natural) == 3,
        "held_out_87029_present": any(r["seed"] == 87029 for r in natural),
        "all_completed_30_days": bool(rows) and all(r["native_runner_passed"] and r["elapsed_hours"] == 720 for r in rows),
        "money_and_references": bool(rows) and all(r["coins"]["conserved"] and r["sources_valid"] for r in rows),
        "natural_worlds_not_injected": bool(natural) and all(r["test_injections"] == 0 for r in natural),
        "natural_purchased_gear_used": any(r["produced_purchased_and_used"] for r in natural),
        "natural_repaired_gear_reused": any(r["produced_used_repaired_used_again"] for r in natural),
        "required_ablation_pairs": all(any(r["seed"] == seed and r["ablation"] == mode for r in rows)
            for seed, mode in [(81001, "equipment"), (81001, "livelihood"), (81001, "negotiation"), (87029, "negotiation")]),
    }
    return {
        "checks": checks,
        "passed": all(checks.values()),
        "rows": rows,
        "natural_negotiated_delivery_observed": any(r["negotiated_deliveries"] for r in natural),
        "hunger_metric_scope": "Extreme-person-hours include the inactive traveler; health and meal-gap metrics describe generated residents only. Keep this scope when reporting percentages.",
        "boundary": "Structural integration evidence, not sustainable nutrition, a full ecology or human play acceptance. Ablations are test interventions. Zero negotiated deliveries must be reported separately from controlled agreement tests and ordinary resumed aid.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = summarize(args.directory)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(not report["passed"])
