extends RefCounted
class_name V5DueResolutionSystem

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
const DueResolutionPolicyModel = preload("res://scripts/sim/consequence/due_resolution_policy.gd")

const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const MODE_DUE_RESOLUTION := "due_resolution"
const DEFAULT_OBLIGATION_FULFILLED_TEMPLATE_ID := "obligation_fulfilled_effect"
const DEFAULT_OBLIGATION_BREACHED_TEMPLATE_ID := "obligation_breached_effect"
const DEFAULT_EXCHANGE_SETTLED_TEMPLATE_ID := "exchange_settled_effect"
const DEFAULT_EXCHANGE_FAILED_TEMPLATE_ID := "exchange_failed_effect"
const DEFAULT_KEEP_DUE_TEMPLATE_ID := "due_resolution_keep_due_effect"

var effect_template_resolver: Variant = null
var policy: Variant = null


func _init() -> void:
	effect_template_resolver = EffectTemplateResolverModel.new()
	effect_template_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	policy = DueResolutionPolicyModel.new()


func resolve_due(snapshot: Variant, decision: Dictionary) -> Variant:
	var validation: Dictionary = policy.validate(decision)
	if not bool(validation.get("ok", false)):
		return _invalid("invalid_decision:%s" % _first_error(validation.get("errors", [])))

	var normalized: Dictionary = validation.get("decision", {})
	var target_kind := str(normalized.get("target_kind", ""))
	var target_id := str(normalized.get("target_id", ""))
	var resolution := str(normalized.get("resolution", ""))
	var record := _find_target(snapshot, target_kind, target_id)

	if record.is_empty():
		return _invalid("target_not_found:%s:%s" % [target_kind, target_id])
	if str(record.get("status", "open")) != "open":
		return _invalid("target_not_open:%s:%s" % [target_kind, target_id])
	if str(record.get("due_status", "not_due")) != "due":
		return _invalid("target_not_due:%s:%s" % [target_kind, target_id])

	var template_id := _template_id(record, resolution, _default_template_id(target_kind, resolution))
	if template_id == "":
		return _invalid("missing_resolution_template:%s:%s" % [target_kind, resolution])

	var result = effect_template_resolver.resolve_template_with_bindings(
		template_id,
		_bindings(snapshot, normalized, record)
	)
	result.mark_resolved(MODE_DUE_RESOLUTION)
	return result


func resolve_many(snapshot: Variant, decisions: Array) -> Array:
	var results: Array = []
	for decision: Variant in decisions:
		if decision is Dictionary:
			results.append(resolve_due(snapshot, decision as Dictionary))
		else:
			results.append(_invalid("invalid_decision_type"))
	return results


func _invalid(reason: String) -> Variant:
	var result = TransactionResultModel.new()
	result.mark_invalid_contract(MODE_DUE_RESOLUTION, reason)
	return result


func _find_target(snapshot: Variant, target_kind: String, target_id: String) -> Dictionary:
	if target_kind == "obligation":
		return _find_obligation(snapshot, target_id)
	if target_kind == "exchange":
		return _find_exchange(snapshot, target_id)
	return {}


func _find_obligation(snapshot: Variant, obligation_id: String) -> Dictionary:
	for obligation: Dictionary in _obligations(snapshot):
		if str(obligation.get("obligation_id", "")) == obligation_id:
			return obligation.duplicate(true)
	return {}


func _find_exchange(snapshot: Variant, exchange_id: String) -> Dictionary:
	for exchange: Dictionary in _exchanges(snapshot):
		if str(exchange.get("exchange_id", "")) == exchange_id:
			return exchange.duplicate(true)
	return {}


func _obligations(snapshot: Variant) -> Array:
	if snapshot == null:
		return []
	var value: Variant = snapshot.get("obligations")
	return (value as Array).duplicate(true) if value is Array else []


func _exchanges(snapshot: Variant) -> Array:
	if snapshot == null:
		return []
	var value: Variant = snapshot.get("exchanges")
	return (value as Array).duplicate(true) if value is Array else []


func _default_template_id(target_kind: String, resolution: String) -> String:
	if target_kind == "obligation":
		match resolution:
			"fulfilled":
				return DEFAULT_OBLIGATION_FULFILLED_TEMPLATE_ID
			"breached":
				return DEFAULT_OBLIGATION_BREACHED_TEMPLATE_ID
			"keep_due":
				return DEFAULT_KEEP_DUE_TEMPLATE_ID
	if target_kind == "exchange":
		match resolution:
			"settled":
				return DEFAULT_EXCHANGE_SETTLED_TEMPLATE_ID
			"failed":
				return DEFAULT_EXCHANGE_FAILED_TEMPLATE_ID
			"keep_due":
				return DEFAULT_KEEP_DUE_TEMPLATE_ID
	return ""


func _template_id(record: Dictionary, resolution: String, default_template_id: String) -> String:
	var overrides: Variant = record.get("resolution_templates")
	if overrides is Dictionary:
		var override_value := str((overrides as Dictionary).get(resolution, ""))
		if override_value != "":
			return override_value
	return default_template_id


func _bindings(snapshot: Variant, decision: Dictionary, record: Dictionary) -> Dictionary:
	var target_kind := str(decision.get("target_kind", ""))
	var resolution := str(decision.get("resolution", ""))
	var target_record_id := str(decision.get("target_id", ""))
	var counterpart_id := _counterpart_id(snapshot, target_kind, record)
	return {
		"actor_id": _actor_id(snapshot, target_kind, record),
		"target_id": target_record_id if resolution == "keep_due" else counterpart_id,
		"location_id": _location_id(snapshot, record, decision),
		"rule_id": "due_resolution_system",
		"obligation_id": target_record_id if target_kind == "obligation" else "",
		"exchange_id": target_record_id if target_kind == "exchange" else "",
		"target_kind": target_kind,
		"resolution": resolution,
		"resolution_id": str(decision.get("resolution_id", "")),
		"resolution_reason": str(decision.get("reason", "")),
		"resolved_by": _resolved_by(decision),
		"resolved_tick_event_id": str(decision.get("tick_event_id", "")),
		"tick_event_id": str(decision.get("tick_event_id", "")),
		"trigger_key": _trigger_key(record, decision),
		"scope_type": _scope_type(record, decision),
		"scope_id": _scope_id(record, decision),
	}


func _actor_id(snapshot: Variant, target_kind: String, record: Dictionary) -> String:
	if target_kind == "obligation":
		return str(record.get("owner_id", _player_id(snapshot)))
	if target_kind == "exchange":
		return str(record.get("party_a", _player_id(snapshot)))
	return _player_id(snapshot)


func _counterpart_id(snapshot: Variant, target_kind: String, record: Dictionary) -> String:
	if target_kind == "obligation":
		return str(record.get("target_id", ""))
	if target_kind == "exchange":
		return str(record.get("party_b", ""))
	return _player_id(snapshot)


func _resolved_by(decision: Dictionary) -> String:
	var resolver_actor_id := str(decision.get("resolver_actor_id", ""))
	if resolver_actor_id != "":
		return resolver_actor_id
	var source := str(decision.get("source", ""))
	return "system" if source == "" else source


func _trigger_key(record: Dictionary, decision: Dictionary) -> String:
	var decision_value := str(decision.get("trigger_key", ""))
	return decision_value if decision_value != "" else str(record.get("last_due_trigger_key", record.get("deadline_key", "")))


func _scope_type(record: Dictionary, decision: Dictionary) -> String:
	var decision_value := str(decision.get("scope_type", ""))
	if decision_value != "":
		return decision_value
	var record_value := str(record.get("scope_type", ""))
	if record_value != "":
		return record_value
	return "location" if str(record.get("location_id", "")) != "" else ""


func _scope_id(record: Dictionary, decision: Dictionary) -> String:
	var decision_value := str(decision.get("scope_id", ""))
	if decision_value != "":
		return decision_value
	var record_value := str(record.get("scope_id", ""))
	if record_value != "":
		return record_value
	return str(record.get("location_id", ""))


func _location_id(snapshot: Variant, record: Dictionary, decision: Dictionary) -> String:
	var record_location_id := str(record.get("location_id", ""))
	if record_location_id != "":
		return record_location_id
	if _scope_type(record, decision) == "location":
		return _scope_id(record, decision)
	if snapshot == null:
		return ""

	var direct_value: Variant = snapshot.get("location_id")
	if direct_value != null and str(direct_value) != "":
		return str(direct_value)

	var location: Dictionary = snapshot.get("location") if snapshot.get("location") is Dictionary else {}
	return str(location.get("id", ""))


func _player_id(snapshot: Variant) -> String:
	if snapshot != null and snapshot.has_method("get_player_value"):
		return str(snapshot.get_player_value("id", "player"))
	return "player"


func _first_error(errors: Variant) -> String:
	if errors is Array and not (errors as Array).is_empty():
		return str((errors as Array)[0])
	return "invalid_resolution"
