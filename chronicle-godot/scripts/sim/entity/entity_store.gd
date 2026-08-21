extends RefCounted
class_name V5EntityStore

const PLAYER_STATIC_KEYS := [
	"id",
	"type",
	"role",
	"display_name",
	"description",
	"tags",
	"interactions",
]

const MUTABLE_STATIC_KEYS := [
	"display_name",
	"description",
	"tags",
	"goal",
	"runtime_response",
	"need_signals",
]

var entities: Dictionary = {}
var entity_order: Array[String] = []
var object_defs_by_type: Dictionary = {}
var strict_definitions: bool = false
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var last_error: String = ""


func configure_definitions(
		object_definitions: Dictionary,
		strict: bool = false
) -> void:
	object_defs_by_type.clear()
	strict_definitions = strict
	for definition: Dictionary in object_definitions.values():
		var object_type := str(definition.get("type", ""))
		if object_type != "":
			object_defs_by_type[object_type] = definition.duplicate(true)


func load_from_context(context: Variant) -> Dictionary:
	entities.clear()
	entity_order.clear()
	validation_errors.clear()
	validation_warnings.clear()
	last_error = ""

	for entity: Dictionary in context.entities:
		add_entity(str(entity.get("id", "")), entity)
	if str(context.region_entity_id) != "" and not context.region_state.is_empty():
		add_entity(str(context.region_entity_id), {
			"type": "region",
			"display_name": str(context.region_state.get("display_name", "")),
			"tags": ["region"],
		})
	if (
		str(context.institution_entity_id) != ""
		and not context.institution.is_empty()
	):
		add_entity(str(context.institution_entity_id), {
			"type": "institution",
			"display_name": str(context.institution.get("display_name", "")),
			"tags": ["institution"],
		})

	var player_source: Dictionary = context.player
	var player_id := str(player_source.get("id", context.actor_id))
	if player_id == "":
		player_id = "player"
	var player_entity := _player_entity_data(player_id, player_source)
	add_entity(player_id, player_entity)
	return get_contract_report()


func add_entity(entity_id: String, data: Dictionary = {}) -> bool:
	last_error = ""
	var normalized_id := entity_id.strip_edges()
	if normalized_id == "":
		return _reject("missing_entity_id")
	if entities.has(normalized_id):
		return _reject("%s:duplicate_entity_id" % normalized_id)

	var entity_data := data.duplicate(true)
	entity_data.erase("entity_id")
	entity_data.erase("states")
	entity_data.erase("location_id")
	entity_data["id"] = normalized_id
	var object_type := str(entity_data.get("type", ""))
	if object_type == "":
		return _reject("%s:missing_entity_type" % normalized_id)
	if not object_defs_by_type.has(object_type):
		var message := "%s:unknown_entity_type:%s" % [normalized_id, object_type]
		if strict_definitions:
			return _reject(message)
		validation_warnings.append(message)
	else:
		_apply_default_tags(entity_data, object_defs_by_type[object_type])

	entities[normalized_id] = entity_data
	entity_order.append(normalized_id)
	return true


func apply_entity_change(change: Dictionary) -> bool:
	last_error = ""
	match str(change.get("operation", "")):
		"create":
			var entity: Variant = change.get("entity", {})
			if not entity is Dictionary:
				return _reject("entity_create_data_invalid")
			var entity_id := str((entity as Dictionary).get(
				"id", change.get("entity_id", "")
			))
			return add_entity(entity_id, entity as Dictionary)
		"update":
			return _update_entity(
				str(change.get("entity_id", "")),
				change.get("fields", {})
			)
		"retire":
			return _retire_entity(change)
	return _reject("entity_change_operation_invalid:%s" % str(
		change.get("operation", "")
	))


func is_entity_active(entity_id: String) -> bool:
	if not entities.has(entity_id):
		return false
	return str((entities[entity_id] as Dictionary).get(
		"lifecycle_status", "active"
	)) != "retired"


func get_entity(entity_id: String) -> Dictionary:
	if not entities.has(entity_id):
		return {}
	return (entities[entity_id] as Dictionary).duplicate(true)


func has_entity(entity_id: String) -> bool:
	return entities.has(entity_id)


func get_owner_kind(entity_id: String) -> String:
	var entity := get_entity(entity_id)
	var object_type := str(entity.get("type", ""))
	if object_defs_by_type.has(object_type):
		return str((object_defs_by_type[object_type] as Dictionary).get(
			"owner_kind",
			"entity"
		))
	return "entity"


func list_entities() -> Dictionary:
	return entities.duplicate(true)


func list_entity_rows(excluded_ids: Array = []) -> Array:
	var rows: Array = []
	for entity_id: String in entity_order:
		if entity_id in excluded_ids or not entities.has(entity_id):
			continue
		rows.append((entities[entity_id] as Dictionary).duplicate(true))
	return rows


func to_save_data() -> Dictionary:
	return entities.duplicate(true)


func load_save_data(data: Variant) -> Dictionary:
	entities.clear()
	entity_order.clear()
	validation_errors.clear()
	validation_warnings.clear()
	last_error = ""
	if not data is Dictionary:
		_reject("save_entities_not_dictionary")
		return get_contract_report()
	for entity_id_value: Variant in (data as Dictionary).keys():
		var entity_id := str(entity_id_value)
		var value: Variant = (data as Dictionary).get(entity_id_value)
		if not value is Dictionary:
			_reject("%s:save_entity_not_dictionary" % entity_id)
			continue
		add_entity(entity_id, value)
	return get_contract_report()


func get_contract_report() -> Dictionary:
	return {
		"ok": validation_errors.is_empty(),
		"entity_count": entities.size(),
		"errors": validation_errors.duplicate(),
		"warnings": validation_warnings.duplicate(),
	}


func _update_entity(entity_id: String, fields_value: Variant) -> bool:
	if entity_id == "" or not entities.has(entity_id):
		return _reject("entity_update_unknown:%s" % entity_id)
	if not is_entity_active(entity_id):
		return _reject("entity_update_retired:%s" % entity_id)
	if not fields_value is Dictionary or (fields_value as Dictionary).is_empty():
		return _reject("entity_update_fields_invalid:%s" % entity_id)
	var entity: Dictionary = (entities[entity_id] as Dictionary).duplicate(true)
	for key_value: Variant in (fields_value as Dictionary).keys():
		var key := str(key_value)
		if key not in MUTABLE_STATIC_KEYS:
			return _reject("entity_update_field_forbidden:%s:%s" % [
				entity_id, key
			])
		var value: Variant = (fields_value as Dictionary).get(key_value)
		if key == "tags" and not value is Array:
			return _reject("entity_update_tags_invalid:%s" % entity_id)
		if key == "tags":
			var current_tags: Array = entity.get("tags", [])
			var updated_tags: Array = value as Array
			var protected_player := (
				entity_id == "player" or "player" in current_tags
			)
			if protected_player and "player" not in updated_tags:
				return _reject("entity_update_player_tag_removed:%s" % entity_id)
			if not protected_player and "player" in updated_tags:
				return _reject("entity_update_player_tag_granted:%s" % entity_id)
		if key in ["runtime_response", "need_signals"] and not value is Dictionary:
			return _reject("entity_update_dictionary_invalid:%s:%s" % [
				entity_id, key
			])
		entity[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	entities[entity_id] = entity
	return true


func _retire_entity(change: Dictionary) -> bool:
	var entity_id := str(change.get("entity_id", ""))
	if entity_id == "" or not entities.has(entity_id):
		return _reject("entity_retire_unknown:%s" % entity_id)
	if not is_entity_active(entity_id):
		return _reject("entity_already_retired:%s" % entity_id)
	var entity: Dictionary = (entities[entity_id] as Dictionary).duplicate(true)
	if (
		entity_id == "player"
		or str(entity.get("type", "")) == "region"
		or "player" in (entity.get("tags", []) as Array)
	):
		return _reject("entity_retire_protected:%s" % entity_id)
	entity["lifecycle_status"] = "retired"
	entity["retired_fact_id"] = str(change.get("retired_fact_id", ""))
	entity["retired_day"] = int(change.get("day", 0))
	entity["retirement_reason"] = str(change.get("reason", ""))
	entities[entity_id] = entity
	return true


func _player_entity_data(player_id: String, source: Dictionary) -> Dictionary:
	var data := {
		"id": player_id,
		"type": str(source.get("type", "person")),
		"role": str(source.get("role", "")),
		"display_name": str(source.get("display_name", "")),
		"description": str(source.get("description", "")),
		"tags": (source.get("tags", ["person", "player"]) as Array).duplicate(true),
	}
	for key: String in PLAYER_STATIC_KEYS:
		if source.has(key):
			data[key] = source.get(key)
	return data


func _apply_default_tags(entity: Dictionary, definition: Dictionary) -> void:
	var tags: Array = (entity.get("tags", []) as Array).duplicate(true)
	for tag: Variant in definition.get("default_tags", []):
		if tag not in tags:
			tags.append(tag)
	entity["tags"] = tags


func _reject(message: String) -> bool:
	last_error = message
	validation_errors.append(message)
	return false
