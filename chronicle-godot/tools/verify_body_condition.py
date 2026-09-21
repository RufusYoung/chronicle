"""Audit frozen shared-body rules, legal policies and a real Windows package."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess

from agent_play import PROJECT
from verify_local_life import read, truth


def hashes():
    return {str(p.relative_to(PROJECT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest()
            for folder in ("scripts", "data", "scenes") for p in sorted((PROJECT / folder).rglob("*"))
            if p.suffix in {".gd", ".json", ".tscn"}}


def audit(root, package=None):
    checks, summaries = {}, {}
    checks["frozen_runtime"] = read(root / "runtime_hashes.json") == hashes()
    before_layout = read(root / "exploratory/pre_duplicate_layout_runtime_hashes.json")
    changed = {p for p, value in hashes().items() if before_layout.get(p) != value}
    checks["simulation_unchanged_during_layout"] = changed <= {
        "scripts/rebuild/v5_live_location_viewer.gd", "scripts/rebuild/v5_shared_world_surface.gd"}

    def state(label, native):
        stores = native["stores"]
        fixture = native["bootstrap"]["fixture_data"]
        checks[label + ":version"] = fixture["body_rules"]["version"] == 1
        checks[label + ":money"] = sum(i["quantity"] for i in stores["items"] if i["item_def_id"] == "item.copper_coin") == sum(
            i["quantity"] for i in fixture["initial_items"] if i["item_def_id"] == "item.copper_coin")
        checks[label + ":no_injection"] = not any(f.get("fact_type") == "test_injection" for f in stores["facts"])
        people = {k: v for k, v in stores["states"].items() if k.startswith("generated_resident.")}
        strain = [f for f in stores["facts"] if f.get("fact_type") == "actor_hunger_strain"]
        checks[label + ":finite_strain"] = bool(strain) and all(f["health_after"] >= 40 and f["health_before"] > f["health_after"] for f in strain)
        return {"player_health": stores["states"]["player"]["health"],
                "extreme_residents": sum(p.get("hunger") == "extreme" for p in people.values()),
                "resident_health": {k: p.get("health", 100) for k, p in people.items()},
                "hunger_strain_by_actor": dict(Counter(f["actor_id"] for f in strain)),
                "production_by_actor": dict(Counter(f["actor_id"] for f in stores["facts"] if f.get("fact_type") == "npc_livelihood_produced")),
                "meals_by_actor": dict(Counter(f.get("target_id", f.get("actor_id")) for f in stores["facts"] if f.get("fact_type") in {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}))}

    for seed in (81001, 86013):
        native = read(root / f"probe_{seed}_168.save.json")
        label = f"passive_{seed}"
        checks[label + ":week"] = native["world_time"]["elapsed_hours"] == 168
        summaries[label] = state(label, native)

    for folder_name, hours in (("source_81001", 72), ("heldout_86013", 72), ("week_81001", 168)):
        folder = root / folder_name
        comparison = read(folder / "comparison.json")
        start_hash = hashlib.sha256((folder / "common_start.json").read_bytes()).hexdigest()
        checks[folder_name + ":policies"] = set(comparison) == {"observer", "provisions", "local_gift"}
        for policy, summary in comparison.items():
            label = folder_name + "/" + policy
            native = read(folder / f"{policy}.native.json")
            records = read(folder / f"{policy}.transcript.json")
            checks[label + ":same_start"] = summary["same_start_sha256"] == start_hash
            checks[label + ":native_hash"] = summary["save_sha256"] == hashlib.sha256((folder / f"{policy}.native.json").read_bytes()).hexdigest()
            checks[label + ":time"] = native["world_time"]["elapsed_hours"] == hours
            checks[label + ":legal"] = all(any(c["enabled"] and c["choice_id"] == r["selected"] for c in r["offered"]) for r in records)
            checks[label + ":continuous"] = records[0]["before_time"]["elapsed_hours"] == 0 and records[-1]["after_time"]["elapsed_hours"] == hours and all(
                r["after_time"]["elapsed_hours"] > r["before_time"]["elapsed_hours"] and (i == 0 or records[i-1]["after_time"] == r["before_time"]) for i, r in enumerate(records))
            summaries[label] = state(label, native)
            summaries[label].update(actions=len(records), waits=sum(r["selected"] == "wait/one_hour" for r in records),
                                    food=summary["player"]["food_count"], coins=summary["player"]["coins"],
                                    combat_rounds=summary["combat_rounds"], gifts=len(summary["player_gifts"]),
                                    changed_residents=len(summary["changed_residents"]))
            checks[label + ":expected_health"] = native["stores"]["states"]["player"]["health"] == (50 if hours == 168 else 82) if policy == "observer" else native["stores"]["states"]["player"]["health"] > 50
            if policy == "provisions":
                recipes = {f.get("recipe_id") for f in summary["production"]}
                checks[label + ":real_trip"] = {"recipe.hand_gather.net_fisher", "recipe.smoke_lake_fish", "recipe.hand_gather.terrace_farmer", "recipe.roast_roots"} <= recipes and summary["provisions_stage"] == "home_life"
                checks[label + ":real_sharing"] = bool(summary["player_gifts"])
    results = read(root / "regression/results.json")
    expected = {p.relative_to(PROJECT).as_posix() for p in (PROJECT / "tests").rglob("*.gd") if p.name != "generated_world_30_day_health_test.gd"}
    checks["regression_coverage"] = {r["Test"] for r in results} == expected
    checks["regression_pass"] = all(r["Passed"] for r in results)
    contract = read(root / "contract_final/results.json")
    if isinstance(contract, dict):
        contract = [contract]
    checks["strengthened_contract"] = len(contract) == 1 and contract[0]["Passed"]
    rendered = read(root / "final_render/results.json")
    checks["render_coverage"] = {r["Test"] for r in rendered} == {p for p in expected if p.endswith("_render_test.gd")}
    checks["render_pass"] = all(r["Passed"] for r in rendered)
    for name in ("week_render", "observer_render"):
        checks[name] = read(root / name / "result.json")["passed"]
    protocol = (root / "source_protocol_final.log").read_text(encoding="utf-8-sig")
    checks["source_protocol"] = "Ran 18 tests" in protocol and protocol.rstrip().endswith("OK")
    if package:
        manifest = read(package / "build_manifest.json")
        checks["package_clean"] = manifest["sourceDirty"] is False
        checks["package_hashes"] = all(hashlib.sha256((package / f["name"]).read_bytes()).hexdigest().upper() == f["sha256"] for f in manifest["files"])
        checks["package_source"] = subprocess.run(["git", "diff", "--quiet", manifest["sourceCommit"], "--", "chronicle-godot/scripts", "chronicle-godot/data", "chronicle-godot/scenes"], cwd=PROJECT.parent).returncode == 0
        for policy in ("observer", "provisions", "local_gift"):
            checks["package_truth:" + policy] = truth(read(root / "source_81001" / f"{policy}.native.json")) == truth(read(root / "packaged_81001" / f"{policy}.native.json"))
        for name in ("body_week", "old_provisions_week", "legacy_day30"):
            checks["package_render:" + name] = read(root / f"package_{name}.json")["passed"]
        log = (root / "package_protocol.log").read_text(encoding="utf-8-sig")
        checks["package_protocol"] = "Ran 18 tests" in log and log.rstrip().endswith("OK")
        checks["package_startup"] = read(root / "package_startup.json")["passed"]
    report = {"passed": all(checks.values()), "checks": checks, "summaries": summaries,
              "boundary": "Versioned limited hunger costs and self-rescue, not full nutrition, permanent death or human play."}
    (root / ("package_audit.json" if package else "source_audit.json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"BODY_CONDITION_AUDIT {sum(checks.values())}/{len(checks)}")
    for key, ok in checks.items():
        if not ok:
            print("FAIL", key)
    return report["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--package", type=Path)
    parser.add_argument("--freeze", action="store_true")
    args = parser.parse_args()
    if args.freeze:
        with (args.evidence / "runtime_hashes.json").open("x", encoding="utf-8") as stream:
            json.dump(hashes(), stream, indent=2)
    else:
        raise SystemExit(0 if audit(args.evidence, args.package) else 1)
