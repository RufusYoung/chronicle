extends RefCounted
class_name HistoryQualityAudit

const DEFAULT_FIELDS := {
	"quality_flags": [],
	"dangling_major_fact": false,
	"impossible_shop_state": false,
	"unresolved_extreme_hunger": false,
	"contradiction_flags": [],
	"notes": [],
}


func normalize(audit: Dictionary) -> Dictionary:
	var output := audit.duplicate(true)
	for key: String in DEFAULT_FIELDS:
		if not output.has(key):
			var default_value: Variant = DEFAULT_FIELDS[key]
			output[key] = (
				default_value.duplicate(true)
				if default_value is Array or default_value is Dictionary
				else default_value
			)
	return output


func quality_flags(audit: Dictionary) -> Array:
	return (
		normalize(audit).get("quality_flags", []) as Array
	).duplicate()
