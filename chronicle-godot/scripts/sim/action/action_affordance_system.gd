extends RefCounted
class_name V5ActionAffordanceSystem

const ActionCandidateModel = preload("res://scripts/sim/action/action_candidate.gd")


func build_candidates(context: Variant = null) -> Array:
	return generate_candidates(context, [])


func generate_candidates(context: Variant, rules: Array) -> Array:
	var candidates: Array = []
	if context == null:
		return candidates

	for rule: Dictionary in rules:
		if rule.has("target"):
			for entity: Dictionary in _candidate_targets(context, rule):
				if _context_matches_rule(context, rule) and _target_matches_rule(context, entity, rule.get("target", {}), rule):
					candidates.append(_build_candidate(context, rule, entity))
		elif _context_matches_rule(context, rule):
			candidates.append(_build_candidate(context, rule, {}))

	candidates.sort_custom(func(left: Variant, right: Variant) -> bool:
		return left.priority < right.priority
	)
	return candidates


func _build_candidate(context: Variant, rule: Dictionary, target: Dictionary) -> Variant:
	var rule_id := str(rule.get("rule_id", ""))
	var target_id := str(target.get("id", ""))
	var target_display_name := str(target.get("display_name", target_id))
	var label := str(rule.get("label_template", rule_id))
	label = label.replace("{target_display_name}", target_display_name)

	var candidate_data := {
		"action_id": _make_action_id(rule_id, target_id),
		"rule_id": rule_id,
		"action_type": str(rule.get("action_type", "")),
		"transaction_mode": _string_or_empty(rule.get("transaction_mode", "")),
		"effect_template_id": _string_or_empty(rule.get("effect_template_id", "")),
		"label": label,
		"target_id": target_id,
		"target_display_name": target_display_name,
		"priority": int(rule.get("priority", 0)),
		"domain": str(rule.get("domain", "")),
		"extra": {},
	}
	_apply_pressure_priority(context, rule, candidate_data)
	return ActionCandidateModel.new(candidate_data)


func _make_action_id(rule_id: String, target_id: String) -> String:
	if target_id == "":
		return rule_id
	return "%s:%s" % [rule_id, target_id]


func _string_or_empty(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)


func _context_matches_rule(context: Variant, rule: Dictionary) -> bool:
	if not _tags_include_all(context.get_location_tags(), rule.get("location_tags_all", [])):
		return false
	if not _dictionary_matches(_context_region_state(context), rule.get("region_state_equals", {})):
		return false
	if not _dictionary_matches(_context_institution(context), rule.get("institution_equals", {})):
		return false
	if not _dictionary_matches(_context_player(context), rule.get("player_equals", {})):
		return false
	if not _dictionary_min_matches(_context_player(context), rule.get("player_min", {})):
		return false
	if not _has_visible_entity_with_tags(context, rule.get("required_visible_entity_tags", [])):
		return false
	if not _has_visible_entity_with_tags(context, rule.get("required_visible_object_tags", [])):
		return false
	return true


func _target_matches_rule(context: Variant, target: Dictionary, target_rule: Dictionary, rule: Dictionary) -> bool:
	if target_rule.has("type") and str(target.get("type", "")) != str(target_rule.get("type", "")):
		return false

	var tags: Array = target.get("tags", [])
	if not _tags_include_all(tags, target_rule.get("tags_all", [])):
		return false
	if not _tags_include_any(tags, target_rule.get("tags_any", [])):
		return false

	if not _target_dictionary_matches(context, target, target_rule.get("state_equals", {})):
		return false
	if not _target_dictionary_in(context, target, target_rule.get("state_in", {})):
		return false
	if not _target_has_keys(context, target, target_rule.get("state_has", [])):
		return false
	if not _relationship_any_matches(context, target, rule.get("relationship_any", [])):
		return false

	return true


func _dictionary_matches(actual: Dictionary, expected: Dictionary) -> bool:
	for key: String in expected.keys():
		if not actual.has(key):
			return false
		if actual.get(key) != expected.get(key):
			return false
	return true


func _dictionary_min_matches(actual: Dictionary, expected: Dictionary) -> bool:
	for key: String in expected.keys():
		if float(actual.get(key, 0)) < float(expected.get(key, 0)):
			return false
	return true


func _dictionary_has_keys(actual: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if not actual.has(key):
			return false
	return true


func _tags_include_all(actual_tags: Array, expected_tags: Array) -> bool:
	for tag: String in expected_tags:
		if tag not in actual_tags:
			return false
	return true


func _tags_include_any(actual_tags: Array, expected_tags: Array) -> bool:
	if expected_tags.is_empty():
		return true
	for tag: String in expected_tags:
		if tag in actual_tags:
			return true
	return false


func _has_visible_entity_with_tags(context: Variant, expected_tags: Array) -> bool:
	if expected_tags.is_empty():
		return true

	for entity: Dictionary in context.get_visible_entities():
		if _tags_include_all(entity.get("tags", []), expected_tags):
			return true
	return false


func _candidate_targets(context: Variant, rule: Dictionary) -> Array:
	var targets: Array = []
	var seen_ids: Dictionary = {}
	for entity: Dictionary in _context_entities(context):
		_add_candidate_target(targets, seen_ids, entity)

	var target_rule: Dictionary = rule.get("target", {})
	var target_type := str(target_rule.get("type", ""))
	if target_type == "trace":
		for trace: Dictionary in _context_visible_traces(context):
			_add_candidate_target(targets, seen_ids, _trace_to_target(trace))
	elif target_type == "rumor_seed":
		for rumor: Dictionary in _context_rumor_seeds(context):
			_add_candidate_target(targets, seen_ids, _rumor_to_target(rumor))

	return targets


func _add_candidate_target(targets: Array, seen_ids: Dictionary, target: Dictionary) -> void:
	var target_id := str(target.get("id", ""))
	if target_id == "":
		return
	if seen_ids.has(target_id):
		return
	seen_ids[target_id] = true
	targets.append(target)


func _context_entities(context: Variant) -> Array:
	if context.has_method("get_entities"):
		return context.get_entities()
	return context.entities


func _context_region_state(context: Variant) -> Dictionary:
	return context.region_state


func _context_institution(context: Variant) -> Dictionary:
	return context.institution


func _context_player(context: Variant) -> Dictionary:
	return context.player


func _context_visible_traces(context: Variant) -> Array:
	if context.has_method("get_visible_traces"):
		return context.get_visible_traces()
	return []


func _context_rumor_seeds(context: Variant) -> Array:
	if context.has_method("get_rumor_seeds"):
		return context.get_rumor_seeds()
	return []


func _apply_pressure_priority(context: Variant, rule: Dictionary, candidate_data: Dictionary) -> void:
	var priority_rules: Array = rule.get("pressure_priority", [])
	if priority_rules.is_empty():
		return

	for priority_rule: Dictionary in priority_rules:
		var scope_id := _resolve_pressure_scope_id(context, str(priority_rule.get("scope_id", "")))
		var pressure_type := str(priority_rule.get("pressure_type", ""))
		var threshold := int(priority_rule.get("threshold", 0))
		var priority_delta := int(priority_rule.get("priority_delta", 0))
		if scope_id == "" or pressure_type == "":
			continue

		var pressure_value := _pressure_value(context, scope_id, pressure_type)
		if pressure_value < threshold:
			continue

		candidate_data["priority"] = int(candidate_data.get("priority", 0)) + priority_delta
		var extra: Dictionary = candidate_data.get("extra", {})
		extra["pressure_priority_applied"] = true
		extra["pressure_priority_scope_id"] = scope_id
		extra["pressure_priority_type"] = pressure_type
		extra["pressure_priority_value"] = pressure_value
		extra["pressure_priority_delta"] = priority_delta
		candidate_data["extra"] = extra
		return


func _resolve_pressure_scope_id(context: Variant, scope_id: String) -> String:
	if scope_id == "{location_id}":
		var location: Dictionary = context.location if context != null else {}
		return str(location.get("id", ""))
	return scope_id


func _pressure_value(context: Variant, scope_id: String, pressure_type: String) -> int:
	var total := 0
	for pressure: Dictionary in _context_pressures(context):
		if (
			str(pressure.get("scope_id", "")) == scope_id
			and str(pressure.get("pressure_type", "")) == pressure_type
		):
			total += int(pressure.get("value", 0))
	return total


func _context_pressures(context: Variant) -> Array:
	if context != null and context.has_method("get_pressures"):
		return context.get_pressures()
	if context != null:
		var value: Variant = context.get("pressures")
		if value is Array:
			return (value as Array).duplicate(true)
	return []


func _trace_to_target(trace: Dictionary) -> Dictionary:
	var trace_id := str(trace.get("id", trace.get("trace_id", "")))
	return {
		"id": trace_id,
		"display_name": str(trace.get("display_name", trace_id)),
		"type": "trace",
		"tags": _merge_tags(["trace"], trace.get("tags", [])),
		"states": {
			"visible": bool(trace.get("visible", true)),
			"inspectable": bool(trace.get("inspectable", true)),
			"trace_type": str(trace.get("trace_type", "")),
		},
	}


func _rumor_to_target(rumor: Dictionary) -> Dictionary:
	var rumor_id := str(rumor.get("id", rumor.get("rumor_id", "")))
	return {
		"id": rumor_id,
		"display_name": str(rumor.get("display_name", rumor.get("text_hint", rumor_id))),
		"type": "rumor_seed",
		"tags": _merge_tags(["rumor", "rumor_seed"], rumor.get("tags", [])),
		"states": {
			"visible": bool(rumor.get("visible", true)),
			"hearable": bool(rumor.get("hearable", true)),
			"spread_scope": str(rumor.get("spread_scope", "")),
		},
	}


func _merge_tags(base_tags: Array, extra_tags: Array) -> Array:
	var rows := base_tags.duplicate()
	for tag: Variant in extra_tags:
		if tag not in rows:
			rows.append(tag)
	return rows


func _target_dictionary_matches(context: Variant, target: Dictionary, expected: Dictionary) -> bool:
	for key: String in expected.keys():
		if _target_state(context, target, key, null) != expected.get(key):
			return false
	return true


func _target_dictionary_in(context: Variant, target: Dictionary, expected: Dictionary) -> bool:
	for key: String in expected.keys():
		var allowed_values: Array = expected.get(key, [])
		if _target_state(context, target, key, null) not in allowed_values:
			return false
	return true


func _target_has_keys(context: Variant, target: Dictionary, keys: Array) -> bool:
	for key: String in keys:
		if _target_state(context, target, key, null) == null:
			return false
	return true


func _target_state(context: Variant, target: Dictionary, key: String, default_value: Variant = null) -> Variant:
	var states: Dictionary = target.get("states", {})
	if states.has(key):
		return states.get(key)

	var target_id := str(target.get("id", ""))
	if target_id != "" and context.has_method("get_entity_state"):
		return context.get_entity_state(target_id, key, default_value)

	return default_value


func _relationship_any_matches(context: Variant, target: Dictionary, groups: Array) -> bool:
	if groups.is_empty():
		return true
	if not context.has_method("get_relation"):
		return false

	for group: Array in groups:
		var group_matches := true
		for condition: Dictionary in group:
			if not _relationship_condition_matches(context, target, condition):
				group_matches = false
				break
		if group_matches:
			return true
	return false


func _relationship_condition_matches(context: Variant, target: Dictionary, condition: Dictionary) -> bool:
	var source_id := _resolve_relationship_side(context, target, str(condition.get("source", "")))
	var target_id := _resolve_relationship_side(context, target, str(condition.get("target", "")))
	var axis := str(condition.get("axis", ""))
	if source_id == "" or target_id == "" or axis == "":
		return false

	var value := float(context.get_relation(source_id, target_id, axis, 0))
	if condition.has("min") and value < float(condition.get("min", 0)):
		return false
	if condition.has("max") and value > float(condition.get("max", 0)):
		return false
	return true


func _resolve_relationship_side(context: Variant, target: Dictionary, value: String) -> String:
	match value:
		"target":
			return str(target.get("id", ""))
		"player", "actor":
			return str(context.get_player_value("id", "player"))
		_:
			return value
