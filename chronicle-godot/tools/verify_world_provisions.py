"""Audit real provisions, finite visitor rights, legal play and package parity."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

from agent_play import PROJECT
from verify_local_life import read, truth


def audit(root, package=None):
    checks, summaries = {}, {}

    def world(prefix, native):
        stores, fixture = native["stores"], native["bootstrap"]["fixture_data"]
        config = fixture["content_extension"]
        checks[prefix + ":versioned"] = config["version"] == 2
        checks[prefix + ":finite_currency"] = sum(i["quantity"] for i in stores["items"] if i["item_def_id"] == "item.copper_coin") == sum(
            i["quantity"] for i in fixture["initial_items"] if i["item_def_id"] == "item.copper_coin")
        facts = {f["fact_id"]: f for f in stores["facts"]}
        checks[prefix + ":no_injection"] = not any(f.get("fact_type") == "test_injection" for f in facts.values())
        meals = Counter()
        for item in stores["items"]:
            benefit = config["meal_rules"]["foods"].get(item["item_def_id"], {}).get("satiation_hours", 0)
            if not benefit:
                continue
            for event in item.get("history", []):
                fact = facts.get(event.get("fact_id"), {})
                if event["event_type"] != "consumed" or fact.get("fact_type") not in {
                    "npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food", "actor_ate", "actor_ate_for_recovery"
                }:
                    continue
                checks[prefix + ":meal:" + fact["fact_id"]] = fact.get("satiation_hours") == benefit
                meals[item["item_def_id"]] += event["quantity"]
        initial = {s["stock_id"]: s for s in fixture["initial_resource_stocks"]}
        visitor_spending = {}
        for stock in stores.get("resource_stocks", []):
            access = stock.get("access", {})
            if access.get("version") != 2:
                continue
            checks[prefix + ":rights:" + stock["stock_id"]] = access["visitors"] == initial[stock["stock_id"]]["access"]["visitors"]
            checks[prefix + ":quota:" + stock["stock_id"]] = all(0 <= u["amount"] <= access["visitors"]["daily_limit"] for u in access["visitor_usage"].values())
            if "player" in access["visitor_usage"]:
                visitor_spending[stock["stock_id"]] = access["visitor_usage"]["player"]
        return {"processed_meals": dict(meals), "visitor_spending": visitor_spending}

    for seed in (81001, 86013):
        native = read(root / f"probe_{seed}_168.save.json")
        probe = read(root / f"probe_{seed}_168.json")
        prefix = f"passive_{seed}"
        checks[prefix + ":native_truth"] = truth(native) == truth(probe["envelope"])
        checks[prefix + ":week"] = native["world_time"]["elapsed_hours"] == 168
        summaries[prefix] = world(prefix, native)
        summaries[prefix]["seconds"] = probe["seconds"]
        checks[prefix + ":real_processed_meals"] = sum(summaries[prefix]["processed_meals"].values()) > 0

    for run in ("source_81001", "heldout_86013", "week_81001"):
        folder = root / run
        comparison = read(folder / "comparison.json")
        start_hash = hashlib.sha256((folder / "common_start.json").read_bytes()).hexdigest()
        expected_hours = 168 if run.startswith("week") else 72
        checks[run + ":policy_coverage"] = set(comparison) == ({"observer", "provisions"} if expected_hours == 168 else {"observer", "provisions", "local_gift"})
        for policy, summary in comparison.items():
            prefix = run + "/" + policy
            path = folder / f"{policy}.native.json"
            native = read(path)
            records = read(folder / f"{policy}.transcript.json")
            checks[prefix + ":same_start"] = summary["same_start_sha256"] == start_hash
            checks[prefix + ":native_hash"] = summary["save_sha256"] == hashlib.sha256(path.read_bytes()).hexdigest()
            checks[prefix + ":aligned"] = summary["elapsed_hours"] == native["world_time"]["elapsed_hours"] == expected_hours
            checks[prefix + ":legal"] = all(any(c["enabled"] and c["choice_id"] == r["selected"] for c in r["offered"]) for r in records)
            checks[prefix + ":continuous"] = records[0]["before_time"]["elapsed_hours"] == 0 and records[-1]["after_time"]["elapsed_hours"] == expected_hours and all(
                r["after_time"]["elapsed_hours"] > r["before_time"]["elapsed_hours"] and (i == 0 or records[i-1]["after_time"] == r["before_time"]) for i, r in enumerate(records))
            summaries[prefix] = world(prefix, native)
            summaries[prefix].update(actions=len(records), waits=sum(r["selected"] == "wait/one_hour" for r in records),
                hunger=summary["hunger"], player_health=summary["player"]["health"], player_food=summary["player"]["food_count"],
                combat_rounds=summary["combat_rounds"], gifts=len(summary["player_gifts"]), changed_residents=len(summary["changed_residents"]))
            if policy == "provisions":
                recipes = {f.get("recipe_id") for f in summary["production"]}
                checks[prefix + ":real_trip_chain"] = {"recipe.hand_gather.net_fisher", "recipe.smoke_lake_fish", "recipe.hand_gather.terrace_farmer", "recipe.roast_roots"} <= recipes
                checks[prefix + ":visitor_rights_spent"] = bool(summaries[prefix]["visitor_spending"])
                checks[prefix + ":trip_returns"] = summary["provisions_stage"] == "home_life"
                checks[prefix + ":shares_owned_food"] = bool(summary["player_gifts"])
                checks[prefix + ":no_naturalization"] = native["stores"]["states"]["player"]["settlement_id"] == native["bootstrap"]["fixture_data"]["player_life_generated"]["settlement_id"]

    proof = read(root / "data_only_proof.json")
    checks["data_only:passed"] = not proof["failures"] and proof["checks"] >= 36
    checks["data_only:runtime_hashes"] = all(hashlib.sha256((PROJECT / p.removeprefix("res://")).read_bytes()).hexdigest() == h for p, h in proof["runtime_hashes"].items())
    checks["data_only:complete_runtime"] = set(proof["runtime_hashes"]) == {"res://" + p.relative_to(PROJECT).as_posix() for p in (PROJECT / "scripts").rglob("*.gd")}
    results = read(root / "regression/results.json")
    effective = {r["Test"]: r for r in results}
    retry = read(root / "recheck/results.json")
    if isinstance(retry, dict):
        retry = [retry]
    effective.update({r["Test"]: r for r in retry})
    expected = {p.relative_to(PROJECT).as_posix() for p in (PROJECT / "tests").rglob("*.gd") if p.name != "generated_world_30_day_health_test.gd"}
    checks["regression:complete"] = set(effective) == expected
    checks["regression:passed_after_recorded_recheck"] = all(r["Passed"] for r in effective.values())
    rendered = {r["Test"]: r for r in read(root / "final_render/results.json")}
    for path in sorted((root / "render_recheck").glob("*/results.json")):
        retry = read(path)
        if isinstance(retry, dict):
            retry = [retry]
        rendered.update({r["Test"]: r for r in retry})
    checks["render:complete"] = set(rendered) == {p for p in expected if p.endswith("_render_test.gd")}
    checks["render:passed_after_recorded_recheck"] = all(r["Passed"] for r in rendered.values())
    for policy in ("observer", "provisions", "local_gift"):
        checks["presentation_only:full_truth:" + policy] = truth(read(root / "source_81001" / f"{policy}.native.json")) == truth(read(root / "final_source_81001" / f"{policy}.native.json"))
    checks["render:legal_week"] = read(root / "week_render/result.json")["passed"]
    if package:
        manifest = read(package / "build_manifest.json")
        checks["package:clean"] = manifest["sourceDirty"] is False
        checks["package:hashes"] = all(hashlib.sha256((package / f["name"]).read_bytes()).hexdigest().upper() == f["sha256"] for f in manifest["files"])
        checks["package:runtime_identity"] = subprocess.run(["git", "diff", "--quiet", manifest["sourceCommit"], "--", "chronicle-godot/scripts", "chronicle-godot/data", "chronicle-godot/scenes", "chronicle-godot/art"], cwd=PROJECT.parent).returncode == 0
        for policy in ("observer", "provisions", "local_gift"):
            checks["package:parity:" + policy] = truth(read(root / "source_81001" / f"{policy}.native.json")) == truth(read(root / "packaged_81001" / f"{policy}.native.json"))
        for name in ("provisions_week", "old_content_week", "legacy_day30"):
            checks["package:render:" + name] = read(root / f"package_{name}.json")["passed"]
    report = {"passed": all(checks.values()), "checks": dict(sorted(checks.items())), "summaries": summaries,
        "boundary": "Legal code-agent play, passive worlds, controlled counterexamples and actual rendering; not human play, preservation, full nutrition or a finished first experience."}
    (root / ("package_audit.json" if package else "source_audit.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, passed in checks.items():
        if not passed:
            print("FAIL", name)
    print(f"WORLD_PROVISIONS_AUDIT {sum(checks.values())}/{len(checks)}")
    return report["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if audit(args.evidence, args.package) else 1)
