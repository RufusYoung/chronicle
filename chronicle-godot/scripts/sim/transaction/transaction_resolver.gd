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
	var empty_result = TransactionResultModel.new()
	if candidate == null or context_or_snapshot == null:
		return empty_result

	var template_id := _effect_template_for_rule(str(candidate.rule_id))
	if template_id == "":
		return empty_result

	return effect_template_resolver.resolve_template(template_id, candidate, context_or_snapshot)


func _effect_template_for_rule(rule_id: String) -> String:
	match rule_id:
		"give_food_to_hungry_person":
			return "give_food_help_effect"
		"ask_about_concealed_item":
			return "inquiry_concealed_item_effect"
		"report_discipline_violation_to_superior":
			return "discipline_report_effect"
		"conceal_discipline_violation_once":
			return "discipline_conceal_effect"
		"read_visible_readable_object":
			return "read_object_effect"
		"inspect_visible_trace":
			return "inspect_trace_effect"
		_:
			return ""
