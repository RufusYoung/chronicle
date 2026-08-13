extends RefCounted
class_name V5SimContext

var world_id: String = ""
var actor_id: String = ""
var fixture_id: String = ""
var region_entity_id: String = ""
var institution_entity_id: String = ""
var location_id: String = ""
var location: Dictionary = {}
var locations: Dictionary = {}
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
	region_entity_id = str(initial_data.get(
		"region_entity_id",
		"%s:region" % fixture_id if fixture_id != "" else ""
	))
	institution_entity_id = str(initial_data.get(
		"institution_entity_id",
		"%s:institution" % fixture_id if fixture_id != "" else ""
	))
	location = (initial_data.get("location", {}) as Dictionary).duplicate(true)
	location_id = str(initial_data.get("location_id", location.get("id", "")))
	_load_locations(initial_data.get("locations", []))
	if not location.is_empty():
		var legacy_location_id := str(location.get("id", location_id))
		if legacy_location_id != "" and not locations.has(legacy_location_id):
			locations[legacy_location_id] = location.duplicate(true)
	if location_id == "" and not locations.is_empty():
		location_id = str(locations.keys()[0])
	if locations.has(location_id):
		location = (locations[location_id] as Dictionary).duplicate(true)
	visible_entity_ids = (initial_data.get("visible_entity_ids", []) as Array).duplicate(true)
	region_state = (initial_data.get("region_state", {}) as Dictionary).duplicate(true)
	institution = (initial_data.get("institution", {}) as Dictionary).duplicate(true)
	entities = (initial_data.get("entities", []) as Array).duplicate(true)
	_assign_missing_entity_locations()
	player = (initial_data.get("player", {}) as Dictionary).duplicate(true)
	if actor_id == "":
		actor_id = str(player.get("id", "player"))
	player["food_count"] = _initial_owned_item_quantity(
		initial_data.get("initial_items", []),
		actor_id,
		"item.travel_ration"
	)
	known_fact_ids = (initial_data.get("known_fact_ids", []) as Array).duplicate(true)
	known_facts = (initial_data.get("known_facts", []) as Array).duplicate(true)
	if visible_entity_ids.is_empty():
		visible_entity_ids = _derive_visible_entity_ids()


func to_dict() -> Dictionary:
	return {
		"world_id": world_id,
		"actor_id": actor_id,
		"fixture_id": fixture_id,
		"region_entity_id": region_entity_id,
		"institution_entity_id": institution_entity_id,
		"location_id": location_id,
		"location": location.duplicate(true),
		"locations": locations.duplicate(true),
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
		if str(entity.get("location_id", "")) != location_id:
			continue
		var states: Dictionary = entity.get("states", {})
		if bool(states.get("visible", false)):
			rows.append(entity.duplicate(true))
	return rows


func get_entities_by_type(type_name: String) -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		if (
			str(entity.get("location_id", "")) == location_id
			and str(entity.get("type", "")) == type_name
		):
			rows.append(entity.duplicate(true))
	return rows


func get_locations() -> Array:
	var rows: Array = []
	for stored_location: Dictionary in locations.values():
		rows.append(stored_location.duplicate(true))
	return rows


func get_location(candidate_location_id: String) -> Dictionary:
	if not locations.has(candidate_location_id):
		return {}
	return (locations[candidate_location_id] as Dictionary).duplicate(true)


func set_current_location(candidate_location_id: String) -> bool:
	if not locations.has(candidate_location_id):
		return false
	location_id = candidate_location_id
	location = (locations[candidate_location_id] as Dictionary).duplicate(true)
	visible_entity_ids = _derive_visible_entity_ids()
	return true


func get_entities_at_location(candidate_location_id: String) -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		if str(entity.get("location_id", "")) == candidate_location_id:
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


func release_runtime_sources() -> void:
	visible_entity_ids.clear()
	region_state.clear()
	institution.clear()
	entities.clear()
	player.clear()
	known_fact_ids.clear()
	known_facts.clear()


func _derive_visible_entity_ids() -> Array:
	var ids: Array = []
	for entity: Dictionary in entities:
		if str(entity.get("location_id", "")) != location_id:
			continue
		var states: Dictionary = entity.get("states", {})
		if bool(states.get("visible", false)):
			ids.append(str(entity.get("id", "")))
	return ids


func _load_locations(raw_locations: Variant) -> void:
	locations.clear()
	if raw_locations is Array:
		for raw_location: Variant in raw_locations:
			if not raw_location is Dictionary:
				continue
			var location_data: Dictionary = raw_location.duplicate(true)
			var candidate_id := str(location_data.get("id", ""))
			if candidate_id != "":
				locations[candidate_id] = location_data
	elif raw_locations is Dictionary:
		for raw_location_id: Variant in raw_locations:
			var raw_location: Variant = raw_locations[raw_location_id]
			if not raw_location is Dictionary:
				continue
			var location_data: Dictionary = raw_location.duplicate(true)
			var candidate_id := str(location_data.get("id", raw_location_id))
			if candidate_id == "":
				continue
			location_data["id"] = candidate_id
			locations[candidate_id] = location_data


func _assign_missing_entity_locations() -> void:
	for index: int in range(entities.size()):
		var entity: Dictionary = entities[index]
		if str(entity.get("location_id", "")) == "":
			entity["location_id"] = location_id
			entities[index] = entity


func _initial_owned_item_quantity(
		source_items: Variant,
		owner_entity_id: String,
		item_def_id: String
) -> int:
	if not source_items is Array:
		return 0
	var quantity := 0
	for item: Dictionary in source_items:
		var holder: Dictionary = item.get("holder", {})
		if (
			str(item.get("item_def_id", "")) == item_def_id
			and str(holder.get("kind", "")) == "entity"
			and str(holder.get("id", "")) == owner_entity_id
		):
			quantity += int(item.get("quantity", 0))
	return quantity
