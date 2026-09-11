"""Audit recorded legal play, native state, runtime freeze and optional package parity."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

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
    observer = read(root / "tool_observer/comparison.json")["observer"]
    tool_start = read(root / "frozen_tool/common_start.json")
    observer_start = read(root / "tool_observer/common_start.json")
    checks["tool:observer_equal_initial_truth_and_time"] = all(tool_start[key] == observer_start[key]
        for key in ("bootstrap", "definition_manifest", "stores", "session", "world_time", "rng_states", "world_log", "agent_control")) and observer["elapsed_hours"] == tool["elapsed_hours"]
    summaries["tool_vs_observer"] = {
        "observer_hunger": observer["hunger"], "tool_hunger": tool["hunger"],
        "comparison_scope": "Equal initial native game truth, not byte-identical files: save_id and wall-clock save timestamps differ. The four-policy E3 branches separately share their exact native file.",
        "changed_residents": {actor: {key: [observer["resident_states"][actor].get(key), state.get(key)]
                              for key in ("hunger", "health", "livelihood_cycle_count")
                              if state.get(key) != observer["resident_states"][actor].get(key)}
                              for actor, state in tool["resident_states"].items()},
    }
    summaries["tool_vs_observer"]["changed_residents"] = {actor: state for actor, state in summaries["tool_vs_observer"]["changed_residents"].items() if state}
    manifest = read(root / "runtime_manifest.json")
    checks["runtime:unchanged"] = all(hashlib.sha256((PROJECT / row["Path"]).read_bytes()).hexdigest().upper() == row["SHA256"] for row in manifest)
    simulation_manifest = {row["Path"]: row["SHA256"] for row in read(root / "simulation_runtime_manifest.json")}
    changed = [row["Path"] for row in manifest if simulation_manifest.get(row["Path"]) != row["SHA256"]]
    checks["runtime:simulation_freeze_preserved"] = all(Path(path).as_posix() == "scripts/rebuild/v5_live_location_viewer.gd" for path in changed)
    regression = read(root / "frozen_regression/results.json")
    expected = {str(path.relative_to(PROJECT)).replace("\\", "/") for path in (PROJECT / "tests").rglob("*.gd")
                if path.name != "generated_world_30_day_health_test.gd"}
    checks["regression:complete_discovery"] = {row["Test"] for row in regression} == expected
    checks["regression:all_passed"] = all(row["Passed"] for row in regression)
    final_render = read(root / "final_render/results.json")
    checks["regression:final_presentation_passed"] = {row["Test"] for row in final_render} == {name for name in expected if name.endswith("_render_test.gd")} and all(row["Passed"] for row in final_render)
    if package:
        build = read(package / "build_manifest.json")
        checks["package:clean_source"] = build["sourceDirty"] is False
        prefix = PROJECT.name + "/"
        tracked = set(subprocess.check_output(["git", "ls-tree", "-r", "-z", "--name-only", build["sourceCommit"], "--",
            prefix + "scripts", prefix + "data", prefix + "scenes"], cwd=PROJECT.parent).decode("utf-8").split("\0"))
        checks["package:runtime_matches_export_commit"] = all(prefix + Path(row["Path"]).as_posix() in tracked for row in manifest) and subprocess.run(
            ["git", "diff", "--quiet", build["sourceCommit"], "--", prefix + "scripts", prefix + "data", prefix + "scenes"], cwd=PROJECT.parent).returncode == 0
        checks["package:binary_hashes"] = all(hashlib.sha256((package / row["name"]).read_bytes()).hexdigest().upper() == row["sha256"] for row in build["files"])
        for policy in ("observer", "prepared", "direct_risk", "local_help"):
            source = read(root / "frozen_81001" / f"{policy}.native.json")
            packed = read(root / "packaged_final_81001" / f"{policy}.native.json")
            checks["package:native_parity:" + policy] = all(source[key] == packed[key] for key in ("stores", "world_time", "rng_states", "session", "world_log"))
    report = {"passed": all(checks.values()), "checks": checks, "summaries": summaries,
              "tool_recipes": dict(recipes), "runtime_files": len(manifest),
              "presentation_only_changes_since_simulation_freeze": changed,
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
