extends RefCounted
class_name V5EntityStore

var entities: Dictionary = {}


func add_entity(entity_id: String, data: Dictionary = {}) -> void:
	var entity_data := data.duplicate(true)
	entity_data["entity_id"] = entity_id
	entities[entity_id] = entity_data


func get_entity(entity_id: String) -> Dictionary:
	if not entities.has(entity_id):
		return {}

	return (entities[entity_id] as Dictionary).duplicate(true)


func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)


func list_entities() -> Dictionary:
	return entities.duplicate(true)
