extends RefCounted
class_name V5RelationshipStore

const SUPPORTED_AXES := [
	"trust",
	"fear",
	"gratitude",
	"resentment",
	"discipline_respect",
	"familiarity",
	"debt",
	"shame",
]

var relations: Dictionary = {}
var axis_defs: Dictionary = {}


func _init() -> void:
	_load_fallback_axis_defs()


func load_axis_defs(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open relationship axis defs: %s" % path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Relationship axis defs must be a JSON object: %s" % path)
		return

	for axis_def: Variant in (parsed as Dictionary).get("axes", []):
		if axis_def is Dictionary:
			var axis_id := str((axis_def as Dictionary).get("axis_id", ""))
			if axis_id != "":
				axis_defs[axis_id] = (axis_def as Dictionary).duplicate(true)


func get_axis_def(axis: String) -> Dictionary:
	if axis_defs.has(axis):
		return (axis_defs[axis] as Dictionary).duplicate(true)
	return {}


func get_axis_range(axis: String) -> Dictionary:
	var axis_def := get_axis_def(axis)
	return {
		"min": int(axis_def.get("range_min", 0)),
		"max": int(axis_def.get("range_max", 100)),
		"default": int(axis_def.get("default_value", 0)),
	}


func clamp_axis_value(axis: String, value: Variant) -> int:
	var axis_range := get_axis_range(axis)
	return clampi(int(value), int(axis_range.get("min", 0)), int(axis_range.get("max", 100)))


func get_relation_tier(source_id: String, target_id: String, axis: String) -> String:
	var value := int(get_relation(source_id, target_id, axis, _axis_default(axis)))
	var axis_def := get_axis_def(axis)
	var thresholds: Dictionary = axis_def.get("tier_thresholds", {})
	for tier: String in thresholds.keys():
		var range_values: Array = thresholds[tier]
		if range_values.size() >= 2 and value >= int(range_values[0]) and value <= int(range_values[1]):
			return tier
	return "none"


func set_relation(source_id: String, target_id: String, axis: String, value: Variant) -> void:
	if not _axis_is_supported(axis):
		return

	var source_relations := _ensure_source(source_id)
	var target_relations := _ensure_target(source_relations, target_id)
	target_relations[axis] = clamp_axis_value(axis, value)


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
	var current_value := int(get_relation(source_id, target_id, axis, _axis_default(axis)))
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
	return axis_defs.has(axis) or axis in SUPPORTED_AXES


func _axis_default(axis: String) -> int:
	return int(get_axis_range(axis).get("default", 0))


func _load_fallback_axis_defs() -> void:
	for axis: String in SUPPORTED_AXES:
		var is_signed := axis == "trust" or axis == "discipline_respect"
		axis_defs[axis] = {
			"axis_id": axis,
			"display_name": axis,
			"range_min": -100 if is_signed else 0,
			"range_max": 100,
			"default_value": 0,
			"axis_type": "signed" if is_signed else "positive",
			"description": "",
			"behavior_effects": [],
			"tier_thresholds": _signed_tiers() if is_signed else _positive_tiers(),
		}


func _positive_tiers() -> Dictionary:
	return {
		"none": [0, 0],
		"low": [1, 24],
		"medium": [25, 49],
		"high": [50, 74],
		"extreme": [75, 100],
	}


func _signed_tiers() -> Dictionary:
	return {
		"hostile": [-100, -50],
		"negative": [-49, -1],
		"neutral": [0, 0],
		"positive": [1, 49],
		"strong": [50, 100],
	}


func _ensure_source(source_id: String) -> Dictionary:
	if not relations.has(source_id):
		relations[source_id] = {}

	return relations[source_id]


func _ensure_target(source_relations: Dictionary, target_id: String) -> Dictionary:
	if not source_relations.has(target_id):
		source_relations[target_id] = {}

	return source_relations[target_id]
