extends SceneTree

const Danger = preload("res://scripts/sim/combat/world_danger_system.gd")
const Setup = preload("res://scripts/sim/combat/world_danger_setup.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot.gd")
var checks := 0
var failures: Array = []


func _initialize() -> void:
	var view := Snapshot.new({"player": {"id": "player"}, "entities": [{"id": "resident", "display_name": "在场守夜人"}]})
	var threat := {"id": "test_threat", "display_name": "测试领地动物", "states": {"alive": true}}
	var tick := {"day": 2, "hour": 13}
	var now := Danger.hour(tick)
	view.facts = [{"fact_id": "test_injection.fed", "fact_type": "world_threat_fed", "actor_id": threat.id,
		"day": 2, "hour": 13, "sated_until": now + 6}]
	var reason := Danger.departure_reason(view, threat, tick, Setup.PROFILE)
	check(reason.reason == "sated" and "并未被击败" in reason.summary, "controlled feeding ends contact without claiming victory")
	check(reason.source_fact_ids == ["test_injection.fed"], "ending points to the actual cause fact")
	threat.states.alive = false
	check(Danger.departure_reason(view, threat, tick, Setup.PROFILE).reason == "dead", "death takes precedence over prior feeding")
	threat.states.alive = true
	view.facts.append({"fact_id": "test_injection.driven", "fact_type": "world_danger_round", "actor_id": "resident",
		"target_id": threat.id, "day": 2, "hour": 13, "threat_dispersed": true})
	reason = Danger.departure_reason(view, threat, tick, Setup.PROFILE)
	check(reason.reason == "driven_off" and "守夜人" in reason.summary, "NPC finishing blow is not claimed by player")
	view.facts = []
	check(Danger.departure_reason(view, threat, {"day": 2, "hour": 19}, Setup.PROFILE).reason == "activity_ended", "scheduled departure is explicit")
	check(Danger.departure_reason(view, threat, tick, Setup.PROFILE).reason == "contact_lost", "unknown ending does not invent a cause")
	view.facts = [{"fact_id": "test_injection.expired", "fact_type": "world_threat_fed", "actor_id": threat.id,
		"day": 1, "hour": 13, "sated_until": now - 1}]
	check(Danger.departure_reason(view, threat, tick, Setup.PROFILE).reason == "contact_lost", "expired feeding fact cannot explain today's ending")
	print("COMBAT_DEPARTURE_REASON %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func check(passed: bool, label: String) -> void:
	checks += 1
	print(("PASS " if passed else "FAIL ") + label)
	if not passed:
		failures.append(label)
