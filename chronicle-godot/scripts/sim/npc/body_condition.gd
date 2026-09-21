extends RefCounted

# Frozen v1 rules: future balance changes require a new bootstrap version.
const PROFILE := {"version": 1, "strain_interval": 6, "health_loss": 2,
	"health_floor": 40, "extra_work_fatigue": 2, "combat_penalty": 2}


static func enabled(states: Dictionary) -> bool:
	return states.get("body_rules_version") == 1


static func strained(states: Dictionary) -> bool:
	return enabled(states) and states.get("hunger") == "extreme"


static func configure(fixture: Dictionary) -> String:
	var config: Variant = fixture.get("body_rules", {})
	if not config is Dictionary:
		return "body_rules_not_dictionary"
	if config.is_empty():
		return "body_rules_missing_bootstrap" if fixture.has("body_rules_generated") else ""
	if config.size() != PROFILE.size() or not PROFILE.keys().all(func(key: String) -> bool: return config.get(key) == PROFILE[key]):
		return "unsupported_body_rules"
	if not fixture.has("player_life_generated") or not fixture.has("world_danger_generated"):
		return "body_rules_require_shared_player_life"
	var actors: Array = [str(fixture.player.id)]
	for actor: Dictionary in fixture.entities:
		if actor.get("type") == "person" and "generated_resident" in actor.get("tags", []):
			actors.append(str(actor.id))
	actors.sort()
	if fixture.has("body_rules_generated"):
		var compiled: Variant = fixture.body_rules_generated
		if not compiled is Dictionary or compiled.size() != 2 or compiled.get("version") != 1 or compiled.get("actors") != actors:
			return "body_rules_compiled_mismatch"
		return ""
	fixture.player["body_rules_version"] = 1
	for actor: Dictionary in fixture.entities:
		if str(actor.id) in actors:
			actor.states["body_rules_version"] = 1
	fixture["body_rules_generated"] = {"version": 1, "actors": actors}
	return ""


static func configure_needs(profiles: Array, fixture: Dictionary) -> void:
	if fixture.get("body_rules", {}).get("version") != 1:
		return
	for profile: Dictionary in profiles:
		for need: Dictionary in profile.get("needs", []):
			if need.get("key") == "hunger":
				need["body_rules_version"] = 1


static func validate_save(fixture: Dictionary, stores: Dictionary) -> String:
	var actors: Array = fixture.get("body_rules_generated", {}).get("actors", [])
	for id: String in actors:
		if stores.state_store.get_state(id, "body_rules_version", 0) != 1 or not stores.entity_store.has_entity(id):
			return "save_body_identity_invalid"
	for id: String in stores.state_store.states:
		var states: Dictionary = stores.state_store.states[id]
		if states.has("body_rules_version") or states.has("hunger_strain_hours"):
			if id not in actors or states.get("body_rules_version") != 1:
				return "save_body_rules_invalid"
			var clock: Variant = states.get("hunger_strain_hours", 0)
			if not (clock is int or clock is float) or not is_finite(float(clock)) or float(clock) != floor(float(clock)) or clock < 0 or clock >= PROFILE.strain_interval:
				return "save_body_clock_invalid"
	return ""


static func append_hunger(result: Variant, actor: Dictionary, snapshot: Variant, tick: Dictionary,
		extreme_hours: int, remains_extreme: bool) -> void:
	var id := str(actor.id)
	if not enabled(actor.get("states", {})) or not actor.states.get("alive", true):
		return
	var old := int(snapshot.get_entity_state(id, "hunger_strain_hours", 0))
	var accumulated := old + extreme_hours if remains_extreme else 0
	var clock := accumulated % int(PROFILE.strain_interval)
	if clock != old:
		result.add_state_change({"entity_id": id, "key": "hunger_strain_hours", "to": clock})
	var health := int(snapshot.get_entity_state(id, "health", 100))
	var loss := mini(int(accumulated / int(PROFILE.strain_interval)) * int(PROFILE.health_loss), maxi(health - int(PROFILE.health_floor), 0))
	if loss <= 0:
		return
	var here := str(actor.states.get("location_id", ""))
	result.add_state_change({"entity_id": id, "key": "health", "to": health - loss, "reason": "hunger_strain"})
	result.add_fact({"fact_id": "fact.hunger_strain.%s.%s" % [id, tick.get("tick_event_id", "tick")],
		"fact_type": "actor_hunger_strain", "actor_id": id, "location_id": here,
		"day": tick.day, "hour": tick.hour, "health_before": health, "health_after": health - loss,
		"observed_by_player": id == str(snapshot.player.id) or (here == str(snapshot.location.id) and actor.states.get("daily_route_id", "") == ""),
		"summary": "%s持续极饿，健康从%d降至%d；进食可以止损，已失去的健康需要休养。" % [actor.get("display_name", id), health, health - loss]})


static func work_fatigue(states: Dictionary) -> int:
	return 1 + (int(PROFILE.extra_work_fatigue) if strained(states) else 0)


static func combat_penalty(states: Dictionary) -> int:
	return int(PROFILE.combat_penalty) if strained(states) else 0


static func describe(states: Dictionary) -> String:
	if not enabled(states):
		return ""
	if strained(states):
		var health := int(states.get("health", 100))
		return ("极饿再持续%d小时损失2健康。" % (int(PROFILE.strain_interval) - int(states.get("hunger_strain_hours", 0))) if health > int(PROFILE.health_floor) else "饥饿损耗已达本版下限，仍可自救。") + "每轮作业多2疲劳，攻防减2。"
	return "持续极饿会损耗健康并增加劳动、交锋代价；进食止损，健康需另行休养。"
