extends RefCounted
class_name V5StateStore

const PLAYER_STATIC_KEYS := [
	"id",
	"type",
	"role",
	"display_name",
	"description",
	"tags",
	"interactions",
]

const EXTERNAL_PROJECTION_KEYS := [
	"food_count",
	"injury",
	"mist_salt_echo",
	"inventory_item_ids",
]

var states: Dictionary = {}
var state_defs_by_key: Dictionary = {}
var entity_store: Variant = null
var strict_definitions: bool = false
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var unregistered_state_keys: Dictionary = {}
var last_error: String = ""


func configure_definitions(
		state_definitions: Dictionary,
		source_entity_store: Variant = null,
		strict: bool = false
) -> void:
	state_defs_by_key.clear()
	entity_store = source_entity_store
	strict_definitions = strict
	for definition: Dictionary in state_definitions.values():
		var key := str(definition.get("key", ""))
		if key != "":
			state_defs_by_key[key] = definition.duplicate(true)


func load_from_context(context: Variant) -> Dictionary:
	states.clear()
	validation_errors.clear()
	validation_warnings.clear()
	unregistered_state_keys.clear()
	last_error = ""

	for entity: Dictionary in context.entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id == "":
			continue
		var entity_states: Dictionary = entity.get("states", {})
		for state_key: String in entity_states.keys():
			_set_initial_state(entity_id, state_key, entity_states[state_key])
		var location_id := str(entity.get("location_id", ""))
		if location_id != "" and not entity_states.has("location_id"):
			_set_initial_state(entity_id, "location_id", location_id)

	var player_id := str(context.player.get("id", context.actor_id))
	if player_id == "":
		player_id = "player"
	for state_key: String in context.player.keys():
		if (
			state_key in PLAYER_STATIC_KEYS
			or state_key in EXTERNAL_PROJECTION_KEYS
		):
			continue
		_set_initial_state(player_id, state_key, context.player[state_key])
	if str(context.region_entity_id) != "":
		for state_key: String in context.region_state.keys():
			if state_key in ["id", "display_name", "description", "tags"]:
				continue
			_set_initial_state(
				str(context.region_entity_id),
				state_key,
				context.region_state[state_key]
			)
	if str(context.institution_entity_id) != "":
		for state_key: String in context.institution.keys():
			if state_key in ["id", "display_name", "description", "tags"]:
				continue
			_set_initial_state(
				str(context.institution_entity_id),
				state_key,
				context.institution[state_key]
			)
	return get_contract_report()


func set_state(entity_id: String, state_key: String, value: Variant) -> bool:
	return _write_state(entity_id, state_key, value, "set", false)


func get_state(
		entity_id: String,
		state_key: String,
		default_value: Variant = null
) -> Variant:
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


func apply_state_change(change: Dictionary) -> bool:
	var entity_id := str(change.get("entity_id", ""))
	var state_key := str(change.get("key", ""))
	if entity_id == "" or state_key == "":
		return _reject("invalid_state_change_target")

	if change.has("to"):
		return _write_state(entity_id, state_key, change.get("to"), "set", false)

	if change.has("delta"):
		var current_value: Variant = get_state(entity_id, state_key, 0)
		var delta: Variant = change.get("delta", 0)
		var next_value: Variant
		if current_value is float or delta is float:
			next_value = float(current_value) + float(delta)
		else:
			next_value = int(current_value) + int(delta)
		return _write_state(entity_id, state_key, next_value, "add", false)

	if change.has("degrade"):
		var current_scale := str(get_state(entity_id, state_key, "none"))
		var next_scale := _degrade_scale(
			current_scale,
			int(change.get("degrade", 1))
		)
		return _write_state(entity_id, state_key, next_scale, "degrade", false)

	return _reject("%s:%s:missing_state_operation" % [entity_id, state_key])


func get_contract_report() -> Dictionary:
	return {
		"ok": validation_errors.is_empty(),
		"state_entity_count": states.size(),
		"registered_state_count": state_defs_by_key.size(),
		"unregistered_state_keys": unregistered_state_keys.keys(),
		"errors": validation_errors.duplicate(),
		"warnings": validation_warnings.duplicate(),
	}


func _set_initial_state(entity_id: String, state_key: String, value: Variant) -> bool:
	return _write_state(entity_id, state_key, value, "load", true)


func _write_state(
		entity_id: String,
		state_key: String,
		value: Variant,
		operation: String,
		is_initial: bool
) -> bool:
	last_error = ""
	if entity_id == "" or state_key == "":
		return _reject("missing_state_identity")
	if state_key in EXTERNAL_PROJECTION_KEYS:
		return _reject("%s:%s:external_projection_owned_key" % [
			entity_id,
			state_key,
		])
	if entity_store != null and not entity_store.has_entity(entity_id):
		return _reject("%s:%s:unknown_entity" % [entity_id, state_key])

	var normalized_value: Variant = value
	if not state_defs_by_key.has(state_key):
		unregistered_state_keys[state_key] = true
		var warning := "unregistered_state_key:%s" % state_key
		if strict_definitions:
			return _reject("%s:%s:%s" % [entity_id, state_key, warning])
		if warning not in validation_warnings:
			validation_warnings.append(warning)
	else:
		var definition: Dictionary = state_defs_by_key[state_key]
		normalized_value = _normalize_state_value(value, definition)
		var validation_error := _state_validation_error(
			entity_id,
			state_key,
			normalized_value,
			operation,
			definition,
			is_initial
		)
		if validation_error != "":
			if strict_definitions or not is_initial:
				return _reject(validation_error)
			if validation_error not in validation_warnings:
				validation_warnings.append(validation_error)

	if not states.has(entity_id):
		states[entity_id] = {}
	var entity_state: Dictionary = states[entity_id]
	entity_state[state_key] = normalized_value
	states[entity_id] = entity_state
	return true


func _state_validation_error(
		entity_id: String,
		state_key: String,
		value: Variant,
		operation: String,
		definition: Dictionary,
		is_initial: bool
) -> String:
	if not is_initial:
		var allowed_operations: Array = definition.get("allowed_operations", [])
		if operation not in allowed_operations:
			return "%s:%s:operation_not_allowed:%s" % [
				entity_id,
				state_key,
				operation,
			]

	var owner_kinds: Array = definition.get("owner_kinds", [])
	if entity_store != null and "entity" not in owner_kinds:
		var owner_kind := str(entity_store.get_owner_kind(entity_id))
		if owner_kind not in owner_kinds:
			return "%s:%s:owner_kind_not_allowed:%s" % [
				entity_id,
				state_key,
				owner_kind,
			]

	var value_type := str(definition.get("value_type", ""))
	if not _value_matches_type(value, value_type):
		return "%s:%s:value_type_mismatch:%s" % [entity_id, state_key, value_type]
	if value_type == "enum" and value not in (definition.get("values", []) as Array):
		return "%s:%s:unknown_enum_value:%s" % [entity_id, state_key, value]
	if value is int or value is float:
		if definition.has("minimum") and float(value) < float(definition.get("minimum")):
			return "%s:%s:value_below_minimum" % [entity_id, state_key]
		if definition.has("maximum") and float(value) > float(definition.get("maximum")):
			return "%s:%s:value_above_maximum" % [entity_id, state_key]
	return ""


func _value_matches_type(value: Variant, value_type: String) -> bool:
	match value_type:
		"bool":
			return value is bool
		"int":
			return value is int
		"float":
			return value is float or value is int
		"string", "enum":
			return value is String
	return false


func _normalize_state_value(value: Variant, definition: Dictionary) -> Variant:
	if str(definition.get("value_type", "")) != "int":
		return value
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return int(value)
	return value


func _degrade_scale(value: String, steps: int = 1) -> String:
	var scale := ["extreme", "high", "medium", "low", "none"]
	var index := scale.find(value)
	if index < 0:
		return value
	return scale[min(index + max(steps, 0), scale.size() - 1)]


func _reject(message: String) -> bool:
	last_error = message
	validation_errors.append(message)
	return false
