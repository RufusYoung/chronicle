"""Check RF1-RF3 passive evidence; does not rate fun or long-term sustainability."""
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path


def evaluate(cases):
    natural = [c for c in cases if "without_" not in c["probe"]["mode"]]
    checks = {}
    checks["three_natural_seeds"] = len({c["audit"]["seed"] for c in natural}) >= 3
    checks["seven_days_no_native_failures"] = all(
        c["audit"]["elapsed_hours"] == 168 and c["probe"]["elapsed_days"] == 7
        and c["probe"]["failures"] == [] for c in cases)
    checks["natural_not_injected"] = all(c["audit"]["test_injections"] == [] for c in natural)
    checks["money_food_goods_conserved"] = all(
        c["audit"]["food_balance_remainder"] == 0
        and c["audit"]["currency_balance_remainder"] == 0
        and all(v == 0 for v in c["audit"]["nonfood_work_balance_remainders"].values()) for c in cases)
    chains = [chain for c in natural for chain in c["audit"]["chains"] if chain["meal_fact_ids"]]
    checks["two_causal_structures"] = len({c["structure"] for c in chains}) >= 2
    checks["autonomous_producer_buyer_use_and_food"] = any(
        c["supplier_id"] and c["supplier_id"] != c["worker_id"]
        and c["supplier_production_fact_ids"] and c["causal_tool_instance_ids"]
        and c["used_tools"] for c in chains)
    checks["seller_reuses_actual_revenue"] = any(c["audit"]["seller_revenue_food_purchase_links"] for c in natural)
    checks["refusal_then_limited_repair"] = any(c["audit"]["repairs_after_supply_refusal"] for c in natural)
    checks["paid_physical_hauling_continues"] = all(c["audit"]["hauling_paid_fees"] > 0 for c in natural)
    for kind in ("repair", "supply", "wear"):
        controls = [c for c in cases if f"without_{kind}_" in c["probe"]["mode"]]
        checks[f"{kind}_ablation_exists"] = len(controls) == 1
        if len(controls) != 1:
            continue
        control = controls[0]["audit"]
        baseline = next((c["audit"] for c in natural if c["audit"]["seed"] == control["seed"]), {})
        checks[f"{kind}_ablation_labeled"] = bool(control["test_injections"])
        checks[f"{kind}_changes_behavior"] = bool(baseline) and any(
            control[key] != baseline[key] for key in
            ("work_purchase_spend", "production_by_recipe", "decision_kinds", "hauling_orders"))
        if kind == "repair":
            checks["no_disabled_repairs"] = control["maintenance_cycles"] == 0
        elif kind == "supply":
            checks["no_disabled_purchases"] = control["work_purchases"] == 0
        else:
            checks["no_tool_replacement_without_wear"] = control["work_purchases"] == control["maintenance_cycles"] == 0
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--heldout", type=Path, required=True)
    parser.add_argument("--compare-previous", type=Path)
    parser.add_argument("--regression", type=Path)
    parser.add_argument("--render", type=Path)
    args = parser.parse_args()
    cases = []
    for directory in (args.directory, args.heldout):
        for path in sorted(directory.glob("*.audit.json")):
            cases.append({"audit": json.loads(path.read_text(encoding="utf-8-sig")),
                          "probe": json.loads(path.with_name(path.name.replace(".audit", ".probe")).read_text(encoding="utf-8-sig"))})
    checks = evaluate(cases)
    checks["same_frozen_runtime_for_heldout"] = json.loads((args.directory / "runtime_manifest.json").read_text(encoding="utf-8-sig")) == json.loads((args.heldout / "runtime_manifest.json").read_text(encoding="utf-8-sig"))
    checks["heldout_seed_is_new"] = not {c["audit"]["seed"] for c in cases if "heldout" in c["probe"]["mode"]}.intersection(
        c["audit"]["seed"] for c in cases if "heldout" not in c["probe"]["mode"])
    checks["heldout_exists"] = any("heldout" in c["probe"]["mode"] for c in cases)
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((args.directory / "runtime_manifest.json").read_text(encoding="utf-8-sig"))
    checks["current_runtime_matches_frozen_evidence"] = all(
        (root / row["Path"]).is_file()
        and hashlib.sha256((root / row["Path"]).read_bytes()).hexdigest().upper() == row["SHA256"] for row in manifest)
    suites = {}
    if args.regression and args.render:
        normal = [r for r in json.loads((args.regression / "results.json").read_text(encoding="utf-8-sig"))
                  if not r["Test"].endswith("_render_test.gd")]
        render = json.loads((args.render / "results.json").read_text(encoding="utf-8-sig"))
        expected = {p.relative_to(root).as_posix() for p in (root / "tests").rglob("*.gd")
                    if p.name != "generated_world_30_day_health_test.gd"}
        checks["complete_frozen_regression_coverage"] = {r["Test"] for r in normal + render} == expected
        for label, rows in (("nonrender", normal), ("actual_render", render)):
            checks[label + "_passed"] = bool(rows) and all(r["Passed"] for r in rows)
            suites[label] = {"passed": sum(bool(r["Passed"]) for r in rows), "total": len(rows)}
    if args.compare_previous:
        previous = {}
        for path in args.compare_previous.glob("*.audit.json"):
            row = json.loads(path.read_text(encoding="utf-8-sig"))
            kind = next((k for k in ("repair", "supply", "wear") if f"without_{k}_" in path.name), "natural")
            previous[(row["seed"], kind)] = row
        for case in cases:
            if "heldout" in case["probe"]["mode"]:
                continue
            kind = next((k for k in ("repair", "supply", "wear") if f"without_{k}_" in case["probe"]["mode"]), "natural")
            old = previous[(case["audit"]["seed"], kind)]
            checks[f"trace_fix_preserves_outcomes:{kind}_{old['seed']}"] = all(old[key] == case["audit"][key] for key in (
                "work_purchases", "work_purchase_spend", "maintenance_cycles", "production_by_recipe",
                "decision_kinds", "meals", "hauling_orders", "hauling_paid_fees", "longest_meal_gap_hours"))
    # Falsify the checker itself: counts and citations must not hide injected or unbalanced worlds.
    bad = deepcopy(cases)
    next(c for c in bad if "without_" not in c["probe"]["mode"])["audit"]["test_injections"] = ["test_injection.checker"]
    checks["checker_rejects_injected_natural"] = not evaluate(bad)["natural_not_injected"]
    bad[0]["audit"]["currency_balance_remainder"] = 1
    checks["checker_rejects_unbalanced_money"] = not evaluate(bad)["money_food_goods_conserved"]
    for case in bad:
        case["audit"]["chains"] = []
    checks["checker_rejects_counts_without_chains"] = not evaluate(bad)["two_causal_structures"]
    result = {"passed": all(checks.values()), "checks": checks, "suites": suites,
              "scope": "RF3 E1 finite local emergence only. Mixed food stacks cite contributing batches, not exact per-meal units. Does not accept H2, thirty-day life, diplomacy, player experience, or human UI tests."}
    (args.directory / "e1_acceptance.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
