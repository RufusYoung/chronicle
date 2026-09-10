"""Read-only danger/life evidence. Temporal follow-up is not exclusive causation."""

import argparse
from collections import Counter
import json
from pathlib import Path

from audit_resident_life import audit as audit_life


def at(row):
    return row.get("day", 0) * 24 + row.get("hour", 0)


def audit(path):
    envelope = json.loads(path.read_text(encoding="utf-8-sig"))
    stores = envelope["stores"]
    facts = stores["facts"]
    index = {f["fact_id"]: f for f in facts}
    life = audit_life(path)
    rounds = [f for f in facts if f.get("fact_type") == "world_danger_round"]
    traits = [t for t in stores["character_features"]["trait_instances"]
              if t["trait_def_id"] == "trait.combat_bruising"]
    followups = []
    for trait in traits:
        owner = trait["owner_entity_id"]
        rest_ids = trait.get("recovery_fact_ids", [])
        healed = trait["stage_id"] == "healed"
        recovery_hour = max((at(index[i]) for i in rest_ids), default=-1)
        later = [f for f in facts if at(f) > recovery_hour]
        followups.append({
            "owner": owner, "trait_id": trait["trait_instance_id"],
            "injury_sources": trait["source_fact_ids"], "stage": trait["stage_id"],
            "recovery_hours": len(rest_ids), "last_recovery_hour": recovery_hour,
            "rest_sources": rest_ids,
            "later_work": [f["fact_id"] for f in later if healed and
                           f.get("fact_type") == "npc_livelihood_produced" and f.get("actor_id") == owner],
            "later_meals": [f["fact_id"] for f in later if healed and
                            f.get("fact_type") in {"npc_self_meal", "npc_household_shared_food", "npc_cross_household_shared_food"}
                            and f.get("target_id") == owner],
        })
    player_meals = sum(f.get("quantity", 1) for f in facts if f.get("fact_type") == "actor_ate_for_recovery")
    decision_types = {"resident_activity_changed", "npc_livelihood_produced", "world_danger_round"}
    danger_choices = [f for f in facts if f.get("fact_type") == "resident_activity_changed" and
                      any("danger" in str(c.get("factors", {})) for c in f.get("alternatives", []))]
    return {
        "evidence_kind": "read_only_checkpoint_audit", "checkpoint": str(path),
        "sha256": life["sha256"], "elapsed_hours": life["elapsed_hours"],
        "scope": "Same-person follow-up, not sole-cause attribution. No simulation or player input is performed by this audit.",
        "test_injections": [f["fact_id"] for f in facts if f.get("fact_type") == "test_injection"],
        "contacts": sum(f.get("fact_type") == "world_danger_contact" for f in facts),
        "rounds": len(rounds),
        "approaches": dict(Counter(f["approach_id"] + ":" + f["outcome"] for f in rounds)),
        "dispersals": [f for f in rounds if f.get("threat_dispersed")],
        "participants": sorted({f["actor_id"] for f in rounds}),
        "traits": dict(Counter(t["stage_id"] for t in traits)),
        "healed_then_worked": sum(bool(t["later_work"]) for t in followups),
        "healed_then_ate": sum(bool(t["later_meals"]) for t in followups),
        "injury_followups": followups,
        "personal_danger_choices": len(danger_choices),
        "life": {k: life[k] for k in ("hunger", "produced_food_portions", "consumed_meals",
                 "remaining_food_portions", "food_balance_remainder", "remaining_currency", "residents")},
        "player_recovery_meals": player_meals,
        "food_balance_after_player_recovery": life["food_balance_remainder"] - player_meals,
        "resident_states": {p["id"]: stores["states"][p["id"]] for p in life["residents"]},
        "threat_states": {i: s for i, s in stores["states"].items() if i.startswith("world_threat.")},
        "decision_trace": [f for f in facts if f.get("fact_type") in decision_types],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = audit(args.checkpoint)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("elapsed_hours", "contacts", "rounds", "traits", "healed_then_worked", "healed_then_ate", "food_balance_after_player_recovery")}, ensure_ascii=True))
