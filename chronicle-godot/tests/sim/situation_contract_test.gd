extends SceneTree

const Agent = preload("res://scripts/agent/agent_game_session.gd")
var failures: Array = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func request(agent: Variant, command: String, fields: Dictionary = {}) -> Dictionary:
	var data := {"protocol": 1, "command": command, "request_id": str(checks) + "." + str(agent.revision) + "." + command,
		"session_id": agent.session_id, "expected_revision": agent.revision}
	data.merge(fields)
	return agent.handle(data)


func run() -> void:
	var agent := Agent.new()
	var started := request(agent, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v1"})
	check(started.get("ok", false), "new version starts: " + str(started.get("error", "")))
	if not started.get("ok", false):
		finish()
		return
	check(agent.model.session.fixture_source_data.journey_rules.events.is_empty(), "zero authored journey events")
	check(started.observation.get("situation_mode", false), "public observation exposes situation projection")
	var native_before := JSON.stringify(agent.model.session.build_save_envelope())
	var projected: Array = agent.model.session.Situations.build(agent.model.session)
	check(JSON.stringify(agent.model.session.build_save_envelope()) == native_before, "recognition does not mutate the world")
	check(not started.choices.any(func(c: Dictionary) -> bool: return str(c.id).begins_with("adventure:")), "no authored action leaks into experiment")
	var waits: Array = started.choices.filter(func(c: Dictionary) -> bool: return c.get("intent") == "wait")
	check(not waits.is_empty(), "waiting is a legal offered action")
	if not waits.is_empty():
		var waited := request(agent, "act", {"choice_id": waits[0].choice_id})
		check(waited.get("ok", false), "legal ten minute wait: " + str(waited.get("error", "")))
		check(agent.model.session.get_time_summary().minute == 10, "native remainder advances")
	check(projected.all(func(s: Dictionary) -> bool: return s.goals.is_empty()), "initial undisclosed intentions remain unknown")
	finish()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func finish() -> void:
	print("SITUATION_CONTRACT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
