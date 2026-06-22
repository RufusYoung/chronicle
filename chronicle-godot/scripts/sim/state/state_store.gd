extends RefCounted
class_name V5StateStore

var states: Dictionary = {}


func load_from_context(context: Variant) -> void:
	for entity: Dictionary in context.entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id == "":
			continue
		var entity_states: Dictionary = entity.get("states", {})
		for state_key: String in entity_states.keys():
			set_state(entity_id, state_key, entity_states[state_key])

	var player_id := str(context.get_player_value("id", "player"))
	for state_key: String in context.player.keys():
		set_state(player_id, state_key, context.player[state_key])


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


func list_entity_states(entity_id: String) -> Dictionary:
	return list_states(entity_id)


func apply_state_change(change: Dictionary) -> void:
	var entity_id := str(change.get("entity_id", ""))
	var state_key := str(change.get("key", ""))
	if entity_id == "" or state_key == "":
		return

	if change.has("to"):
		set_state(entity_id, state_key, change.get("to"))
		return

	if change.has("delta"):
		var current_value: Variant = get_state(entity_id, state_key, 0)
		set_state(entity_id, state_key, int(current_value) + int(change.get("delta", 0)))
		return

	if change.has("degrade"):
		var current_scale := str(get_state(entity_id, state_key, "none"))
		set_state(entity_id, state_key, _degrade_scale(current_scale, int(change.get("degrade", 1))))


func _degrade_scale(value: String, steps: int = 1) -> String:
	var scale := ["extreme", "high", "medium", "low", "none"]
	var index := scale.find(value)
	if index < 0:
		return value

	return scale[min(index + max(steps, 0), scale.size() - 1)]
