extends RefCounted
class_name V5TransactionResolver

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")


func resolve_action(candidate: Variant, context: Variant) -> Variant:
	var result = TransactionResultModel.new()
	var fact_type := _fact_type_for_rule(str(candidate.rule_id))
	if fact_type == "":
		return result

	result.add_fact(_build_fact(fact_type, candidate, context))
	return result


func _fact_type_for_rule(rule_id: String) -> String:
	match rule_id:
		"give_food_to_hungry_person":
			return "actor_gave_food_to_target"
		"read_visible_readable_object":
			return "actor_read_object"
		"inspect_visible_trace":
			return "actor_inspected_trace"
		"report_discipline_violation_to_superior":
			return "actor_reported_discipline_violation"
		"conceal_discipline_violation_once":
			return "actor_concealed_discipline_violation"
		_:
			return ""


func _build_fact(fact_type: String, candidate: Variant, context: Variant) -> Dictionary:
	return {
		"fact_id": "%s:%s" % [fact_type, str(candidate.target_id)],
		"fact_type": fact_type,
		"actor_id": str(context.get_player_value("id", "player")),
		"target_id": str(candidate.target_id),
		"target_display_name": str(candidate.target_display_name),
		"action_id": str(candidate.action_id),
		"rule_id": str(candidate.rule_id),
		"fixture_id": str(context.fixture_id),
		"location_id": str(context.location_id),
	}
