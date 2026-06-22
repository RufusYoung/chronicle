extends RefCounted
class_name V5StateStore

var states: Dictionary = {}


func set_state(entity_id: String, state_key: String, value: Variant) -> void:
	if not states.has(entity_id):
		states[entity_id] = {}

	var entity_state: Dictionary = states[entity_id]
	entity_state[state_key] = value


func get_state(entity_id: String, state_key: String, default_value: Variant = null) -> Variant:
	if not states.has(entity_id):
		return default_value

	var entity_state: Dictionary = states[entity_id]
	return entity_state.get(state_key, default_value)


func list_states(entity_id: String) -> Dictionary:
	if not states.has(entity_id):
		return {}

	return (states[entity_id] as Dictionary).duplicate(true)
