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
			for entity: Dictionary in context.entities:
				if _context_matches_rule(context, rule) and _target_matches_rule(entity, rule.get("target", {})):
					candidates.append(_build_candidate(rule, entity))
		elif _context_matches_rule(context, rule):
			candidates.append(_build_candidate(rule, {}))

	candidates.sort_custom(func(left: Variant, right: Variant) -> bool:
		return left.priority < right.priority
	)
	return candidates


func _build_candidate(rule: Dictionary, target: Dictionary) -> Variant:
	var rule_id := str(rule.get("rule_id", ""))
	var target_id := str(target.get("id", ""))
	var target_display_name := str(target.get("display_name", target_id))
	var label := str(rule.get("label_template", rule_id))
	label = label.replace("{target_display_name}", target_display_name)

	return ActionCandidateModel.new({
		"action_id": _make_action_id(rule_id, target_id),
		"rule_id": rule_id,
		"action_type": str(rule.get("action_type", "")),
		"label": label,
		"target_id": target_id,
		"target_display_name": target_display_name,
		"priority": int(rule.get("priority", 0)),
		"domain": str(rule.get("domain", "")),
	})


func _make_action_id(rule_id: String, target_id: String) -> String:
	if target_id == "":
		return rule_id
	return "%s:%s" % [rule_id, target_id]


func _context_matches_rule(context: Variant, rule: Dictionary) -> bool:
	if not _tags_include_all(context.get_location_tags(), rule.get("location_tags_all", [])):
		return false
	if not _dictionary_matches(context.region_state, rule.get("region_state_equals", {})):
		return false
	if not _dictionary_matches(context.institution, rule.get("institution_equals", {})):
		return false
	if not _dictionary_matches(context.player, rule.get("player_equals", {})):
		return false
	if not _dictionary_min_matches(context.player, rule.get("player_min", {})):
		return false
	if not _has_visible_entity_with_tags(context, rule.get("required_visible_entity_tags", [])):
		return false
	if not _has_visible_entity_with_tags(context, rule.get("required_visible_object_tags", [])):
		return false
	return true


func _target_matches_rule(target: Dictionary, target_rule: Dictionary) -> bool:
	if target_rule.has("type") and str(target.get("type", "")) != str(target_rule.get("type", "")):
		return false

	var tags: Array = target.get("tags", [])
	if not _tags_include_all(tags, target_rule.get("tags_all", [])):
		return false
	if not _tags_include_any(tags, target_rule.get("tags_any", [])):
		return false

	var states: Dictionary = target.get("states", {})
	if not _dictionary_matches(states, target_rule.get("state_equals", {})):
		return false
	if not _dictionary_has_keys(states, target_rule.get("state_has", [])):
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
