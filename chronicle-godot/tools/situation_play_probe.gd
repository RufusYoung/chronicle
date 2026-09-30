extends SceneTree
## Legal backend play. Policy reads only the public observation and offered actions.

const Agent = preload("res://scripts/agent/agent_game_session.gd")
var agent := Agent.new()
var serial := 0
var visits := {}
var asked := {}
var helped := {}


func _initialize() -> void:
	call_deferred("run")


func request(command: String, fields: Dictionary = {}) -> Dictionary:
	serial += 1
	var data := {"protocol": 1, "command": command, "request_id": "play." + str(serial), "session_id": agent.session_id, "expected_revision": agent.revision}
	data.merge(fields)
	return agent.handle(data)


func run() -> void:
	var seed_value := 81001
	var steps := 60
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--steps="):
			steps = int(arg.trim_prefix("--steps="))
	var response := request("start", {"mode": "play", "scenario": "echo_realm", "seed": seed_value, "economy_variant": "world_situation_v1"})
	var actions := {}
	var saved_interest := false
	for step: int in range(steps):
		if not response.get("ok", false):
			push_error(JSON.stringify(response.get("receipt", response)))
			quit(1)
			return
		var view: Dictionary = response.observation
		var choices: Array = response.choices.filter(func(c: Dictionary) -> bool: return c.enabled)
		var action := choose(choices, view)
		if action.is_empty():
			push_error("no legal continuation")
			quit(1)
			return
		var type := str(action.get("intent", action.kind))
		if type in ["give", "repair", "fund"] and not saved_interest:
			var checkpoint := request("save", {"slot": "situation_interest_" + str(seed_value), "overwrite": true})
			if not checkpoint.ok:
				push_error("legal interest checkpoint failed")
				quit(1)
				return
			saved_interest = true
		actions[type] = int(actions.get(type, 0)) + 1
		print("LEGAL_PLAY " + JSON.stringify({"step": step, "time": view.time, "location": view.location.title,
			"visible_situations": view.get("situations", []).map(func(s: Dictionary) -> String: return s.body),
			"action": action.label, "choice_id": action.choice_id}))
		response = request("act", {"choice_id": action.choice_id, "confirm": true})
		print("LEGAL_RESULT " + JSON.stringify(response.get("observation", {}).get("feedback", {})))
	var saved := request("save", {"slot": "situation_probe_" + str(seed_value), "overwrite": true})
	print("LEGAL_COMPLETE " + JSON.stringify({"ok": saved.ok, "seed": seed_value, "time": response.observation.time,
		"actions": actions, "visited": visits.keys(), "helped": helped.keys()}))
	quit(0 if saved.ok else 1)


func choose(choices: Array, view: Dictionary) -> Dictionary:
	var combat: Array = choices.filter(func(c: Dictionary) -> bool: return c.kind == "combat_encounter")
	if not combat.is_empty():
		for c: Dictionary in combat:
			if str(c.id).ends_with(":withdraw"):
				return c
		return combat[0]
	for c: Dictionary in choices:
		if c.id == "continue":
			return c
	for c: Dictionary in choices:
		if str(c.id).begins_with("eat:") and view.player.get("hunger") in ["high", "extreme"]:
			return c
	for c: Dictionary in choices:
		if str(c.id).begins_with("rest") and int(view.player.get("fatigue", 0)) >= 7:
			return c
	for c: Dictionary in choices:
		if c.get("intent") in ["give", "repair", "fund"] and not helped.has(c.subject_id):
			helped[c.subject_id] = true
			return c
	for c: Dictionary in choices:
		if c.get("intent") == "ask" and not asked.has(c.subject_id):
			asked[c.subject_id] = true
			return c
	for c: Dictionary in choices:
		if c.get("intent") == "follow" and helped.has(c.subject_id):
			return c
	var routes: Array = choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel")
	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a := int(visits.get(a.destination_name, 0)) * 20 + int(a.hours)
		var score_b := int(visits.get(b.destination_name, 0)) * 20 + int(b.hours)
		return score_a < score_b if score_a != score_b else str(a.destination_name) < str(b.destination_name))
	if not routes.is_empty():
		var chosen: Dictionary = routes[0]
		visits[chosen.destination_name] = int(visits.get(chosen.destination_name, 0)) + 1
		return chosen
	for c: Dictionary in choices:
		if c.get("intent") == "wait" and c.get("minutes") == 60:
			return c
	return choices[0] if not choices.is_empty() else {}
