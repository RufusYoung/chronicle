extends RefCounted
class_name V5CharacterProgressProjector

const ATTRIBUTE_KEYS := [
	"strength",
	"dexterity",
	"wisdom",
	"charisma",
	"constitution",
	"perception",
]


func build(
		entity_id: String,
		state_store: Variant,
		feature_store: Variant
) -> Dictionary:
	var attributes: Dictionary = {}
	for key: String in ATTRIBUTE_KEYS:
		attributes[key] = int(state_store.get_state(entity_id, key, 0))
	return {
		"entity_id": entity_id,
		"attributes": attributes,
		"talent_assignment_ids": _ids(
			feature_store.list_talent_assignments(entity_id),
			"talent_assignment_id"
		),
		"trait_instance_ids": _ids(
			feature_store.list_trait_instances(entity_id),
			"trait_instance_id"
		),
		"mark_instance_ids": _ids(
			feature_store.list_mark_instances(entity_id),
			"mark_instance_id"
		),
		"skill_progress_ids": _ids(
			feature_store.list_skill_progress(entity_id),
			"skill_progress_id"
		),
	}


func _ids(rows: Array, id_field: String) -> Array:
	var ids: Array = []
	for row: Dictionary in rows:
		ids.append(str(row.get(id_field, "")))
	return ids
