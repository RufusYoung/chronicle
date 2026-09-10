extends RefCounted

const PROFILE := {"version": 1, "contacts_enabled": true, "memory_hours": 24, "retreat_hours": 24,
	"recovery_hours": 12, "rest_health_gain": 3,
	"threat": {"display_name": "田边的野猪", "health": 32, "attack": 15,
		"defense": 18, "escape_difficulty": 12, "retreat_health": 10,
		"damage": 8, "start_hour": 6, "end_hour": 19}}
const STATE_KEYS := ["danger_opponent_id", "danger_round_hour", "danger_advantage",
	"danger_grace_until", "danger_retreat_until", "danger_rest_nourished_until"]


static func validate(config: Variant) -> String:
	if not config is Dictionary:
		return "world_danger_not_dictionary"
	if config.is_empty():
		return ""
	if config.get("version") != 1 or not config.get("threat") is Dictionary:
		return "unsupported_world_danger_version"
	if not config.get("contacts_enabled", true) is bool:
		return "invalid_world_danger_contacts_flag"
	for key: String in ["memory_hours", "retreat_hours", "recovery_hours", "rest_health_gain"]:
		if not _integer(config.get(key), 1, 72):
			return "invalid_world_danger:" + key
	for key: String in ["health", "attack", "defense", "escape_difficulty", "retreat_health", "damage"]:
		if not _integer(config.threat.get(key), 1, 100):
			return "invalid_world_threat:" + key
	if not _integer(config.threat.get("start_hour"), 0, 23) or not _integer(config.threat.get("end_hour"), 0, 23) \
			or config.threat.start_hour >= config.threat.end_hour or config.threat.retreat_health >= config.threat.health \
			or not config.threat.get("display_name") is String:
		return "invalid_world_threat_bounds"
	return ""


static func configure(fixture: Dictionary) -> String:
	var config: Dictionary = fixture.get("world_danger", {})
	var error := validate(config)
	if error != "":
		return error
	if config.is_empty():
		return "world_danger_missing_bootstrap" if not fixture.get("resident_daily_life", {}).get("world_danger", {}).is_empty() else ""
	if not fixture.has("work_rules_generated"):
		return "world_danger_requires_work_framework"
	if fixture.has("world_danger_generated"):
		return "" if fixture.resident_daily_life.get("world_danger", {}) == config else "world_danger_compiled_mismatch"
	var sites: Array = []
	for profile: Dictionary in fixture.get("generated_livelihood_profiles", []):
		if profile.get("occupation_id") == "terrace_farmer" and profile.workplace_id not in sites:
			sites.append(profile.workplace_id)
	if sites.is_empty():
		return "world_danger_requires_crop_site"
	sites.sort()
	var id := "world_threat.field_boar"
	fixture.entities.append({"id": id, "type": "creature", "role": "territorial_wildlife",
		"display_name": config.threat.display_name,
		"description": "野猪守着田边的隐蔽觅食地。它不会追踪不在这里的人，受创后会缩回同一地块的灌丛。",
		"tags": ["world_threat", "wildlife", "territorial"], "territory_id": sites[0],
		"states": {"location_id": sites[0], "health": config.threat.health, "alive": true,
			"visible": true, "danger_retreat_until": 0},
		"source_note": "Boar from authored Mirrorlake forest belt fauna; local individual and territory are generated detail."})
	fixture.resident_daily_life["world_danger"] = config.duplicate(true)
	fixture["world_danger_generated"] = {"version": 1, "threat_ids": [id]}
	# Finite authored journey supplies, not an hourly reward or a settlement subsidy.
	var player := str(fixture.get("player", {}).get("id", "player"))
	var supplied: bool = fixture.get("initial_items", []).any(func(item: Dictionary) -> bool:
		return item.get("holder", {}).get("id") == player)
	if not supplied:
		fixture.initial_items.append({"item_instance_id": "item_instance.danger.journey_rations", "item_def_id": "item.travel_ration",
			"holder": {"kind": "entity", "id": player}, "quantity": 2, "provenance": {"source": "world_danger_starting_kit_v1"}})
		fixture.initial_items.append({"item_instance_id": "item_instance.danger.worn_cloak", "item_def_id": "item.waxed_winter_cloak",
			"holder": {"kind": "entity", "id": player}, "quantity": 1, "condition": {"durability": 40, "maximum_durability": 100},
			"provenance": {"source": "world_danger_starting_kit_v1"}})
		if not fixture.has("initial_equipment_loadouts"):
			fixture["initial_equipment_loadouts"] = []
		if not fixture.initial_equipment_loadouts.any(func(row: Dictionary) -> bool: return row.get("entity_id") == player):
			fixture.initial_equipment_loadouts.append({"entity_id": player, "slots": {"body_outer": "item_instance.danger.worn_cloak"}, "updated_tick": 0})
	return ""


static func validate_references(fixture: Dictionary, stores: Dictionary, locations: Dictionary,
		player_id: String, player_location: String) -> String:
	var config: Dictionary = fixture.get("world_danger", {})
	for id: Variant in fixture.get("world_danger_generated", {}).get("threat_ids", []):
		var entity: Dictionary = stores.entity_store.get_entity(str(id))
		if config.is_empty() or entity.get("type") != "creature" or not locations.has(str(entity.get("territory_id", ""))) \
				or stores.state_store.get_state(str(id), "location_id", "") != entity.territory_id:
			return "save_world_threat_invalid"
	for id: String in stores.state_store.states:
		var states: Dictionary = stores.state_store.states[id]
		for key: String in STATE_KEYS.slice(1):
			if states.has(key) and (config.is_empty() or not _integer(states[key], 0, 1000000000)):
				return "save_world_danger_state_invalid:" + key
		var opponent := str(states.get("danger_opponent_id", ""))
		var location := player_location if id == player_id else str(states.get("location_id", ""))
		if opponent != "" and (opponent not in fixture.get("world_danger_generated", {}).get("threat_ids", []) \
				or stores.state_store.get_state(opponent, "location_id", "") != location \
				or states.get("daily_route_id", "") != ""):
			return "save_world_danger_opponent_invalid"
		if int(states.get("danger_advantage", 0)) > 4:
			return "save_world_danger_advantage_invalid"
	for memory: Dictionary in stores.memory_store.memories:
		if memory.get("memory_type") != "world_danger_seen":
			continue
		var fact: Dictionary = stores.fact_store.get_fact(str(memory.get("source_fact_id", "")))
		if config.is_empty() or not memory.get("danger_present") is bool \
				or memory.get("subject_id") not in fixture.get("world_danger_generated", {}).get("threat_ids", []) \
				or fact.get("actor_id") != memory.get("owner_id") or fact.get("target_id") != memory.get("subject_id") \
				or fact.get("location_id") != memory.get("location_id") \
				or not _integer(memory.get("observed_hour"), 0, 1000000000) \
				or int(memory.observed_hour) != int(fact.get("day", 0)) * 24 + int(fact.get("hour", 0)) \
				or memory.get("expires_hour") != int(memory.observed_hour) + int(config.memory_hours):
			return "save_world_danger_memory_invalid"
	for injury: Dictionary in stores.character_feature_store.list_trait_instances():
		if not injury.has("recovery_fact_ids"):
			if not config.is_empty() and injury.get("trait_def_id") == "trait.combat_bruising" \
					and (int(injury.get("recovery_progress", 0)) > 0 or injury.get("stage_id") in ["recovering", "healed"]):
				return "save_world_danger_recovery_sources_missing"
			continue
		var sources: Variant = injury.get("recovery_fact_ids")
		if config.is_empty() or not sources is Array or sources.size() != int(injury.get("recovery_progress", 0)) \
				or sources.size() > int(config.recovery_hours) or sources.is_empty():
			return "save_world_danger_recovery_invalid"
		var seen := {}
		for source: Variant in sources:
			var fact: Dictionary = stores.fact_store.get_fact(str(source))
			if seen.has(source) or fact.get("fact_type") != "actor_rested_with_injury" \
					or fact.get("actor_id") != injury.owner_entity_id or injury.trait_instance_id not in fact.get("trait_instance_ids", []) \
					or fact.get("required_recovery_hours") != config.recovery_hours:
				return "save_world_danger_recovery_source_invalid"
			seen[source] = true
		if injury.get("stage_id") != ("healed" if sources.size() == int(config.recovery_hours) else "recovering") \
				or injury.get("status") != ("resolved" if sources.size() == int(config.recovery_hours) else "active"):
			return "save_world_danger_recovery_stage_invalid"
	return ""


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == float(int(value)) and int(value) >= minimum and int(value) <= maximum
