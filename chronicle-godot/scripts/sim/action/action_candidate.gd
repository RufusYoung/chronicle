extends RefCounted
class_name V5ActionCandidate

var action_id: String = ""
var label: String = ""
var action_type: String = ""
var source_rule_id: String = ""
var target_id: String = ""
var priority: int = 0


func _init(data: Dictionary = {}) -> void:
	action_id = str(data.get("action_id", ""))
	label = str(data.get("label", ""))
	action_type = str(data.get("action_type", ""))
	source_rule_id = str(data.get("source_rule_id", ""))
	target_id = str(data.get("target_id", ""))
	priority = int(data.get("priority", 0))


func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"label": label,
		"action_type": action_type,
		"source_rule_id": source_rule_id,
		"target_id": target_id,
		"priority": priority,
	}
