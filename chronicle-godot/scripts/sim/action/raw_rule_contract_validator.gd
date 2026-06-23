extends RefCounted
class_name V5RawRuleContractValidator

const MODE_EFFECT_TEMPLATE := "effect_template"
const MODE_CANDIDATE_ONLY := "candidate_only"


func validate_rules(rules: Array, effect_templates: Dictionary) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []

	for index: int in range(rules.size()):
		var rule_value: Variant = rules[index]
		if not rule_value is Dictionary:
			errors.append("rule_at_index_%s_is_not_dictionary" % index)
			continue

		var rule: Dictionary = rule_value
		var rule_id := str(rule.get("rule_id", ""))
		if rule_id == "":
			rule_id = "rule_at_index_%s" % index

		if not rule.has("transaction_mode"):
			errors.append("%s:missing_transaction_mode" % rule_id)
			continue

		var transaction_mode := str(rule.get("transaction_mode", ""))
		if transaction_mode != MODE_EFFECT_TEMPLATE and transaction_mode != MODE_CANDIDATE_ONLY:
			errors.append("%s:invalid_transaction_mode:%s" % [rule_id, transaction_mode])
			continue

		var effect_template_id := _optional_string(rule.get("effect_template_id"))
		if transaction_mode == MODE_EFFECT_TEMPLATE:
			if effect_template_id == "":
				errors.append("%s:missing_effect_template_id" % rule_id)
			elif not _effect_template_exists(effect_templates, effect_template_id):
				errors.append("%s:unknown_effect_template_id:%s" % [rule_id, effect_template_id])
		elif effect_template_id != "":
			errors.append("%s:candidate_only_has_effect_template_id:%s" % [rule_id, effect_template_id])
		else:
			warnings.append("%s:candidate_only_rule" % rule_id)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


func _effect_template_exists(effect_templates: Dictionary, effect_template_id: String) -> bool:
	if effect_templates.has(effect_template_id):
		return true

	for template: Variant in effect_templates.get("effect_templates", []):
		if template is Dictionary and str((template as Dictionary).get("effect_template_id", "")) == effect_template_id:
			return true

	return false


func _optional_string(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)
