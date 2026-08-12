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

var entities: Dictionary = {}
var entity_order: Array[String] = []
var object_defs_by_type: Dictionary = {}
var strict_definitions: bool = false
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []


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


func get_contract_report() -> Dictionary:
	return {
		"ok": validation_errors.is_empty(),
		"entity_count": entities.size(),
		"errors": validation_errors.duplicate(),
		"warnings": validation_warnings.duplicate(),
	}


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
	validation_errors.append(message)
	return false
