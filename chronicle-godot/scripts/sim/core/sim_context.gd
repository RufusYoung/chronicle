extends RefCounted
class_name V5SimContext

var world_id: String = ""
var actor_id: String = ""
var fixture_id: String = ""
var location_id: String = ""
var location: Dictionary = {}
var visible_entity_ids: Array = []
var region_state: Dictionary = {}
var institution: Dictionary = {}
var entities: Array = []
var player: Dictionary = {}
var known_fact_ids: Array = []
var known_facts: Array = []


func _init(initial_data: Dictionary = {}) -> void:
	world_id = str(initial_data.get("world_id", ""))
	actor_id = str(initial_data.get("actor_id", ""))
	fixture_id = str(initial_data.get("fixture_id", ""))
	location = (initial_data.get("location", {}) as Dictionary).duplicate(true)
	location_id = str(initial_data.get("location_id", location.get("id", "")))
	visible_entity_ids = (initial_data.get("visible_entity_ids", []) as Array).duplicate(true)
	region_state = (initial_data.get("region_state", {}) as Dictionary).duplicate(true)
	institution = (initial_data.get("institution", {}) as Dictionary).duplicate(true)
	entities = (initial_data.get("entities", []) as Array).duplicate(true)
	player = (initial_data.get("player", {}) as Dictionary).duplicate(true)
	known_fact_ids = (initial_data.get("known_fact_ids", []) as Array).duplicate(true)
	known_facts = (initial_data.get("known_facts", []) as Array).duplicate(true)
	if visible_entity_ids.is_empty():
		visible_entity_ids = _derive_visible_entity_ids()


func to_dict() -> Dictionary:
	return {
		"world_id": world_id,
		"actor_id": actor_id,
		"fixture_id": fixture_id,
		"location_id": location_id,
		"location": location.duplicate(true),
		"visible_entity_ids": visible_entity_ids.duplicate(true),
		"region_state": region_state.duplicate(true),
		"institution": institution.duplicate(true),
		"entities": entities.duplicate(true),
		"player": player.duplicate(true),
		"known_fact_ids": known_fact_ids.duplicate(true),
		"known_facts": known_facts.duplicate(true),
	}


func get_visible_entities() -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		var states: Dictionary = entity.get("states", {})
		if bool(states.get("visible", false)):
			rows.append(entity.duplicate(true))
	return rows


func get_entities_by_type(type_name: String) -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		if str(entity.get("type", "")) == type_name:
			rows.append(entity.duplicate(true))
	return rows


func get_location_tags() -> Array:
	return (location.get("tags", []) as Array).duplicate(true)


func get_region_state_value(key: String, default_value: Variant = null) -> Variant:
	return region_state.get(key, default_value)


func get_institution_value(key: String, default_value: Variant = null) -> Variant:
	return institution.get(key, default_value)


func get_player_value(key: String, default_value: Variant = null) -> Variant:
	return player.get(key, default_value)


func get_entity_by_id(entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if str(entity.get("id", "")) == entity_id:
			return entity.duplicate(true)
	return {}


func _derive_visible_entity_ids() -> Array:
	var ids: Array = []
	for entity: Dictionary in entities:
		var states: Dictionary = entity.get("states", {})
		if bool(states.get("visible", false)):
			ids.append(str(entity.get("id", "")))
	return ids
