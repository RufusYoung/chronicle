"""Read-only causal audit of versioned content, lawful play and packaged parity."""

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
    definitions = read(PROJECT / "data/sim/raw/content/echo_port_life_v1.json")["item_defs"]
    added = {d["item_def_id"] for d in definitions}
    foods = {d["item_def_id"] for d in definitions if "food" in d["tags"]}
    tools = added - foods
    aggregate = {key: Counter() for key in added}
    meals = {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food", "actor_ate"}
    for seed in (81001, 86013):
        probe = read(root / f"probe_{seed}_168.json")
        native = read(root / f"probe_{seed}_168.save.json")
        state, fixture = native["stores"], native["bootstrap"]["fixture_data"]
        facts = {f["fact_id"]: f for f in state["facts"]}
        prefix = f"passive_{seed}"
        checks[prefix + ":same_native_truth"] = truth(native) == truth(probe["envelope"])
        checks[prefix + ":world_seed_preserved"] = fixture["world_danger"]["seed"] == seed
        checks[prefix + ":seven_days"] = probe["start_hours"] == 0 and native["world_time"]["elapsed_hours"] == 168
        checks[prefix + ":no_injection"] = not any(f.get("fact_type") == "test_injection" for f in facts.values())
        checks[prefix + ":finite_money"] = sum(i["quantity"] for i in state["items"] if i["item_def_id"] == "item.copper_coin") == sum(
            i["quantity"] for i in fixture["initial_items"] if i["item_def_id"] == "item.copper_coin")
        item_summary = {}
        for definition in added:
            items = [i for i in state["items"] if i["item_def_id"] == definition]
            counts = Counter(batches=len(items), remaining=sum(i["quantity"] for i in items))
            for item in items:
                source = item["provenance"].get("created_by_fact_id", "")
                checks[prefix + ":item_origin:" + item["item_instance_id"]] = source in facts
                for event in item.get("history", []):
                    source = event.get("fact_id", "")
                    checks[prefix + ":history_source:" + source] = source in facts
                    kind = facts.get(source, {}).get("fact_type")
                    if event["event_type"] == "consumed":
                        counts["eaten" if kind in meals else "material_used"] += event["quantity"]
                    if event["event_type"] == "durability_changed":
                        counts["wear"] += max(0, event["from"] - event["to"])
                    if event["event_type"] in {"transferred", "stack_split"} and kind == "work_supply_purchased":
                        counts["purchased_transfers"] += 1
                    if kind == "npc_food_debt_repaid":
                        counts["in_kind_debt_transfer"] += 1
            item_summary[definition] = dict(counts)
            aggregate[definition].update(counts)
        summaries[prefix] = {"seconds": probe["seconds"], "items": item_summary,
            "hunger": dict(Counter(s.get("hunger", "none") for i, s in state["states"].items() if i.startswith("generated_resident."))),
            "recipes": dict(Counter(f["recipe_id"] for f in facts.values() if f.get("fact_type") == "npc_livelihood_produced" and "recipe_id" in f))}
    for item in foods:
        checks[item + ":naturally_produced_and_eaten"] = aggregate[item]["batches"] > 0 and aggregate[item]["eaten"] > 0
    for item in tools:
        checks[item + ":naturally_produced_purchased_used"] = all(aggregate[item][key] > 0 for key in ("batches", "purchased_transfers", "wear"))
    for run, hours in (("play_81001_72", 72), ("play_86013_72", 72), ("week_81001", 168)):
        folder = root / run
        comparison = read(folder / "comparison.json")
        start = read(folder / "common_start.json")
        checks[run + ":policy_coverage"] = set(comparison) == ({"content_life"} if hours == 168 else {"observer", "content_life", "prepared", "local_gift"})
        start_coins = sum(i["quantity"] for i in start["stores"]["items"] if i["item_def_id"] == "item.copper_coin")
        for policy, summary in comparison.items():
            prefix = run + "/" + policy
            native_path = folder / (policy + ".native.json")
            native = read(native_path)
            rows = read(folder / (policy + ".transcript.json"))
            checks[prefix + ":same_start"] = summary["same_start_sha256"] == hashlib.sha256((folder / "common_start.json").read_bytes()).hexdigest()
            checks[prefix + ":native_hash"] = summary["save_sha256"] == hashlib.sha256(native_path.read_bytes()).hexdigest()
            checks[prefix + ":aligned"] = summary["elapsed_hours"] == native["world_time"]["elapsed_hours"] == hours
            checks[prefix + ":finite_money"] = summary["total_coins"] == start_coins
            checks[prefix + ":legal"] = all(any(c["enabled"] and c["choice_id"] == row["selected"] for c in row["offered"]) for row in rows)
            checks[prefix + ":continuous"] = rows[0]["before_time"]["elapsed_hours"] == 0 and rows[-1]["after_time"]["elapsed_hours"] == hours and all(
                row["after_time"]["elapsed_hours"] > row["before_time"]["elapsed_hours"] and (index == 0 or rows[index-1]["after_time"] == row["before_time"])
                for index, row in enumerate(rows))
            checks[prefix + ":no_injection"] = not any(f.get("fact_type") == "test_injection" for f in native["stores"]["facts"])
            checks[prefix + ":public_combat_feedback"] = all(not any(key in json.dumps(r.get("feedback", {})) for key in
                ("danger_round_hour", "danger_opponent_id", "danger_advantage")) for r in rows)
            if summary["combat_rounds"]:
                checks[prefix + ":tactical_information_retained"] = any("优势" in r.get("feedback", {}).get("body", "") for r in rows)
            summaries[prefix] = {"actions": len(rows), "waits": sum(r["selected"] == "wait/one_hour" for r in rows),
                "hunger": summary["hunger"], "player_food": summary["player"]["food_count"], "player_health": summary["player"]["health"],
                "gifts": len(summary["player_gifts"]), "combat_rounds": summary["combat_rounds"],
                "changed_residents": len(summary["changed_residents"]), "changed_balances": len(summary["changed_balances"])}
            if hours == 168:
                recipes = {f.get("recipe_id") for f in summary["production"]}
                checks[prefix + ":integrated_artisan_chain"] = {"recipe.reed_cordage", "recipe.double_light_cords", "recipe.net_fishing", "recipe.smoke_lake_fish"} <= recipes
                checks[prefix + ":shares_and_encounters"] = bool(summary["player_gifts"]) and summary["combat_rounds"] > 0
        if hours == 72:
            checks[run + ":two_of_three_material_interventions"] = sum(bool(comparison[p]["changed_residents"] or comparison[p]["changed_balances"])
                for p in ("content_life", "prepared", "local_gift")) >= 2
    proof = read(root / "data_only_proof.json")
    checks["heldout:all_passed"] = not proof["failures"] and proof["checks"] >= 34
    checks["heldout:runtime_still_frozen"] = all(hashlib.sha256((PROJECT / p.removeprefix("res://")).read_bytes()).hexdigest() == h for p, h in proof["runtime_hashes"].items())
    checks["heldout:all_runtime_scripts"] = set(proof["runtime_hashes"]) == {"res://" + p.relative_to(PROJECT).as_posix() for p in (PROJECT / "scripts").rglob("*.gd")}
    original = read(root / "simulation_freeze_proof.json")["runtime_hashes"]
    checks["simulation:unchanged_after_freeze"] = {p for p, h in original.items() if proof["runtime_hashes"].get(p) != h} <= {
        "res://scripts/rebuild/v5_live_location_view_model.gd"}
    results = read(root / "frozen_regression/results.json")
    expected = {p.relative_to(PROJECT).as_posix() for p in (PROJECT / "tests").rglob("*.gd") if p.name != "generated_world_30_day_health_test.gd"}
    checks["regression:complete"] = {r["Test"] for r in results} == expected
    checks["regression:passed"] = all(r["Passed"] for r in results)
    rendered = read(root / "final_render/results.json")
    checks["render:final_complete"] = {r["Test"] for r in rendered} == {p for p in expected if p.endswith("_render_test.gd")}
    checks["render:final_passed"] = all(r["Passed"] for r in rendered)
    checks["render:legal_week"] = read(root / "content_week_render/result.json")["passed"]
    if package:
        build = read(package / "build_manifest.json")
        checks["package:clean"] = build["sourceDirty"] is False
        checks["package:binary_hashes"] = all(hashlib.sha256((package / row["name"]).read_bytes()).hexdigest().upper() == row["sha256"] for row in build["files"])
        checks["package:source_identity"] = subprocess.run(["git", "diff", "--quiet", build["sourceCommit"], "--", "chronicle-godot/scripts", "chronicle-godot/data", "chronicle-godot/scenes", "chronicle-godot/art"], cwd=PROJECT.parent).returncode == 0
        for policy in ("observer", "content_life", "prepared", "local_gift"):
            checks["package:parity:" + policy] = truth(read(root / "play_81001_72" / (policy + ".native.json"))) == truth(read(root / "packaged_81001_72" / (policy + ".native.json")))
        for name in ("content_week", "old_v2_week", "legacy_day30"):
            checks["package:render:" + name] = read(root / ("package_" + name + ".json"))["passed"]
    result = {"passed": all(checks.values()), "checks": checks, "summaries": summaries,
        "boundary": "Two-seed passive week, legal agent play, controlled data-only extension and rendering. Not human play, nutrition, ecology or general profitable planning."}
    (root / ("package_audit.json" if package else "source_audit.json")).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for key, ok in checks.items():
        if not ok:
            print("FAIL " + key)
    print(f"WORLD_CONTENT_AUDIT {sum(checks.values())}/{len(checks)}")
    return result["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if audit(args.evidence, args.package) else 1)
