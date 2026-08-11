extends RefCounted
class_name V5NpcDecisionSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_tick(
		snapshot: Variant,
		rules: Array,
		tick_event: Dictionary
) -> Dictionary:
	var evaluations: Array = []
	var candidates_by_actor: Dictionary = {}
	for rule_value: Variant in rules:
		if not (rule_value is Dictionary):
			continue
		var rule := rule_value as Dictionary
		for actor_id_value: Variant in _matching_actor_ids(rule, snapshot):
			var actor_id := str(actor_id_value)
			var evaluation := _evaluate_rule(rule, snapshot, actor_id)
			evaluations.append(evaluation)
			if not bool(evaluation.get("eligible", false)):
				continue
			if not candidates_by_actor.has(actor_id):
				candidates_by_actor[actor_id] = []
			(candidates_by_actor[actor_id] as Array).append(evaluation)

	var results: Array = []
	var decisions: Array = []
	var actor_ids: Array = candidates_by_actor.keys()
	actor_ids.sort()
	for actor_id_value: Variant in actor_ids:
		var actor_id := str(actor_id_value)
		var chosen := _choose_action(candidates_by_actor[actor_id])
		if chosen.is_empty():
			continue
		var rule: Dictionary = chosen.get("rule", {})
		var result: Variant = _build_result(rule, chosen, snapshot, tick_event)
		results.append(result)
		decisions.append(_decision_row(chosen, tick_event))

	return {
		"actor_count": actor_ids.size(),
		"decision_count": decisions.size(),
		"decisions": decisions,
		"evaluations": _public_evaluations(evaluations),
		"results": results,
	}


func _evaluate_rule(
		rule: Dictionary,
		snapshot: Variant,
		actor_id: String
) -> Dictionary:
	var rule_id := str(rule.get("rule_id", ""))
	var eligible := actor_id != "" and rule_id != ""
	var blocked_reason := ""
	var bindings := _build_bindings(rule, snapshot, actor_id)
	if eligible and snapshot.get_entity(actor_id).is_empty():
		eligible = false
		blocked_reason = "actor_not_found"

	var once_fact_type := str(rule.get("once_fact_type", ""))
	if (
		eligible
		and once_fact_type != ""
		and _has_fact_type(snapshot, once_fact_type, actor_id)
	):
		eligible = false
		blocked_reason = "already_performed"

	if eligible:
		for requirement_value: Variant in rule.get("requirements", []):
			if not (requirement_value is Dictionary):
				continue
			var requirement := _resolve_dictionary(
				requirement_value as Dictionary,
				bindings
			)
			if not _condition_matches(
				requirement,
				snapshot,
				actor_id
			):
				eligible = false
				blocked_reason = "requirements_not_met"
				break

	var score := int(rule.get("base_utility", 0))
	var matched_factors: Array = []
	for factor_value: Variant in rule.get("utility_factors", []):
		if not (factor_value is Dictionary):
			continue
		var factor := factor_value as Dictionary
		var condition := _resolve_dictionary(
			factor.get("condition", {}) as Dictionary,
			bindings
		)
		if not _condition_matches(condition, snapshot, actor_id):
			continue
		var weight := int(factor.get("weight", 0))
		score += weight
		matched_factors.append({
			"factor_id": str(factor.get("factor_id", "")),
			"label": str(_resolve_value(
				factor.get("label", ""),
				bindings
			)),
			"weight": weight,
		})

	var minimum_utility := int(rule.get("minimum_utility", 0))
	if eligible and score < minimum_utility:
		eligible = false
		blocked_reason = "below_minimum_utility"

	return {
		"actor_id": actor_id,
		"rule_id": rule_id,
		"score": score,
		"minimum_utility": minimum_utility,
		"priority": int(rule.get("priority", 0)),
		"eligible": eligible,
		"blocked_reason": blocked_reason,
		"matched_factors": matched_factors,
		"bindings": bindings,
		"rule": rule.duplicate(true),
	}


func _matching_actor_ids(rule: Dictionary, snapshot: Variant) -> Array:
	var explicit_actor_id := str(rule.get("actor_id", ""))
	if explicit_actor_id != "":
		return [explicit_actor_id]

	var rows: Array = []
	var actor_query: Dictionary = rule.get("actor", {})
	for entity: Dictionary in snapshot.get_entities():
		if _actor_matches(entity, actor_query, snapshot):
			rows.append(str(entity.get("id", "")))
	return rows


func _actor_matches(
		actor: Dictionary,
		query: Dictionary,
		snapshot: Variant
) -> bool:
	var actor_id := str(actor.get("id", ""))
	if actor_id == "":
		return false
	if query.has("type") and str(actor.get("type", "")) != str(query.get("type", "")):
		return false

	var tags: Array = actor.get("tags", [])
	for required_tag: Variant in query.get("tags_all", []):
		if not (required_tag in tags):
			return false
	var tags_any: Array = query.get("tags_any", [])
	if not tags_any.is_empty():
		var matched_any := false
		for accepted_tag: Variant in tags_any:
			if accepted_tag in tags:
				matched_any = true
				break
		if not matched_any:
			return false

	var state_equals: Dictionary = query.get("state_equals", {})
	for key_value: Variant in state_equals.keys():
		var state_key := str(key_value)
		if snapshot.get_entity_state(actor_id, state_key, null) != state_equals[key_value]:
			return false
	return true


func _build_bindings(
		rule: Dictionary,
		snapshot: Variant,
		actor_id: String
) -> Dictionary:
	var actor: Dictionary = snapshot.get_entity(actor_id)
	var bindings := {
		"actor_id": actor_id,
		"actor_display_name": str(actor.get("display_name", actor_id)),
		"location_id": str(actor.get("location_id", "")),
		"player_location_id": str(snapshot.location.get("id", "")),
	}
	var binding_specs: Dictionary = rule.get("bindings", {})
	for binding_key_value: Variant in binding_specs.keys():
		var binding_key := str(binding_key_value)
		var spec_value: Variant = binding_specs[binding_key_value]
		if not (spec_value is Dictionary):
			bindings[binding_key] = spec_value
			continue
		var spec := spec_value as Dictionary
		match str(spec.get("source", "literal")):
			"actor_state":
				bindings[binding_key] = snapshot.get_entity_state(
					actor_id,
					str(spec.get("key", "")),
					spec.get("default")
				)
			"actor_field":
				bindings[binding_key] = actor.get(
					str(spec.get("key", "")),
					spec.get("default")
				)
			"literal":
				bindings[binding_key] = spec.get("value")

	for binding_key_value: Variant in binding_specs.keys():
		var binding_key := str(binding_key_value)
		var spec_value: Variant = binding_specs[binding_key_value]
		if not (spec_value is Dictionary):
			continue
		var spec := spec_value as Dictionary
		if str(spec.get("source", "")) != "entity_display_name":
			continue
		var entity_id := str(_resolve_value(
			spec.get("entity_id", ""),
			bindings
		))
		bindings[binding_key] = str(
			snapshot.get_entity(entity_id).get("display_name", entity_id)
		)
	return bindings


func _choose_action(candidates: Array) -> Dictionary:
	var chosen: Dictionary = {}
	for candidate_value: Variant in candidates:
		if not (candidate_value is Dictionary):
			continue
		var candidate := candidate_value as Dictionary
		if chosen.is_empty() or _is_better_choice(candidate, chosen):
			chosen = candidate
	return chosen.duplicate(true)


func _is_better_choice(candidate: Dictionary, current: Dictionary) -> bool:
	var candidate_score := int(candidate.get("score", 0))
	var current_score := int(current.get("score", 0))
	if candidate_score != current_score:
		return candidate_score > current_score
	var candidate_priority := int(candidate.get("priority", 0))
	var current_priority := int(current.get("priority", 0))
	if candidate_priority != current_priority:
		return candidate_priority > current_priority
	return str(candidate.get("rule_id", "")) < str(current.get("rule_id", ""))


func _condition_matches(
		condition: Dictionary,
		snapshot: Variant,
		actor_id: String
) -> bool:
	if condition.is_empty():
		return true

	var source := str(condition.get("source", "entity_state"))
	var value: Variant = null
	match source:
		"entity_state":
			var entity_id := str(condition.get("entity_id", actor_id))
			value = snapshot.get_entity_state(
				entity_id,
				str(condition.get("key", "")),
				null
			)
		"region_state":
			value = snapshot.region_state.get(str(condition.get("key", "")))
		"institution":
			value = snapshot.institution.get(str(condition.get("key", "")))
		"relationship":
			value = snapshot.get_relation(
				str(condition.get("source_id", actor_id)),
				str(condition.get("target_id", "player")),
				str(condition.get("axis", "trust")),
				0
			)
		"fact":
			value = _has_fact_type(
				snapshot,
				str(condition.get("fact_type", "")),
				str(condition.get("actor_id", ""))
			)
		_:
			return false

	if condition.has("equals") and value != condition.get("equals"):
		return false
	if condition.has("not_equals") and value == condition.get("not_equals"):
		return false
	if condition.has("in"):
		var accepted_values: Variant = condition.get("in", [])
		if not (accepted_values is Array) or not (value in accepted_values):
			return false
	if condition.has("min") and float(value) < float(condition.get("min", 0)):
		return false
	if condition.has("max") and float(value) > float(condition.get("max", 0)):
		return false
	return true


func _has_fact_type(
		snapshot: Variant,
		fact_type: String,
		actor_id: String = ""
) -> bool:
	if fact_type == "":
		return false
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", fact.get("type", ""))) != fact_type:
			continue
		if actor_id == "" or str(fact.get("actor_id", "")) == actor_id:
			return true
	return false


func _build_result(
		rule: Dictionary,
		evaluation: Dictionary,
		snapshot: Variant,
		tick_event: Dictionary
) -> Variant:
	var result: Variant = TransactionResultModel.new()
	var bindings: Dictionary = (
		evaluation.get("bindings", {}) as Dictionary
	).duplicate(true)
	bindings["rule_id"] = str(evaluation.get("rule_id", ""))
	bindings["tick_event_id"] = str(tick_event.get("tick_event_id", ""))
	var observed_by_player: bool = bindings["location_id"] == str(
		snapshot.location.get("id", "")
	)
	result.add_fact({
		"fact_id": "npc_autonomous_action:%s:%s" % [
			bindings["actor_id"],
			bindings["tick_event_id"],
		],
		"fact_type": "npc_autonomous_action",
		"actor_id": bindings["actor_id"],
		"rule_id": bindings["rule_id"],
		"tick_event_id": bindings["tick_event_id"],
		"location_id": bindings["location_id"],
		"utility_score": int(evaluation.get("score", 0)),
		"matched_factors": (
			evaluation.get("matched_factors", []) as Array
		).duplicate(true),
		"observed_by_player": observed_by_player,
	})

	var effects: Dictionary = rule.get("effects", {})
	for fact_value: Variant in effects.get("facts", []):
		if fact_value is Dictionary:
			var fact := _resolve_dictionary(fact_value, bindings)
			if not fact.has("observed_by_player"):
				fact["observed_by_player"] = observed_by_player
			result.add_fact(fact)
	for change_value: Variant in effects.get("state_changes", []):
		if change_value is Dictionary:
			result.add_state_change(_resolve_dictionary(change_value, bindings))
	for change_value: Variant in effects.get("relationship_changes", []):
		if change_value is Dictionary:
			result.add_relationship_change(
				_resolve_dictionary(change_value, bindings)
			)
	for change_value: Variant in effects.get("pressure_changes", []):
		if change_value is Dictionary:
			result.add_pressure_change(_resolve_dictionary(change_value, bindings))

	var narrative: Dictionary = effects.get("narrative", {})
	if not narrative.is_empty():
		var resolved_narrative := _resolve_dictionary(narrative, bindings)
		resolved_narrative["decision_rule_id"] = bindings["rule_id"]
		resolved_narrative["utility_score"] = int(evaluation.get("score", 0))
		resolved_narrative["matched_factors"] = (
			evaluation.get("matched_factors", []) as Array
		).duplicate(true)
		result.set_narrative_result(resolved_narrative)
	result.mark_resolved("npc_autonomous_decision")
	return result


func _resolve_dictionary(source: Dictionary, bindings: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}
	for key_value: Variant in source.keys():
		resolved[key_value] = _resolve_value(source[key_value], bindings)
	return resolved


func _resolve_value(value: Variant, bindings: Dictionary) -> Variant:
	if value is String:
		var text := str(value)
		for binding_key: Variant in bindings.keys():
			text = text.replace(
				"{%s}" % str(binding_key),
				str(bindings[binding_key])
			)
		return text
	if value is Dictionary:
		return _resolve_dictionary(value as Dictionary, bindings)
	if value is Array:
		var resolved_array: Array = []
		for item: Variant in value:
			resolved_array.append(_resolve_value(item, bindings))
		return resolved_array
	return value


func _decision_row(
		evaluation: Dictionary,
		tick_event: Dictionary
) -> Dictionary:
	return {
		"actor_id": str(evaluation.get("actor_id", "")),
		"rule_id": str(evaluation.get("rule_id", "")),
		"utility_score": int(evaluation.get("score", 0)),
		"minimum_utility": int(evaluation.get("minimum_utility", 0)),
		"matched_factors": (
			evaluation.get("matched_factors", []) as Array
		).duplicate(true),
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"observed_by_player": str(
			(evaluation.get("bindings", {}) as Dictionary).get("location_id", "")
		) == str(
			(evaluation.get("bindings", {}) as Dictionary).get(
				"player_location_id",
				""
			)
		),
	}


func _public_evaluations(evaluations: Array) -> Array:
	var rows: Array = []
	for evaluation_value: Variant in evaluations:
		if not (evaluation_value is Dictionary):
			continue
		var evaluation := (evaluation_value as Dictionary).duplicate(true)
		evaluation.erase("rule")
		rows.append(evaluation)
	return rows
