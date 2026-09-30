extends SceneTree
## Legal backend play. Policy reads only the public observation and offered actions.

const Agent = preload("res://scripts/agent/agent_game_session.gd")
var agent := Agent.new()
var serial := 0
var visits := {}
var asked := {}
var helped := {}
var policy := "explore"
var variant := "world_situation_v1"
var interest := ""
var seen_leads := {}
var waited_for := {}
var heard_updates := 0
var withdraw_location := ""


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
	var load_slot := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.trim_prefix("--seed="))
		if arg.begins_with("--steps="):
			steps = int(arg.trim_prefix("--steps="))
		if arg.begins_with("--policy="):
			policy = arg.trim_prefix("--policy=")
		if arg.begins_with("--variant="):
			variant = arg.trim_prefix("--variant=")
		if arg.begins_with("--load-slot="):
			load_slot = arg.trim_prefix("--load-slot=")
	var response := request("start", {"mode": "play", "scenario": "echo_realm", "seed": seed_value, "economy_variant": variant})
	if load_slot != "":
		response = request("load", {"slot": load_slot})
	var actions := {}
	var saved_interest := false
	var saved_combat := false
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
		if action.kind == "combat_encounter" and not saved_combat:
			var checkpoint := request("save", {"slot": "situation_combat_" + policy + "_" + str(seed_value), "overwrite": true})
			if not checkpoint.ok:
				push_error("legal combat checkpoint failed")
				quit(1)
				return
			saved_combat = true
		if type in ["give", "repair", "fund"] and not saved_interest:
			var checkpoint := request("save", {"slot": "situation_interest_" + ("v2_" if variant == "world_situation_v2" else "") + str(seed_value), "overwrite": true})
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
	var saved := request("save", {"slot": "situation_probe_" + policy + "_" + str(seed_value), "overwrite": true})
	print("LEGAL_COMPLETE " + JSON.stringify({"ok": saved.ok, "seed": seed_value, "time": response.observation.time,
		"actions": actions, "visited": visits.keys(), "helped": helped.keys(), "policy": policy, "variant": variant, "heard_updates": heard_updates}))
	quit(0 if saved.ok else 1)


func choose(choices: Array, view: Dictionary) -> Dictionary:
	var combat: Array = choices.filter(func(c: Dictionary) -> bool: return c.kind == "combat_encounter")
	if not combat.is_empty():
		if policy in ["risk", "protect"] and int(view.player.health) > 65 and int(view.player.fatigue) < (9 if policy == "protect" else 7):
			var attacks: Array = combat.filter(func(c: Dictionary) -> bool: return str(c.id).ends_with(":attack"))
			if not attacks.is_empty() and int(attacks[0].get("required_roll", 7)) <= 4:
				return attacks[0]
			for c: Dictionary in combat:
				if str(c.id).ends_with(":guard"):
					return c
		for c: Dictionary in combat:
			if str(c.id).ends_with(":withdraw"):
				withdraw_location = str(view.location.id)
				return c
		return combat[0]
	if withdraw_location == str(view.location.id):
		for c: Dictionary in choices:
			if c.kind == "travel":
				withdraw_location = ""
				return c
	for c: Dictionary in choices:
		if c.id == "journey_block":
			return c
	for c: Dictionary in choices:
		if c.id == "continue":
			return c
	for c: Dictionary in choices:
		if (c.id == "eat" or str(c.id).begins_with("eat:")) and view.player.get("hunger") in ["medium", "high", "extreme"]:
			return c
	for c: Dictionary in choices:
		if c.id == "rest_block" and int(view.player.get("fatigue", 0)) >= (4 if policy == "protect" else 7):
			return c
	for c: Dictionary in choices:
		if str(c.id).begins_with("rest") and int(view.player.get("fatigue", 0)) >= (4 if policy == "protect" else 7):
			return c
	for c: Dictionary in choices:
		if c.get("intent") == "aftermath":
			heard_updates += 1
			if interest == c.subject_id and policy != "persistent":
				interest = ""
			return c
	for c: Dictionary in choices:
		if c.get("intent") == "read_notice":
			return c
	for intent: String in (["fund"] if policy == "fund" else ["give", "repair", "fund"]):
		for c: Dictionary in choices:
			if policy not in ["bystander", "protect"] and c.get("intent") == intent and not helped.has(c.subject_id) \
				and (interest == "" or policy not in ["persistent", "sacrifice"]):
				helped[c.subject_id] = true
				interest = str(c.subject_id)
				return c
	for c: Dictionary in choices:
		if c.get("intent") == "ask" and not asked.has(c.subject_id):
			asked[c.subject_id] = true
			return c
	for c: Dictionary in choices:
		if c.get("intent") == "follow" and c.subject_id == interest:
			return c
	if policy != "explore":
		for c: Dictionary in choices:
			if c.get("intent") == "pursue" and (c.subject_id == interest or (policy in ["risk", "protect"] and c.get("lead_kind") == "danger")):
				var key := str(c.source_fact_id) + ":" + str(view.location.id)
				if not seen_leads.has(key):
					seen_leads[key] = true
					return c
		if interest != "":
			for c: Dictionary in choices:
				if c.get("intent") == "whereabouts" and c.get("wanted_id") == interest:
					return c
			var key := interest + ":" + str(view.location.id)
			if int(waited_for.get(key, 0)) < 3:
				for c: Dictionary in choices:
					if c.get("intent") == "wait" and c.minutes == 60:
						waited_for[key] = int(waited_for.get(key, 0)) + 1
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
