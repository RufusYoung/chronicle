"""Bounded code-level play and observer traces, with no state or dice injection."""

import argparse
from collections import Counter
import json
from pathlib import Path
import time

from agent_play import ChronicleClient


def run(output: Path, days: int, skip_world: bool = False) -> None:
    output.mkdir(parents=True, exist_ok=True)
    summary = {"evidence_kind": "code_agent_and_passive_world", "runs": []}
    with (output / "agent_trace.jsonl").open("w", encoding="utf-8") as trace:
        def record(game, command, **arguments):
            started = time.perf_counter()
            result = game.request(command, **arguments)
            trace.write(json.dumps({"command": command, "arguments": arguments,
                                    "seconds": round(time.perf_counter() - started, 4),
                                    "response": result}, ensure_ascii=False) + "\n")
            trace.flush()
            if not result.get("ok"):
                raise RuntimeError(json.dumps(result, ensure_ascii=False))
            return result

        for seed in (() if skip_world else (81001, 82002)):
            with ChronicleClient(timeout=180) as game:
                started = time.perf_counter()
                first = record(game, "start", mode="world", scenario="generated_network", seed=seed)
                last = first
                for _ in range(days):
                    last = record(game, "advance", hours=24)
                fact_types = Counter()
                offset = 0
                while True:
                    page = game.request("inspect", kind="facts", offset=offset, limit=100)
                    if not page["ok"]:
                        raise RuntimeError(str(page))
                    fact_types.update(row.get("fact_type", "unknown") for row in page["rows"])
                    offset += len(page["rows"])
                    if offset >= page["total"]:
                        break
                summary["runs"].append({"profile": "world", "seed": seed, "days": days,
                                        "actor_actions": 0, "seconds": round(time.perf_counter() - started, 3),
                                        "before": first["observation"], "after": last["observation"],
                                        "fact_type_counts": dict(fact_types)})

        with ChronicleClient(timeout=180) as game:
            current = record(game, "start", mode="play", scenario="generated_network", seed=81001)
            visited = [current["observation"]["location"]["id"]]
            visited_names = [current["observation"]["location"]["title"]]
            performed = []
            for _ in range(6):
                available = [c for c in current["choices"] if c["enabled"]]
                unseen_route = next((c for c in available if c["kind"] == "travel"
                                     and c.get("destination_name") not in visited_names), None)
                choice = unseen_route or next((c for c in available if c["kind"] == "player_action"
                                                and c["choice_id"] not in performed), None)
                choice = choice or next((c for c in available if c["kind"] == "wait"), None)
                if choice is None:
                    break
                current = record(game, "act", choice_id=choice["choice_id"])
                performed.append(choice["choice_id"])
                visited.append(current["observation"]["location"]["id"])
                visited_names.append(current["observation"]["location"]["title"])
            summary["runs"].append({"profile": "generated_network_play", "actions": performed,
                                    "locations": visited, "time": current["observation"]["time"]})

        with ChronicleClient(timeout=180) as game:
            current = record(game, "start", mode="play", scenario="first_winter", seed=81001)
            performed = []
            for _ in range(24):
                available = [c for c in current["choices"] if c["enabled"]]
                growth = next((c for c in available if c["kind"] == "growth"), None)
                if growth:
                    current = record(game, "act", choice_id=growth["choice_id"], confirm=True)
                    performed.append(growth["choice_id"])
                    break
                incident = next((c for c in available if c["kind"] == "incident"), None)
                duties = [c for c in available if c["kind"] == "duty"]
                # A simple diagnostic policy, not a claim that duties are interesting.
                fatigue = current["observation"].get("player", {}).get("fatigue", 0)
                recovery = next((c for c in duties if "recover" in c["id"] or "rest" in c["id"]), None)
                untried = next((c for c in duties if c["choice_id"] not in performed), None)
                choice = incident or (recovery if fatigue >= 5 else None) or untried or (duties[0] if duties else None)
                if choice is None:
                    break
                current = record(game, "act", choice_id=choice["choice_id"])
                performed.append(choice["choice_id"])
            summary["runs"].append({"profile": "first_winter_play", "actions": performed,
                                    "complete": current["observation"].get("complete", False),
                                    "next_choices": [c["choice_id"] for c in current["choices"]],
                                    "time": current["observation"]["time"]})
    (output / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"trace": str(output), "runs": len(summary["runs"])}, ensure_ascii=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--days", type=int, choices=range(1, 8), default=3)
    parser.add_argument("--skip-world", action="store_true", help="Only rerun the two player policies")
    arguments = parser.parse_args()
    run(arguments.output, arguments.days, arguments.skip_world)
