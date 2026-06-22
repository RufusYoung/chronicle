extends RefCounted
class_name V5SimRegistry

var definitions: Dictionary = {}


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


func _ensure_group(kind: String) -> Dictionary:
	if not definitions.has(kind):
		definitions[kind] = {}

	return definitions[kind]
