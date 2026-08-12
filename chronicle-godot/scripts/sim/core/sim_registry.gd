extends RefCounted
class_name V5SimRegistry

const DEFINITION_COLLECTIONS := {
	"state_defs": {
		"kind": "state",
		"id_field": "state_def_id",
	},
	"object_defs": {
		"kind": "object",
		"id_field": "object_def_id",
	},
}

const STATE_VALUE_TYPES := [
	"bool",
	"int",
	"float",
	"string",
	"enum",
]

const STATE_OPERATIONS := ["set", "add", "degrade"]
const STATE_OWNER_KINDS := ["entity", "character", "object", "region", "institution"]
const STATE_UI_VISIBILITY := ["hidden", "summary", "detail"]

var definitions: Dictionary = {}
var action_rules: Array = []
var definition_errors: Array[String] = []
var definition_warnings: Array[String] = []
var definition_sources: Dictionary = {}


func register_definition(
		kind: String,
		definition_id: String,
		data: Dictionary,
		source_path: String = ""
) -> bool:
	var normalized_kind := kind.strip_edges()
	var normalized_id := definition_id.strip_edges()
	if normalized_kind == "":
		return _definition_error("missing_definition_kind")
	if normalized_id == "":
		return _definition_error("%s:missing_definition_id" % normalized_kind)

	var group := _ensure_group(normalized_kind)
	if group.has(normalized_id):
		return _definition_error(
			"%s:%s:duplicate_definition_id" % [normalized_kind, normalized_id]
		)

	var normalized := _normalize_definition(normalized_kind, data)
	var id_field := _definition_id_field(normalized_kind)
	if id_field != "":
		var embedded_id := str(normalized.get(id_field, ""))
		if embedded_id != "" and embedded_id != normalized_id:
			return _definition_error(
				"%s:%s:definition_id_mismatch:%s" % [
					normalized_kind,
					normalized_id,
					embedded_id,
				]
			)
		normalized[id_field] = normalized_id
	var validation := _validate_definition(
		normalized_kind,
		normalized_id,
		normalized
	)
	for warning: String in validation.get("warnings", []):
		definition_warnings.append(warning)
	var errors: Array = validation.get("errors", [])
	if not errors.is_empty():
		for error: String in errors:
			definition_errors.append(error)
		return false
	var identity_field := _definition_identity_field(normalized_kind)
	if identity_field != "":
		var logical_identity := str(normalized.get(identity_field, ""))
		for existing_id: String in group.keys():
			var existing: Dictionary = group[existing_id]
			if str(existing.get(identity_field, "")) == logical_identity:
				return _definition_error(
					"%s:%s:duplicate_%s:%s" % [
						normalized_kind,
						normalized_id,
						identity_field,
						existing_id,
					]
				)

	group[normalized_id] = normalized
	if source_path != "":
		definition_sources["%s:%s" % [normalized_kind, normalized_id]] = source_path
	return true


func has_definition(kind: String, definition_id: String) -> bool:
	return definitions.has(kind) and (definitions[kind] as Dictionary).has(
		definition_id
	)


func get_definition(kind: String, definition_id: String) -> Dictionary:
	if not has_definition(kind, definition_id):
		return {}
	return ((definitions[kind] as Dictionary)[definition_id] as Dictionary).duplicate(
		true
	)


func list_definitions(kind: String) -> Dictionary:
	if not definitions.has(kind):
		return {}
	return (definitions[kind] as Dictionary).duplicate(true)


func get_state_definitions_by_key() -> Dictionary:
	var rows: Dictionary = {}
	for definition: Dictionary in list_definitions("state").values():
		var key := str(definition.get("key", ""))
		if key != "":
			rows[key] = definition.duplicate(true)
	return rows


func load_raw_definitions(path: String, strict: bool = true) -> Dictionary:
	var data := load_json(path)
	if data.is_empty():
		_definition_error("%s:definition_file_not_loaded" % path)
		return _definition_report(0)

	var registered_count := 0
	var recognized_collection := false
	for collection_key: String in DEFINITION_COLLECTIONS.keys():
		if not data.has(collection_key):
			continue
		recognized_collection = true
		var spec: Dictionary = DEFINITION_COLLECTIONS[collection_key]
		var values: Variant = data.get(collection_key, [])
		if not values is Array:
			_definition_error("%s:%s:not_an_array" % [path, collection_key])
			continue
		for index: int in range((values as Array).size()):
			var value: Variant = (values as Array)[index]
			if not value is Dictionary:
				_definition_error(
					"%s:%s:%d:not_a_dictionary" % [path, collection_key, index]
				)
				continue
			var definition: Dictionary = (value as Dictionary).duplicate(true)
			var definition_id := str(definition.get(spec.get("id_field", ""), ""))
			if definition_id == "" and not strict:
				definition_id = _legacy_definition_id(
					str(spec.get("kind", "")),
					definition
				)
				if definition_id != "":
					definition[str(spec.get("id_field", ""))] = definition_id
			if register_definition(
				str(spec.get("kind", "")),
				definition_id,
				definition,
				path
			):
				registered_count += 1

	if not recognized_collection:
		_definition_error("%s:no_supported_definition_collection" % path)
	return _definition_report(registered_count)


func load_raw_definition_files(
		paths: Array,
		strict: bool = true,
		clear_existing: bool = true
) -> Dictionary:
	if clear_existing:
		definitions.clear()
		definition_sources.clear()
	definition_errors.clear()
	definition_warnings.clear()

	var registered_count := 0
	for path_value: Variant in paths:
		var report := load_raw_definitions(str(path_value), strict)
		registered_count += int(report.get("registered_count", 0))
	return _definition_report(registered_count)


func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open JSON file: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed

	push_error("JSON file did not contain an object: %s" % path)
	return {}


func load_action_rules(paths: Array) -> void:
	action_rules.clear()
	for path: String in paths:
		var data := load_json(path)
		for rule: Variant in data.get("rules", []):
			if rule is Dictionary:
				action_rules.append((rule as Dictionary).duplicate(true))


func get_action_rules() -> Array:
	return action_rules.duplicate(true)


func get_definition_report() -> Dictionary:
	return _definition_report(_definition_count())


func _validate_definition(
		kind: String,
		definition_id: String,
		definition: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if kind not in ["state", "object"]:
		return {"errors": errors, "warnings": warnings}

	var version := int(definition.get("definition_version", 0))
	if version < 1:
		errors.append("%s:%s:invalid_definition_version" % [kind, definition_id])

	if kind == "state":
		_validate_state_definition(definition_id, definition, errors)
	elif kind == "object":
		_validate_object_definition(definition_id, definition, errors)
	return {"errors": errors, "warnings": warnings}


func _validate_state_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	var key := str(definition.get("key", ""))
	if key == "":
		errors.append("state:%s:missing_key" % definition_id)
	var value_type := str(definition.get("value_type", ""))
	if value_type not in STATE_VALUE_TYPES:
		errors.append("state:%s:invalid_value_type:%s" % [definition_id, value_type])
	var owner_kinds: Variant = definition.get("owner_kinds", [])
	if not owner_kinds is Array or (owner_kinds as Array).is_empty():
		errors.append("state:%s:missing_owner_kinds" % definition_id)
	elif not _array_values_allowed(owner_kinds, STATE_OWNER_KINDS):
		errors.append("state:%s:invalid_owner_kinds" % definition_id)
	var operations: Variant = definition.get("allowed_operations", [])
	if not operations is Array or (operations as Array).is_empty():
		errors.append("state:%s:missing_allowed_operations" % definition_id)
	elif not _array_values_allowed(operations, STATE_OPERATIONS):
		errors.append("state:%s:invalid_allowed_operations" % definition_id)
	if value_type == "enum":
		var values: Variant = definition.get("values", [])
		if not values is Array or (values as Array).is_empty():
			errors.append("state:%s:missing_enum_values" % definition_id)
	if str(definition.get("persistence", "")) == "":
		errors.append("state:%s:missing_persistence" % definition_id)
	var ui_visibility := str(definition.get("ui_visibility", ""))
	if ui_visibility not in STATE_UI_VISIBILITY:
		errors.append("state:%s:invalid_ui_visibility" % definition_id)
	if definition.has("minimum") and definition.has("maximum"):
		if float(definition.get("minimum")) > float(definition.get("maximum")):
			errors.append("state:%s:invalid_numeric_range" % definition_id)
	if definition.has("default") and value_type in STATE_VALUE_TYPES:
		var default_value: Variant = definition.get("default")
		if not _definition_value_matches_type(default_value, value_type):
			errors.append("state:%s:default_type_mismatch" % definition_id)
		elif value_type == "enum" and default_value not in (
			definition.get("values", []) as Array
		):
			errors.append("state:%s:default_not_in_enum" % definition_id)
		elif default_value is int or default_value is float:
			if definition.has("minimum") and float(default_value) < float(
				definition.get("minimum")
			):
				errors.append("state:%s:default_below_minimum" % definition_id)
			if definition.has("maximum") and float(default_value) > float(
				definition.get("maximum")
			):
				errors.append("state:%s:default_above_maximum" % definition_id)


func _validate_object_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	if str(definition.get("type", "")) == "":
		errors.append("object:%s:missing_type" % definition_id)
	if str(definition.get("owner_kind", "")) == "":
		errors.append("object:%s:missing_owner_kind" % definition_id)
	var default_tags: Variant = definition.get("default_tags", [])
	if not default_tags is Array:
		errors.append("object:%s:default_tags_not_array" % definition_id)


func _legacy_definition_id(kind: String, definition: Dictionary) -> String:
	if kind == "state":
		var key := str(definition.get("key", ""))
		return "state.%s" % key if key != "" else ""
	if kind == "object":
		var object_type := str(definition.get("type", ""))
		return "object.%s" % object_type if object_type != "" else ""
	return ""


func _definition_identity_field(kind: String) -> String:
	if kind == "state":
		return "key"
	if kind == "object":
		return "type"
	return ""


func _definition_id_field(kind: String) -> String:
	if kind == "state":
		return "state_def_id"
	if kind == "object":
		return "object_def_id"
	return ""


func _normalize_definition(kind: String, data: Dictionary) -> Dictionary:
	var normalized := data.duplicate(true)
	if normalized.has("definition_version"):
		normalized["definition_version"] = int(normalized.get("definition_version"))
	if kind != "state" or str(normalized.get("value_type", "")) != "int":
		return normalized
	for field: String in ["default", "minimum", "maximum"]:
		if not normalized.has(field):
			continue
		var value: Variant = normalized[field]
		if value is float and is_equal_approx(float(value), roundf(float(value))):
			normalized[field] = int(value)
	return normalized


func _array_values_allowed(values: Array, allowed_values: Array) -> bool:
	for value: Variant in values:
		if value not in allowed_values:
			return false
	return true


func _definition_value_matches_type(value: Variant, value_type: String) -> bool:
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


func _definition_report(registered_count: int) -> Dictionary:
	return {
		"ok": definition_errors.is_empty(),
		"registered_count": registered_count,
		"total_definition_count": _definition_count(),
		"errors": definition_errors.duplicate(),
		"warnings": definition_warnings.duplicate(),
	}


func _definition_count() -> int:
	var count := 0
	for group: Dictionary in definitions.values():
		count += group.size()
	return count


func _definition_error(message: String) -> bool:
	definition_errors.append(message)
	return false


func _ensure_group(kind: String) -> Dictionary:
	if not definitions.has(kind):
		definitions[kind] = {}
	return definitions[kind]
