"""Audit public, stepwise play logs for choice-created follow-up problems.

This is a diagnostic projection, not a game rule or proof of player interest.
Unknown/private consequences remain unknown; no inspect command is used.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def legal_choices(response: dict) -> dict[str, str]:
    return {
        row["choice_id"]: row.get("label", row["choice_id"])
        for row in response.get("choices", [])
        if row.get("enabled", row.get("can_execute", True))
    }


def holdings(player: dict) -> dict[str, int]:
    return {
        item["id"]: item.get("quantity", 1)
        for item in player.get("inventory", [])
        if isinstance(item, dict) and "id" in item
    }


def followup(before: dict, after: dict, choice_id: str) -> dict:
    old = before.get("observation", {})
    new = after.get("observation", {})
    left, right = old.get("player", {}), new.get("player", {})
    changes: list[str] = []
    for key in ("coins", "food_count", "health", "fatigue", "hunger", "injury"):
        if key in left and key in right and left[key] != right[key]:
            changes.append(f"player.{key}: {left[key]} -> {right[key]}")
    old_location = old.get("location", {}).get("id")
    new_location = new.get("location", {}).get("id")
    if old_location != new_location:
        changes.append(f"location: {old_location} -> {new_location}")
    old_items, new_items = holdings(left), holdings(right)
    for item_id in sorted(old_items.keys() | new_items.keys()):
        if old_items.get(item_id, 0) != new_items.get(item_id, 0):
            changes.append(f"owned.{item_id}: {old_items.get(item_id, 0)} -> {new_items.get(item_id, 0)}")
    old_choices, new_choices = legal_choices(before), legal_choices(after)
    lost = [old_choices[key] for key in old_choices.keys() - new_choices.keys()]
    gained = [new_choices[key] for key in new_choices.keys() - old_choices.keys()]
    lost.sort()
    gained.sort()
    if old.get("risk", {}).get("active") != new.get("risk", {}).get("active"):
        semantic = "safety"
    elif any(left.get(key) != right.get(key) for key in ("health", "injury", "hunger", "fatigue")) and old_location == new_location:
        semantic = "body"
    elif old_location != new_location:
        semantic = "route"
    elif old_items != new_items and left.get("coins") == right.get("coins"):
        semantic = "ownership"
    elif left.get("coins") != right.get("coins"):
        semantic = "budget"
    elif gained or lost:
        semantic = "opportunity"
    else:
        semantic = "unresolved"
    return {
        "choice_id": choice_id,
        "state_changes": changes,
        "new_constraints": [f"No longer legal: {label}" for label in lost],
        "new_opportunities": gained,
        "new_affordances": list(new_choices.values()),
        "time_to_next_meaningful_choice": None,
        "followup_semantic_type": semantic,
        "evidence_scope": "public_stepwise_play",
        "note": "Affordance changes are observable; whether any option is meaningful requires play review.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    previous: dict | None = None
    for line in args.log.read_text(encoding="utf-8").splitlines():
        event = json.loads(line)
        response = event.get("response", {})
        if not response.get("ok"):
            continue
        request = event.get("request", {})
        if request.get("command") == "act" and previous is not None:
            row = followup(previous, response, request.get("choice_id", ""))
            row["at"] = event.get("at")
            print(json.dumps(row, ensure_ascii=False))
        previous = response


if __name__ == "__main__":
    main()
