"""Stepwise local play: no policy, hidden state, or automatic choice selection."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from datetime import datetime, timezone

from agent_play import ChronicleClient


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--godot")
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    args.log.parent.mkdir(parents=True, exist_ok=True)
    choices: list[dict] = []
    with args.log.open("x", encoding="utf-8") as log, ChronicleClient(
        godot=args.godot, packaged=not args.source
    ) as game:
        print('READY: JSON command; {"pick": index, "reason": "..."}, or {"command":"quit"}', flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            rationale = request.pop("reason", "")
            if request.get("command") == "quit":
                break
            if "pick" in request:
                index = request.pop("pick")
                if type(index) is not int or not 0 <= index < len(choices):
                    print("Invalid choice index", flush=True)
                    continue
                request.update(command="act", choice_id=choices[index]["choice_id"], confirm=True)
            result = game.request(**request)
            log.write(json.dumps({"at": datetime.now(timezone.utc).isoformat(), "request": request, "reason": rationale, "response": result}, ensure_ascii=False) + "\n")
            log.flush()
            if not result.get("ok"):
                print(json.dumps(result, ensure_ascii=False), flush=True)
                continue
            choices = result.get("choices", choices)
            observation = result.get("observation", {})
            # Preserve the complete public observation in the log; omit bulky journals here.
            visible = {key: observation[key] for key in ("time", "location", "feedback", "risk", "goal_pressure", "wilderness") if key in observation}
            visible["player"] = {key: value for key, value in observation.get("player", {}).items() if key not in ("summary", "items", "inventory")}
            visible["situations"] = [{key: row[key] for key in ("title", "body") if key in row} for row in observation.get("situations", [])]
            print(json.dumps({"revision": result.get("revision"), "observation": visible}, ensure_ascii=False), flush=True)
            for index, choice in enumerate(choices):
                print(json.dumps({"pick": index, **{key: choice[key] for key in (
                    "choice_id", "label", "enabled", "blocked_reason", "cost", "hint", "tradeoff", "goal_priority"
                ) if key in choice}}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
