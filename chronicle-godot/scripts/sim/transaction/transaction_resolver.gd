extends RefCounted
class_name V5TransactionResolver

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const NarrativeSurfaceAdapterModel = preload("res://scripts/sim/narrative/narrative_surface_adapter.gd")


func resolve_action(candidate: Variant, context: Variant) -> Variant:
	var result = TransactionResultModel.new()
	var fact_type := _fact_type_for_rule(str(candidate.rule_id))
	if fact_type == "":
		return result

	result.add_fact(_build_fact(fact_type, candidate, context))
	_add_effects(result, fact_type, candidate, context)
	var narrative_adapter = NarrativeSurfaceAdapterModel.new()
	result.set_narrative_result(narrative_adapter.build_transaction_summary(result, context))
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


func _add_effects(result: Variant, fact_type: String, candidate: Variant, context: Variant) -> void:
	match fact_type:
		"actor_gave_food_to_target":
			_add_give_food_effects(result, candidate, context, fact_type)
		"actor_reported_discipline_violation":
			_add_report_discipline_effects(result, candidate, context, fact_type)
		"actor_concealed_discipline_violation":
			_add_conceal_discipline_effects(result, candidate, context, fact_type)
		"actor_read_object":
			result.add_memory(_build_memory(
				"player_remembers_read_object:%s" % str(candidate.target_id),
				str(context.get_player_value("id", "player")),
				fact_type,
				"remembers_read_object",
				"attention",
				false
			))
		"actor_inspected_trace":
			result.add_memory(_build_memory(
				"player_remembers_inspected_trace:%s" % str(candidate.target_id),
				str(context.get_player_value("id", "player")),
				fact_type,
				"remembers_inspected_trace",
				"attention",
				false
			))


func _add_give_food_effects(result: Variant, candidate: Variant, context: Variant, fact_type: String) -> void:
	var target_id := str(candidate.target_id)
	var actor_id := str(context.get_player_value("id", "player"))
	var from_hunger := str(_target_state(context, target_id, "hunger", "high"))
	var to_hunger := _degrade_scale(from_hunger)
	var from_food_count := int(context.get_player_value("food_count", 0))

	result.add_state_change({
		"entity_id": target_id,
		"key": "hunger",
		"from": from_hunger,
		"to": to_hunger,
		"reason": str(candidate.rule_id),
	})
	result.add_state_change({
		"entity_id": actor_id,
		"key": "food_count",
		"from": from_food_count,
		"to": max(from_food_count - 1, 0),
		"reason": str(candidate.rule_id),
	})
	result.add_relationship_change(_relationship_delta(target_id, actor_id, "gratitude", 15, candidate))
	result.add_relationship_change(_relationship_delta(target_id, actor_id, "trust", 5, candidate))
	result.add_relationship_change(_relationship_delta(target_id, actor_id, "fear", -5, candidate))
	result.add_memory(_build_memory(
		"%s_received_food_from_%s" % [target_id, actor_id],
		target_id,
		fact_type,
		"received_help",
		"gratitude",
		true
	))


func _add_report_discipline_effects(
	result: Variant,
	candidate: Variant,
	context: Variant,
	fact_type: String
) -> void:
	var target_id := str(candidate.target_id)
	var actor_id := str(context.get_player_value("id", "player"))
	var superior_id := _find_visible_entity_id_by_tags(context, ["captain", "superior"])

	result.add_relationship_change(_relationship_delta(target_id, actor_id, "resentment", 25, candidate))
	result.add_relationship_change(_relationship_delta(target_id, actor_id, "trust", -20, candidate))
	if superior_id != "":
		result.add_relationship_change(
			_relationship_delta(superior_id, actor_id, "discipline_respect", 15, candidate)
		)
		result.add_memory(_build_memory(
			"%s_remembers_discipline_report_from_%s" % [superior_id, actor_id],
			superior_id,
			fact_type,
			"discipline_report",
			"approval",
			true
		))

	result.add_trace({
		"trace_id": "ration_record_marked_for_review",
		"trace_type": "institutional_record_mark",
		"location_id": str(context.location_id),
		"source_fact_type": fact_type,
		"display_name": "被折起的口粮记录",
		"visible": true,
		"inspectable": true,
		"freshness": "fresh",
	})
	result.add_rumor_seed({
		"rumor_id": "outpost_discipline_report_seed",
		"source_fact_type": fact_type,
		"origin_location": str(context.location_id),
		"truth_level": "high",
		"distortion_level": "low",
		"spread_scope": "squad",
		"text_hint": "有人说，玩家把私藏口粮的事报告给了罗恩。",
	})
	result.add_memory(_build_memory(
		"%s_remembers_being_reported_by_%s" % [target_id, actor_id],
		target_id,
		fact_type,
		"being_reported",
		"resentment",
		true
	))


func _add_conceal_discipline_effects(
	result: Variant,
	candidate: Variant,
	context: Variant,
	fact_type: String
) -> void:
	var target_id := str(candidate.target_id)
	var actor_id := str(context.get_player_value("id", "player"))

	result.add_relationship_change(_relationship_delta(target_id, actor_id, "trust", 15, candidate))
	result.add_relationship_change(_relationship_delta(target_id, actor_id, "gratitude", 15, candidate))
	result.add_relationship_change(_relationship_delta(target_id, actor_id, "debt", 10, candidate))
	result.add_memory(_build_memory(
		"%s_remembers_being_protected_by_%s" % [target_id, actor_id],
		target_id,
		fact_type,
		"being_protected",
		"gratitude",
		true
	))


func _relationship_delta(
	source_id: String,
	target_id: String,
	axis: String,
	delta: int,
	candidate: Variant
) -> Dictionary:
	return {
		"source_id": source_id,
		"target_id": target_id,
		"axis": axis,
		"delta": delta,
		"reason": str(candidate.rule_id),
	}


func _build_memory(
	memory_id: String,
	owner_id: String,
	source_fact_type: String,
	memory_type: String,
	emotional_tone: String,
	can_be_told_as_rumor: bool
) -> Dictionary:
	return {
		"memory_id": memory_id,
		"owner_id": owner_id,
		"source_fact_type": source_fact_type,
		"memory_type": memory_type,
		"emotional_tone": emotional_tone,
		"clarity": "high",
		"can_be_told_as_rumor": can_be_told_as_rumor,
	}


func _target_state(context: Variant, target_id: String, key: String, default_value: Variant = null) -> Variant:
	var entity: Dictionary = context.get_entity_by_id(target_id)
	var states: Dictionary = entity.get("states", {})
	return states.get(key, default_value)


func _degrade_scale(value: String) -> String:
	var scale := ["extreme", "high", "medium", "low", "none"]
	var index := scale.find(value)
	if index < 0:
		return value
	return scale[min(index + 1, scale.size() - 1)]


func _find_visible_entity_id_by_tags(context: Variant, tags: Array) -> String:
	for entity: Dictionary in context.get_visible_entities():
		var entity_tags: Array = entity.get("tags", [])
		var matches := true
		for tag: String in tags:
			if tag not in entity_tags:
				matches = false
				break
		if matches:
			return str(entity.get("id", ""))
	return ""
