extends SceneTree
## Passive observation only; no player intervention or forced NPC outcomes.

const Agent = preload("res://scripts/agent/agent_game_session.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var seed_value := 81001
	var hours := 72
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seed="):
			seed_value = int(argument.trim_prefix("--seed="))
		if argument.begins_with("--hours="):
			hours = int(argument.trim_prefix("--hours="))
	var agent := Agent.new()
	var started: Dictionary = agent.handle({"protocol": 1, "command": "start", "request_id": "start",
		"session_id": agent.session_id, "expected_revision": 0, "mode": "world", "scenario": "echo_realm",
		"seed": seed_value, "economy_variant": "world_situation_v1"})
	if not started.get("ok", false):
		push_error(str(started))
		quit(1)
		return
	var session: Variant = agent.model.session
	var seen := {}
	var counts := {}
	for hour: int in range(hours):
		var result: Dictionary = session.advance_time(1, "passive_situation_probe")
		if not result.get("success", false):
			push_error(str(result))
			quit(1)
			return
		for fact: Dictionary in session.stores.fact_store.list_facts():
			if fact.get("fact_type") not in ["work_supply_purchased", "work_supply_unmet", "resident_equipped", "world_danger_contact", "equipment_request", "equipment_given", "npc_work_maintained"] or seen.has(fact.fact_id):
				continue
			seen[fact.fact_id] = true
			counts[fact.fact_type] = int(counts.get(fact.fact_type, 0)) + 1
			print("PASSIVE_FACT " + JSON.stringify(fact))
	print("PASSIVE_COMPLETE " + JSON.stringify({"clock": session.get_time_summary(), "seed": seed_value, "counts": counts}))
	quit()
