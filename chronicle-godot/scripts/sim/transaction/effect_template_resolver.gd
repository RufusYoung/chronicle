extends RefCounted
class_name V5EffectTemplateResolver

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")

var templates: Dictionary = {}


func load_effect_templates(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open effect templates: %s" % path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Effect template file must contain a JSON object: %s" % path)
		return

	var template_rows: Array = (parsed as Dictionary).get("effect_templates", [])
	for template: Variant in template_rows:
		if not template is Dictionary:
			continue
		var template_id := str((template as Dictionary).get("effect_template_id", ""))
		if template_id == "":
			continue
		templates[template_id] = (template as Dictionary).duplicate(true)


func get_template(template_id: String) -> Dictionary:
	if not templates.has(template_id):
		return {}
	return (templates[template_id] as Dictionary).duplicate(true)


func resolve_template(template_id: String, candidate: Variant, snapshot: Variant) -> Variant:
	var bindings := _build_bindings(candidate, snapshot)
	return resolve_template_with_bindings(template_id, bindings, snapshot)


func resolve_template_with_bindings(
	template_id: String,
	bindings: Dictionary,
	snapshot: Variant = null
) -> Variant:
	var result = TransactionResultModel.new()
	var template := get_template(template_id)
	if template.is_empty():
		return result

	var resolved_bindings := _normalize_bindings(bindings, snapshot)

	for fact_template: Dictionary in template.get("facts", []):
		var fact := _resolve_dictionary(fact_template, resolved_bindings)
		if _valid_fact(fact):
			result.add_fact(_normalize_fact(fact, resolved_bindings))

	for state_template: Dictionary in template.get("state_changes", []):
		var state_change := _resolve_dictionary(state_template, resolved_bindings)
		state_change = _normalize_state_change(state_change)
		if _valid_state_change(state_change):
			result.add_state_change(state_change)

	for relationship_template: Dictionary in template.get("relationship_changes", []):
		var relationship_change := _resolve_dictionary(relationship_template, resolved_bindings)
		if _valid_relationship_change(relationship_change):
			result.add_relationship_change(relationship_change)

	for memory_template: Dictionary in template.get("memories", []):
		var memory := _resolve_dictionary(memory_template, resolved_bindings)
		if _valid_memory(memory):
			result.add_memory(memory)

	for trace_template: Dictionary in template.get("traces", []):
		var trace := _resolve_dictionary(trace_template, resolved_bindings)
		if _valid_trace(trace):
			result.add_trace(trace)

	for rumor_template: Dictionary in template.get("rumors", []):
		var rumor := _resolve_dictionary(rumor_template, resolved_bindings)
		if _valid_rumor(rumor):
			result.add_rumor_seed(rumor)

	for pressure_template: Dictionary in template.get("pressure_changes", []):
		var pressure_change := _resolve_dictionary(pressure_template, resolved_bindings)
		if _valid_pressure_change(pressure_change):
			result.add_pressure_change(pressure_change)

	for obligation_template: Dictionary in template.get("obligations", []):
		var obligation := _resolve_dictionary(obligation_template, resolved_bindings)
		if _valid_obligation(obligation):
			result.add_obligation(obligation)

	for exchange_template: Dictionary in template.get("exchanges", []):
		var exchange := _resolve_dictionary(exchange_template, resolved_bindings)
		if _valid_exchange(exchange):
			result.add_exchange(exchange)

	for deferred_template: Dictionary in template.get("deferred_consequences", []):
		var consequence := _resolve_dictionary(deferred_template, resolved_bindings)
		if _valid_deferred_consequence(consequence):
			result.add_deferred_consequence(consequence)

	for obligation_update_template: Dictionary in template.get("obligation_updates", []):
		var obligation_update := _resolve_dictionary(obligation_update_template, resolved_bindings)
		if _valid_obligation_update(obligation_update):
			result.add_obligation_update(obligation_update)

	for exchange_update_template: Dictionary in template.get("exchange_updates", []):
		var exchange_update := _resolve_dictionary(exchange_update_template, resolved_bindings)
		if _valid_exchange_update(exchange_update):
			result.add_exchange_update(exchange_update)

	for deferred_update_template: Dictionary in template.get("deferred_consequence_updates", []):
		var deferred_update := _resolve_dictionary(deferred_update_template, resolved_bindings)
		if _valid_deferred_consequence_update(deferred_update):
			result.add_deferred_consequence_update(deferred_update)

	var narrative := _resolve_dictionary(template.get("narrative", {}), resolved_bindings)
	if not narrative.is_empty():
		result.set_narrative_result(_build_narrative_result(narrative, result, template_id))

	return result


func _build_bindings(candidate: Variant, snapshot: Variant) -> Dictionary:
	var actor_id := _player_id(snapshot)
	var target_id := str(candidate.target_id)
	var target_entity := _get_entity(snapshot, target_id)
	var target_display_name := str(target_entity.get("display_name", ""))
	if target_display_name == "":
		target_display_name = str(candidate.target_display_name)
	if target_display_name == "":
		target_display_name = target_id

	var superior_id := _candidate_extra_value(candidate, "superior_id")
	if superior_id == "":
		superior_id = _find_visible_entity_id_by_tags(snapshot, ["captain", "superior"])
	var superior_entity := _get_entity(snapshot, superior_id)
	var superior_display_name := str(superior_entity.get("display_name", ""))
	if superior_display_name == "":
		superior_display_name = superior_id

	return {
		"actor_id": actor_id,
		"target_id": target_id,
		"target_display_name": target_display_name,
		"action_id": str(candidate.action_id),
		"rule_id": str(candidate.rule_id),
		"fixture_id": _fixture_id(snapshot),
		"location_id": _location_id(snapshot),
		"superior_id": superior_id,
		"superior_display_name": superior_display_name,
		"obligation_id": _candidate_extra_value(candidate, "obligation_id"),
		"exchange_id": _candidate_extra_value(candidate, "exchange_id"),
		"deferred_id": _candidate_extra_value(candidate, "deferred_id"),
		"trigger_key": _candidate_extra_value(candidate, "trigger_key"),
	}


func _normalize_bindings(bindings: Dictionary, snapshot: Variant = null) -> Dictionary:
	var normalized := bindings.duplicate(true)
	if str(normalized.get("actor_id", "")) == "":
		normalized["actor_id"] = _player_id(snapshot)
	if str(normalized.get("target_id", "")) == "":
		normalized["target_id"] = ""
	if str(normalized.get("location_id", "")) == "":
		normalized["location_id"] = _location_id(snapshot)
	if str(normalized.get("rule_id", "")) == "":
		normalized["rule_id"] = ""
	if str(normalized.get("obligation_id", "")) == "":
		normalized["obligation_id"] = ""
	if str(normalized.get("exchange_id", "")) == "":
		normalized["exchange_id"] = ""
	if str(normalized.get("deferred_id", "")) == "":
		normalized["deferred_id"] = ""
	if str(normalized.get("trigger_key", "")) == "":
		normalized["trigger_key"] = ""
	if str(normalized.get("fixture_id", "")) == "":
		normalized["fixture_id"] = _fixture_id(snapshot)
	if str(normalized.get("target_kind", "")) == "":
		normalized["target_kind"] = ""
	if str(normalized.get("resolution", "")) == "":
		normalized["resolution"] = ""
	if str(normalized.get("resolution_id", "")) == "":
		normalized["resolution_id"] = ""
	if str(normalized.get("resolution_reason", "")) == "":
		normalized["resolution_reason"] = ""
	if str(normalized.get("resolved_by", "")) == "":
		normalized["resolved_by"] = ""
	if str(normalized.get("resolved_tick_event_id", "")) == "":
		normalized["resolved_tick_event_id"] = ""
	if str(normalized.get("tick_event_id", "")) == "":
		normalized["tick_event_id"] = ""
	if str(normalized.get("scope_type", "")) == "":
		normalized["scope_type"] = ""
	if str(normalized.get("scope_id", "")) == "":
		normalized["scope_id"] = ""
	return normalized


func _resolve_dictionary(source: Dictionary, bindings: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}
	for key: String in source.keys():
		resolved[key] = _resolve_value(source[key], bindings)
	return resolved


func _resolve_array(source: Array, bindings: Dictionary) -> Array:
	var resolved: Array = []
	for value: Variant in source:
		resolved.append(_resolve_value(value, bindings))
	return resolved


func _resolve_value(value: Variant, bindings: Dictionary) -> Variant:
	if value is Dictionary:
		return _resolve_dictionary(value, bindings)
	if value is Array:
		return _resolve_array(value, bindings)
	if value is String:
		var text := str(value)
		for binding_key: String in bindings.keys():
			text = text.replace("{%s}" % binding_key, str(bindings[binding_key]))
		return text
	return value


func _normalize_fact(fact: Dictionary, bindings: Dictionary) -> Dictionary:
	var normalized := fact.duplicate(true)
	if str(normalized.get("fact_id", "")) == "":
		normalized["fact_id"] = "%s:%s" % [
			str(normalized.get("fact_type", "")),
			str(normalized.get("target_id", "")),
		]
	if str(normalized.get("actor_id", "")) == "":
		normalized["actor_id"] = str(bindings.get("actor_id", "player"))
	if str(normalized.get("rule_id", "")) == "":
		normalized["rule_id"] = str(bindings.get("rule_id", ""))
	if str(normalized.get("fixture_id", "")) == "":
		normalized["fixture_id"] = str(bindings.get("fixture_id", ""))
	if str(normalized.get("location_id", "")) == "":
		normalized["location_id"] = str(bindings.get("location_id", ""))
	return normalized


func _normalize_state_change(change: Dictionary) -> Dictionary:
	var normalized := change.duplicate(true)
	var operation := str(normalized.get("operation", ""))
	if operation == "decrease_tier" and not normalized.has("degrade"):
		normalized["degrade"] = int(normalized.get("steps", 1))
	return normalized


func _build_narrative_result(narrative: Dictionary, result: Variant, template_id: String) -> Dictionary:
	var fact_types := _fact_types(result)
	var memory_types := _memory_types(result)
	return {
		"effect_template_id": template_id,
		"title": str(narrative.get("title", "")),
		"summary": str(narrative.get("summary", narrative.get("body", ""))),
		"body": str(narrative.get("body", narrative.get("summary", ""))),
		"tone": str(narrative.get("tone", "neutral")),
		"fact_types": fact_types,
		"memory_types": memory_types,
		"state_change_count": result.state_changes.size(),
		"relationship_change_count": result.relationship_changes.size(),
		"memory_count": result.memories_added.size(),
		"trace_count": result.traces_added.size(),
		"rumor_seed_count": result.rumors_added.size(),
		"pressure_change_count": result.pressure_changes.size(),
		"obligation_count": result.obligations_added.size(),
		"exchange_count": result.exchanges_added.size(),
		"deferred_consequence_count": result.deferred_consequences_added.size(),
		"obligation_update_count": result.obligation_updates.size(),
		"exchange_update_count": result.exchange_updates.size(),
		"deferred_consequence_update_count": result.deferred_consequence_updates.size(),
	}


func _fact_types(result: Variant) -> Array:
	var rows: Array = []
	for fact: Dictionary in result.facts_added:
		var fact_type := str(fact.get("fact_type", ""))
		if fact_type != "" and not (fact_type in rows):
			rows.append(fact_type)
	return rows


func _memory_types(result: Variant) -> Array:
	var rows: Array = []
	for memory: Dictionary in result.memories_added:
		var memory_type := str(memory.get("memory_type", ""))
		if memory_type != "" and not (memory_type in rows):
			rows.append(memory_type)
	return rows


func _valid_fact(fact: Dictionary) -> bool:
	return str(fact.get("fact_type", "")) != ""


func _valid_state_change(change: Dictionary) -> bool:
	return str(change.get("entity_id", "")) != "" and str(change.get("key", "")) != ""


func _valid_relationship_change(change: Dictionary) -> bool:
	return (
		str(change.get("source_id", "")) != ""
		and str(change.get("target_id", "")) != ""
		and str(change.get("axis", "")) != ""
	)


func _valid_memory(memory: Dictionary) -> bool:
	return str(memory.get("owner_id", "")) != "" and str(memory.get("memory_type", "")) != ""


func _valid_trace(trace: Dictionary) -> bool:
	return str(trace.get("trace_id", "")) != "" and str(trace.get("trace_type", "")) != ""


func _valid_rumor(rumor: Dictionary) -> bool:
	return str(rumor.get("rumor_id", "")) != ""


func _valid_pressure_change(change: Dictionary) -> bool:
	return str(change.get("scope_id", "")) != "" and str(change.get("pressure_type", "")) != ""


func _valid_obligation(obligation: Dictionary) -> bool:
	return str(obligation.get("owner_id", "")) != "" and str(obligation.get("obligation_type", "")) != ""


func _valid_exchange(exchange: Dictionary) -> bool:
	return str(exchange.get("party_a", "")) != "" and str(exchange.get("party_b", "")) != ""


func _valid_deferred_consequence(consequence: Dictionary) -> bool:
	return str(consequence.get("trigger_key", "")) != ""


func _valid_obligation_update(update: Dictionary) -> bool:
	return (
		str(update.get("obligation_id", "")) != ""
		and (
			str(update.get("status", "")) != ""
			or str(update.get("due_status", "")) != ""
			or str(update.get("resolution_status", "")) != ""
		)
	)


func _valid_exchange_update(update: Dictionary) -> bool:
	return (
		str(update.get("exchange_id", "")) != ""
		and (
			str(update.get("status", "")) != ""
			or str(update.get("due_status", "")) != ""
			or str(update.get("resolution_status", "")) != ""
		)
	)


func _valid_deferred_consequence_update(update: Dictionary) -> bool:
	return str(update.get("deferred_id", "")) != "" and str(update.get("status", "")) != ""


func _player_id(snapshot: Variant) -> String:
	if snapshot != null and snapshot.has_method("get_player_value"):
		return str(snapshot.get_player_value("id", "player"))
	return "player"


func _fixture_id(snapshot: Variant) -> String:
	var value: Variant = snapshot.get("fixture_id") if snapshot != null else null
	return str(value) if value != null else ""


func _location_id(snapshot: Variant) -> String:
	var direct_value: Variant = snapshot.get("location_id") if snapshot != null else null
	if direct_value != null and str(direct_value) != "":
		return str(direct_value)

	var location: Dictionary = snapshot.get("location") if snapshot != null else {}
	return str(location.get("id", ""))


func _get_entity(snapshot: Variant, entity_id: String) -> Dictionary:
	if entity_id == "" or snapshot == null:
		return {}
	if snapshot.has_method("get_entity"):
		return snapshot.get_entity(entity_id)
	if snapshot.has_method("get_entity_by_id"):
		return snapshot.get_entity_by_id(entity_id)
	return {}


func _visible_entities(snapshot: Variant) -> Array:
	if snapshot != null and snapshot.has_method("get_visible_entities"):
		return snapshot.get_visible_entities()
	return []


func _find_visible_entity_id_by_tags(snapshot: Variant, tags: Array) -> String:
	for entity: Dictionary in _visible_entities(snapshot):
		if str(entity.get("type", "")) != "person":
			continue
		var entity_tags: Array = entity.get("tags", [])
		var matches_any := false
		for tag: String in tags:
			if tag in entity_tags:
				matches_any = true
				break
		if matches_any:
			return str(entity.get("id", ""))
	return ""


func _candidate_extra_value(candidate: Variant, key: String) -> String:
	if candidate == null:
		return ""
	var extra: Variant = candidate.get("extra")
	if extra is Dictionary:
		return str((extra as Dictionary).get(key, ""))
	return ""
