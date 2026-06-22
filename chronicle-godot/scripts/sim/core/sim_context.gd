extends RefCounted
class_name V5SimContext

var world_id: String = ""
var actor_id: String = ""
var location_id: String = ""
var visible_entity_ids: Array = []
var region_state: Dictionary = {}
var known_fact_ids: Array = []


func _init(initial_data: Dictionary = {}) -> void:
	world_id = str(initial_data.get("world_id", ""))
	actor_id = str(initial_data.get("actor_id", ""))
	location_id = str(initial_data.get("location_id", ""))
	visible_entity_ids = (initial_data.get("visible_entity_ids", []) as Array).duplicate(true)
	region_state = (initial_data.get("region_state", {}) as Dictionary).duplicate(true)
	known_fact_ids = (initial_data.get("known_fact_ids", []) as Array).duplicate(true)


func to_dict() -> Dictionary:
	return {
		"world_id": world_id,
		"actor_id": actor_id,
		"location_id": location_id,
		"visible_entity_ids": visible_entity_ids.duplicate(true),
		"region_state": region_state.duplicate(true),
		"known_fact_ids": known_fact_ids.duplicate(true),
	}
