"""Audit recorded legal play, native state, runtime freeze and optional package parity."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from agent_play import PROJECT


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def audit(root, package=None):
    checks = {}
    summaries = {}
    for name in ("frozen_81001", "heldout_85005", "frozen_tool"):
        directory = root / name
        comparison = read(directory / "comparison.json")
        initial = read(directory / "common_start.json")
        coins = sum(i["quantity"] for i in initial["stores"]["items"] if i["item_def_id"] == "item.copper_coin")
        for policy, summary in comparison.items():
            key = f"{name}/{policy}"
            native = read(directory / f"{policy}.native.json")
            transcript = read(directory / f"{policy}.transcript.json")
            checks[key + ":aligned"] = native["world_time"]["elapsed_hours"] == summary["elapsed_hours"]
            checks[key + ":no_injection"] = not any(f.get("fact_type") == "test_injection" for f in native["stores"]["facts"])
            checks[key + ":finite_money"] = summary["total_coins"] == coins
            checks[key + ":same_start"] = summary["same_start_sha256"] == hashlib.sha256((directory / "common_start.json").read_bytes()).hexdigest()
            checks[key + ":legal_actions"] = all(any(c["choice_id"] == row["selected"] and c["enabled"] for c in row["offered"]) for row in transcript)
            kinds = Counter(row["selected"].split("/", 1)[0] for row in transcript)
            summaries[key] = {
                "elapsed_hours": summary["elapsed_hours"], "actions": len(transcript), "action_kinds": dict(kinds),
                "waits": sum(row["selected"] == "wait/one_hour" for row in transcript),
                "player_food": summary["player"]["food_count"], "player_coins": summary["player"]["coins"],
                "known_followups": len(summary["witnessed_followups"]), "hunger": summary["hunger"],
                "changed_residents": summary["changed_residents"], "changed_balances": summary["changed_balances"],
            }
        if name != "frozen_tool":
            checks[name + ":four_policies"] = set(comparison) == {"observer", "prepared", "direct_risk", "local_help"}
            checks[name + ":two_materially_different_strategies"] = all(
                comparison[p]["changed_residents"] or comparison[p]["changed_balances"] for p in ("prepared", "local_help"))
            checks[name + ":local_report"] = bool(comparison["local_help"]["witnessed_followups"])
    tool = read(root / "frozen_tool/comparison.json")["tool_life"]
    recipes = Counter(f.get("recipe_id", "") for f in tool["production"])
    checks["tool:earned_income"] = len(tool["hired_work"]) >= 2
    checks["tool:actual_purchase"] = tool["player_facts"].get("work_supply_purchased", 0) > 0
    checks["tool:use_to_exhaustion"] = recipes["recipe.net_fishing"] >= 4
    checks["tool:actual_maintenance"] = tool["player_facts"].get("npc_work_maintained", 0) > 0
    checks["tool:finished_nonfood_recipe"] = recipes["recipe.reed_cordage"] > 0
    checks["tool:inventory_contains_new_tool"] = sum(i["quantity"] for i in tool["player"]["inventory"] if i["definition_id"] == "item.fiber_rope") > 1
    manifest = read(root / "runtime_manifest.json")
    checks["runtime:unchanged"] = all(hashlib.sha256((PROJECT / row["Path"]).read_bytes()).hexdigest().upper() == row["SHA256"] for row in manifest)
    if package:
        build = read(package / "build_manifest.json")
        checks["package:clean_source"] = build["sourceDirty"] is False
        checks["package:binary_hashes"] = all(hashlib.sha256((package / row["name"]).read_bytes()).hexdigest().upper() == row["sha256"] for row in build["files"])
        for policy in ("observer", "prepared", "direct_risk", "local_help"):
            source = read(root / "frozen_81001" / f"{policy}.native.json")
            packed = read(root / "packaged_81001" / f"{policy}.native.json")
            checks["package:native_parity:" + policy] = all(source[key] == packed[key] for key in ("stores", "world_time", "rng_states", "session", "world_log"))
    report = {"passed": all(checks.values()), "checks": checks, "summaries": summaries,
              "tool_recipes": dict(recipes), "runtime_files": len(manifest),
              "boundary": "Legal code-agent evidence, not human play, fun, full RF6, or universal welfare improvement. Danger-to-resident causality remains hard to read in the current UI."}
    (root / ("package_audit.json" if package else "source_audit.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    for name, passed in checks.items():
        if not passed:
            print("FAIL " + name)
    print(f"PLAYER_LIFE_AUDIT {sum(checks.values())}/{len(checks)}")
    return report["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if audit(args.evidence, args.package) else 1)
