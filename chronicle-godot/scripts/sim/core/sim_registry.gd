extends RefCounted
class_name V5SimRegistry

var definitions: Dictionary = {}
var action_rules: Array = []


func register_definition(kind: String, definition_id: String, data: Dictionary) -> void:
	var group := _ensure_group(kind)
	group[definition_id] = data.duplicate(true)


func get_definition(kind: String, definition_id: String) -> Dictionary:
	if not definitions.has(kind):
		return {}

	var group: Dictionary = definitions[kind]
	if not group.has(definition_id):
		return {}

	return (group[definition_id] as Dictionary).duplicate(true)


func list_definitions(kind: String) -> Dictionary:
	if not definitions.has(kind):
		return {}

	return (definitions[kind] as Dictionary).duplicate(true)


func load_raw_definitions(_path: String) -> void:
	# Placeholder for the later Raw / Rule prototype.
	pass


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


func _ensure_group(kind: String) -> Dictionary:
	if not definitions.has(kind):
		definitions[kind] = {}

	return definitions[kind]
