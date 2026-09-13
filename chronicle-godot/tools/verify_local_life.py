"""Audit RF6 v2 recorded legal play without changing the game or its evidence."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

from agent_play import PROJECT


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def truth(envelope):
    return {key: envelope[key] for key in
            ("bootstrap", "definition_manifest", "stores", "session", "world_time", "rng_states", "world_log")}


def audit(root, package=None):
    checks, summaries = {}, {}
    for run in ("frozen_81001", "heldout_86013", "week_81001"):
        directory = root / run
        comparison = read(directory / "comparison.json")
        start_path = directory / "common_start.json"
        start = read(start_path)
        initial_coins = sum(i["quantity"] for i in start["stores"]["items"] if i["item_def_id"] == "item.copper_coin")
        expected_hours = 168 if run.startswith("week") else 72
        checks[run + ":policies"] = set(comparison) == ({"observer", "local_trade", "local_gift"} if expected_hours == 168
                                                        else {"observer", "local_trade", "local_gift", "prepared"})
        for policy, summary in comparison.items():
            key = run + "/" + policy
            native_path = directory / (policy + ".native.json")
            native = read(native_path)
            transcript = read(directory / (policy + ".transcript.json"))
            facts = native["stores"]["facts"]
            by_id = {f["fact_id"]: f for f in facts}
            coins = sum(i["quantity"] for i in native["stores"]["items"] if i["item_def_id"] == "item.copper_coin")
            checks[key + ":aligned"] = native["world_time"]["elapsed_hours"] == summary["elapsed_hours"] == expected_hours
            checks[key + ":same_native_start"] = summary["same_start_sha256"] == hashlib.sha256(start_path.read_bytes()).hexdigest()
            checks[key + ":native_hash"] = summary["save_sha256"] == hashlib.sha256(native_path.read_bytes()).hexdigest()
            checks[key + ":finite_money"] = coins == initial_coins == summary["total_coins"]
            checks[key + ":no_injection"] = not any(f.get("fact_type") == "test_injection" for f in facts)
            checks[key + ":legal_choices"] = bool(transcript) and all(any(c["enabled"] and c["choice_id"] == row["selected"]
                                                                         for c in row["offered"]) for row in transcript)
            checks[key + ":continuous_clock"] = transcript[0]["before_time"]["elapsed_hours"] == 0 and all(
                row["after_time"]["elapsed_hours"] > row["before_time"]["elapsed_hours"] and
                (index == 0 or transcript[index - 1]["after_time"] == row["before_time"])
                for index, row in enumerate(transcript)) and transcript[-1]["after_time"]["elapsed_hours"] == expected_hours
            exchanges = [f for f in facts if f.get("fact_type") in {"player_food_sold", "player_food_given"}]
            contributions = {f["fact_id"] for f in exchanges}
            followups = [f for f in facts if f.get("fact_type") in {"npc_self_meal", "household_pantry_stored", "household_food_delivered",
                         "npc_household_shared_food", "npc_cross_household_shared_food"} and contributions.intersection(f.get("source_fact_ids", []))]
            if policy in {"local_trade", "local_gift"}:
                checks[key + ":real_exchange"] = bool(exchanges)
                checks[key + ":later_physical_use"] = bool(followups)
                checks[key + ":public_information"] = bool(summary["local_information"])
                checks[key + ":visible_consequence"] = any(row["witnessed_followups"] for row in transcript)
            clearance = summary["work_after_danger"]
            checks[key + ":danger_sources_exist"] = all(f["danger_clearance_source_id"] in by_id and
                all(source in by_id for source in f.get("source_fact_ids", [])) for f in clearance)
            kinds = Counter(row["selected"].split("/", 1)[0] for row in transcript)
            summaries[key] = {"hours": expected_hours, "actions": len(transcript), "waits": sum(row["selected"] == "wait/one_hour" for row in transcript),
                              "action_kinds": dict(kinds), "food": summary["player"]["food_count"], "coins": summary["player"]["coins"],
                              "hunger": summary["hunger"], "sales": len(summary["player_sales"]), "gifts": len(summary["player_gifts"]),
                              "later_food_uses": len(followups), "work_after_danger": len(clearance),
                              "changed_residents": len(summary["changed_residents"]), "changed_balances": len(summary["changed_balances"])}
        checks[run + ":two_material_strategies"] = all(comparison[p]["changed_residents"] or comparison[p]["changed_balances"]
                                                       for p in ("local_trade", "local_gift"))
    prepared = read(root / "frozen_81001/comparison.json")["prepared"]
    checks["danger:actual_work_and_visible_aftermath"] = bool(prepared["work_after_danger"]) and bool(prepared["witnessed_followups"])
    manifest = read(root / "runtime_manifest.json")
    checks["runtime:unchanged"] = all(hashlib.sha256((PROJECT / row["Path"]).read_bytes()).hexdigest().upper() == row["SHA256"] for row in manifest)
    expected = {str(p.relative_to(PROJECT)).replace("\\", "/") for p in (PROJECT / "tests").rglob("*.gd")
                if p.name != "generated_world_30_day_health_test.gd"}
    regression = read(root / "frozen_regression/results.json")
    checks["regression:complete_discovery"] = {row["Test"] for row in regression} == expected
    reruns = read(root / "scoped_rerun/results.json")
    if isinstance(reruns, dict):
        reruns = [reruns]
    final_results = {row["Test"]: row for row in regression}
    final_results.update({row["Test"]: row for row in reruns})
    checks["regression:scoped_rerun_only_known_tests"] = {row["Test"] for row in reruns} <= expected
    checks["regression:all_final_passed"] = all(row["Passed"] for row in final_results.values())
    checks["render:natural_danger_checkpoint"] = read(root / "natural_danger_render/result.json")["passed"]
    if package:
        build = read(package / "build_manifest.json")
        checks["package:clean_source"] = build["sourceDirty"] is False
        prefix = PROJECT.name + "/"
        tracked = set(subprocess.check_output(["git", "ls-tree", "-r", "-z", "--name-only", build["sourceCommit"], "--",
            prefix + "scripts", prefix + "data", prefix + "scenes"], cwd=PROJECT.parent).decode("utf-8").split("\0"))
        checks["package:runtime_matches_export_source"] = all(prefix + Path(row["Path"]).as_posix() in tracked for row in manifest) and subprocess.run(
            ["git", "diff", "--quiet", build["sourceCommit"], "--", prefix + "scripts", prefix + "data", prefix + "scenes"], cwd=PROJECT.parent).returncode == 0
        checks["package:binary_hashes"] = all(hashlib.sha256((package / row["name"]).read_bytes()).hexdigest().upper() == row["sha256"] for row in build["files"])
        for policy in ("observer", "local_trade", "local_gift", "prepared"):
            checks["package:native_parity:" + policy] = truth(read(root / "frozen_81001" / (policy + ".native.json"))) == truth(
                read(root / "packaged_81001" / (policy + ".native.json")))
        for probe in ("v2_week", "v1_week", "legacy_day30"):
            result = read(root / ("package_" + probe + ".json"))
            checks["package:render:" + probe] = result["passed"] and result["sample"]["ok"]
    result = {"passed": all(checks.values()), "checks": checks, "summaries": summaries, "runtime_files": len(manifest),
              "boundary": "Legal code-agent play and program-driven render evidence. Not human play, fun, full RF6, balanced welfare, or unique food-unit lineage."}
    output = root / ("package_audit.json" if package else "source_audit.json")
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for key, ok in checks.items():
        if not ok:
            print("FAIL " + key)
    print(f"LOCAL_LIFE_AUDIT {sum(checks.values())}/{len(checks)}")
    return result["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if audit(args.evidence, args.package) else 1)
