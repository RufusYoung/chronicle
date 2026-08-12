extends RefCounted
class_name V5TransactionResolver

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")

const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"

var effect_template_resolver: Variant = null


func _init() -> void:
	effect_template_resolver = EffectTemplateResolverModel.new()
	effect_template_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)


func resolve_action(candidate: Variant, context_or_snapshot: Variant) -> Variant:
	if candidate == null:
		return TransactionResultModel.invalid_contract(candidate, "missing_candidate")
	if context_or_snapshot == null:
		return TransactionResultModel.invalid_contract(candidate, "missing_context")
	if not _candidate_bool(candidate, "can_execute", true):
		return TransactionResultModel.invalid_contract(candidate, "action_blocked")

	var transaction_mode := _candidate_transaction_mode(candidate)
	match transaction_mode:
		"effect_template":
			var template_id := _candidate_effect_template_id(candidate)
			if template_id == "":
				return TransactionResultModel.invalid_contract(candidate, "missing_effect_template_id")
			if effect_template_resolver.get_template(template_id).is_empty():
				return TransactionResultModel.invalid_contract(candidate, "unknown_effect_template_id:%s" % template_id)

			var result = effect_template_resolver.resolve_template(template_id, candidate, context_or_snapshot)
			result.mark_resolved(transaction_mode)
			return result
		"candidate_only":
			if _candidate_effect_template_id(candidate) != "":
				return TransactionResultModel.invalid_contract(candidate, "candidate_only_has_effect_template_id")
			return TransactionResultModel.empty_candidate_only(candidate)
		_:
			if transaction_mode == "":
				return TransactionResultModel.invalid_contract(candidate, "missing_transaction_mode")
			return TransactionResultModel.invalid_contract(candidate, "invalid_transaction_mode:%s" % transaction_mode)


func _candidate_transaction_mode(candidate: Variant) -> String:
	return _candidate_string(candidate, "transaction_mode")


func _candidate_effect_template_id(candidate: Variant) -> String:
	return _candidate_string(candidate, "effect_template_id")


func _candidate_bool(candidate: Variant, key: String, default_value: bool) -> bool:
	if candidate == null:
		return default_value
	if candidate is Dictionary:
		return bool((candidate as Dictionary).get(key, default_value))
	var value: Variant = candidate.get(key)
	return default_value if value == null else bool(value)


func _candidate_string(candidate: Variant, key: String) -> String:
	var value: Variant = null
	if candidate == null:
		return ""
	if candidate is Dictionary:
		value = (candidate as Dictionary).get(key)
	else:
		value = candidate.get(key)
	if value == null:
		return ""
	return str(value)
