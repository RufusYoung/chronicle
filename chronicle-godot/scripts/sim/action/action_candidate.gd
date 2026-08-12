extends RefCounted
class_name V5ActionCandidate

var action_id: String = ""
var rule_id: String = ""
var label: String = ""
var action_type: String = ""
var transaction_mode: String = ""
var effect_template_id: String = ""
var source_rule_id: String = ""
var target_id: String = ""
var target_display_name: String = ""
var priority: int = 0
var domain: String = ""
var can_execute: bool = true
var blocked_reason: String = ""
var player_requirements: Array = []
var extra: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	rule_id = str(data.get("rule_id", data.get("source_rule_id", "")))
	action_id = str(data.get("action_id", rule_id))
	label = str(data.get("label", ""))
	action_type = str(data.get("action_type", ""))
	transaction_mode = _string_or_empty(data.get("transaction_mode", ""))
	effect_template_id = _string_or_empty(data.get("effect_template_id", ""))
	source_rule_id = rule_id
	target_id = str(data.get("target_id", ""))
	target_display_name = str(data.get("target_display_name", ""))
	priority = int(data.get("priority", 0))
	domain = str(data.get("domain", ""))
	can_execute = bool(data.get("can_execute", true))
	blocked_reason = str(data.get("blocked_reason", ""))
	player_requirements = (
		data.get("player_requirements", []) as Array
	).duplicate(true)
	extra = (data.get("extra", {}) as Dictionary).duplicate(true)


func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"rule_id": rule_id,
		"label": label,
		"action_type": action_type,
		"transaction_mode": transaction_mode,
		"effect_template_id": effect_template_id,
		"source_rule_id": source_rule_id,
		"target_id": target_id,
		"target_display_name": target_display_name,
		"priority": priority,
		"domain": domain,
		"can_execute": can_execute,
		"blocked_reason": blocked_reason,
		"player_requirements": player_requirements.duplicate(true),
		"extra": extra.duplicate(true),
	}


func _string_or_empty(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)
