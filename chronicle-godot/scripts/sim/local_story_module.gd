extends RefCounted
class_name LocalStoryModule


func get_module_id() -> String:
	return ""


func get_module_version() -> String:
	return "0.0.0"


func get_region_id() -> String:
	return ""


func get_location_ids() -> Array:
	return []


func get_required_state_keys() -> Array:
	return []


func initialize_module_state(
		_state: Variant,
		_profile: Dictionary = {}
	) -> void:
	pass


func tick_module(_state: Variant) -> Array:
	return []


func build_narratable_states(_state: Variant) -> Array:
	return []


func build_action_candidates(
		_state: Variant,
		_actor_state: Dictionary,
		_narratable_state_id: String
	) -> Array:
	return []


func resolve_action(
		_state: Variant,
		_actor_state: Dictionary,
		action_id: String,
		_narratable_state_id: String
	) -> Dictionary:
	return {
		"ok": false,
		"action_id": action_id,
		"error": "not_implemented",
	}


func build_history_signature(_state: Variant) -> Dictionary:
	return {}


func audit_quality(
		_state: Variant,
		_signature: Dictionary = {}
	) -> Dictionary:
	return {
		"quality_flags": ["not_implemented"],
	}


func describe_module() -> Dictionary:
	return {
		"module_id": get_module_id(),
		"module_version": get_module_version(),
		"region_id": get_region_id(),
		"locations": get_location_ids(),
		"module_stage": "contract",
	}
