extends RefCounted
class_name V5RelationshipStore

const SUPPORTED_AXES := [
	"trust",
	"fear",
	"gratitude",
	"resentment",
	"discipline_respect",
	"shame",
]

var relations: Dictionary = {}


func set_relation(source_id: String, target_id: String, axis: String, value: Variant) -> void:
	if not _axis_is_supported(axis):
		return

	var source_relations := _ensure_source(source_id)
	var target_relations := _ensure_target(source_relations, target_id)
	target_relations[axis] = int(value)


func get_relation(
	source_id: String,
	target_id: String,
	axis: String,
	default_value: Variant = 0
) -> Variant:
	if not relations.has(source_id):
		return default_value

	var source_relations: Dictionary = relations[source_id]
	if not source_relations.has(target_id):
		return default_value

	var target_relations: Dictionary = source_relations[target_id]
	return target_relations.get(axis, default_value)


func adjust_relation(source_id: String, target_id: String, axis: String, delta: int) -> void:
	var current_value := int(get_relation(source_id, target_id, axis, 0))
	set_relation(source_id, target_id, axis, current_value + delta)


func list_relations_for(source_id: String) -> Dictionary:
	if not relations.has(source_id):
		return {}

	return (relations[source_id] as Dictionary).duplicate(true)


func apply_relationship_change(change: Dictionary) -> void:
	var source_id := str(change.get("source_id", ""))
	var target_id := str(change.get("target_id", ""))
	var axis := str(change.get("axis", ""))
	if source_id == "" or target_id == "" or axis == "":
		return

	if change.has("delta"):
		adjust_relation(source_id, target_id, axis, int(change.get("delta", 0)))
	elif change.has("to"):
		set_relation(source_id, target_id, axis, change.get("to"))
	elif change.has("value"):
		set_relation(source_id, target_id, axis, change.get("value"))


func _axis_is_supported(axis: String) -> bool:
	return axis in SUPPORTED_AXES


func _ensure_source(source_id: String) -> Dictionary:
	if not relations.has(source_id):
		relations[source_id] = {}

	return relations[source_id]


func _ensure_target(source_relations: Dictionary, target_id: String) -> Dictionary:
	if not source_relations.has(target_id):
		source_relations[target_id] = {}

	return source_relations[target_id]
