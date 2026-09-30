extends SceneTree
## Matched legal interventions from a real play save; internal facts are inspected only afterward.

const Agent = preload("res://scripts/agent/agent_game_session.gd")
const Continuity = preload("res://scripts/sim/situation/situation_continuity.gd")
var serial := 0


func _initialize() -> void:
	call_deferred("run")


func request(agent: Variant, command: String, fields: Dictionary = {}) -> Dictionary:
	serial += 1
	var data := {"protocol": 1, "command": command, "request_id": "branch." + str(serial), "session_id": agent.session_id, "expected_revision": agent.revision}
	data.merge(fields)
	return agent.handle(data)


func run() -> void:
	var slot := "situation_interest_v2_81001"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = arg.trim_prefix("--slot=")
	var rows := []
	var subject := ""
	for branch: String in ["give", "fund", "caution", "leave_alone"]:
		var agent := Agent.new()
		var response := request(agent, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
		response = request(agent, "load", {"slot": slot})
		if not response.get("ok", false):
			fail("load", response)
			return
		var session: Variant = agent.model.session
		if session.stores.fact_store.list_facts().any(func(f: Dictionary) -> bool: return f.get("fact_type") == "test_injection"):
			fail("not a natural checkpoint", {})
			return
		var start_hour: int = response.observation.time.elapsed_hours
		var actions: Array = response.choices.filter(func(c: Dictionary) -> bool: return c.enabled and c.get("intent") == "give" and c.has("clear_slots"))
		if subject == "" and not actions.is_empty():
			subject = str(actions[0].subject_id)
		var selected: Array = response.choices.filter(func(c: Dictionary) -> bool:
			return c.enabled and ((c.get("intent") == branch and c.get("subject_id") == subject) \
			or (branch == "leave_alone" and c.get("intent") == "wait" and c.get("minutes") == 10)))
		if selected.is_empty():
			fail("intervention not offered: " + branch, {})
			return
		response = request(agent, "act", {"choice_id": selected[0].choice_id, "confirm": true})
		var intervention: Dictionary = response.get("observation", {}).get("feedback", {}).duplicate(true)
		var start_fact_count: int = session.stores.fact_store.facts.size()
		for action_index: int in range(240):
			if not response.get("ok", false):
				fail("legal waiting", response)
				return
			if int(response.observation.time.elapsed_hours) >= start_hour + 24:
				break
			var wait: Array = response.choices.filter(func(c: Dictionary) -> bool:
				return c.enabled and c.get("intent") == "wait" and c.get("minutes") == 60)
			if wait.is_empty():
				fail("no safe hub wait", response)
				return
			response = request(agent, "act", {"choice_id": wait[0].choice_id})
		var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
		var events := []
		for fact: Dictionary in session.stores.fact_store.facts.slice(start_fact_count):
			if fact.get("actor_id") != subject or fact.get("fact_type") not in ["resident_activity_changed", "resident_equipped", "world_danger_round", "npc_livelihood_produced", "work_supply_purchased", "resident_food_purchased"]:
				continue
			events.append({"id": fact.fact_id, "type": fact.fact_type, "day": fact.day, "hour": fact.get("hour", 0),
				"summary": fact.summary, "source_fact_ids": fact.get("source_fact_ids", []),
				"player_contribution": Continuity.contribution(snapshot, fact.get("source_fact_ids", []), "player")})
		var save := request(agent, "save", {"slot": "situation_branch_" + branch, "overwrite": true})
		var loaded := request(agent, "load", {"slot": "situation_branch_" + branch})
		if not save.ok or not loaded.ok:
			fail("branch persistence", loaded)
			return
		var row := {"branch": branch, "subject": subject, "time": response.observation.time,
			"elapsed": int(response.observation.time.elapsed_hours) - start_hour,
			"intervention": intervention, "actor": snapshot.get_entity(subject).states,
			"loadout": snapshot.get_equipment_loadout(subject), "events": events}
		rows.append(row)
		print("NATURAL_BRANCH " + JSON.stringify(row))
	var path := "user://tests/situations/natural_branches.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"source_slot": slot, "scope": "Legal interventions and waiting; post-run inspection is omniscient analysis, not player knowledge or human play.", "branches": rows}, "\t"))
	print("NATURAL_BRANCH_COMPLETE " + ProjectSettings.globalize_path(path))
	quit(0)


func fail(reason: String, result: Dictionary) -> void:
	push_error(reason + ": " + JSON.stringify(result.get("receipt", result)))
	quit(1)
