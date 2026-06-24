extends RefCounted
class_name V5DueTriggerSystem

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")

const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const MODE_DUE_TRIGGER := "due_trigger"
const DEFAULT_OBLIGATION_DUE_TEMPLATE_ID := "obligation_due_effect"
const DEFAULT_EXCHANGE_DUE_TEMPLATE_ID := "exchange_due_effect"

var effect_template_resolver: Variant = null


func _init() -> void:
	effect_template_resolver = EffectTemplateResolverModel.new()
	effect_template_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)


func find_due_obligations(snapshot: Variant, tick_event: Dictionary) -> Array:
	var rows: Array = []
	var trigger_key := str(tick_event.get("trigger_key", ""))
	var scope_type := str(tick_event.get("scope_type", ""))
	var scope_id := str(tick_event.get("scope_id", ""))

	for obligation: Dictionary in _open_obligations(snapshot):
		if str(obligation.get("deadline_key", "")) != trigger_key:
			continue
		if not _scope_matches(obligation, scope_type, scope_id):
			continue
		if _already_due_for_trigger(obligation, trigger_key):
			continue
		rows.append(obligation.duplicate(true))
	return rows


func find_due_exchanges(snapshot: Variant, tick_event: Dictionary) -> Array:
	var rows: Array = []
	var trigger_key := str(tick_event.get("trigger_key", ""))
	var scope_type := str(tick_event.get("scope_type", ""))
	var scope_id := str(tick_event.get("scope_id", ""))

	for exchange: Dictionary in _open_exchanges(snapshot):
		if str(exchange.get("deadline_key", "")) != trigger_key:
			continue
		if not _scope_matches(exchange, scope_type, scope_id):
			continue
		if _already_due_for_trigger(exchange, trigger_key):
			continue
		rows.append(exchange.duplicate(true))
	return rows


func trigger_obligation_due(snapshot: Variant, obligation_id: String, tick_event: Dictionary) -> Variant:
	var obligation := _find_obligation(snapshot, obligation_id)
	if obligation.is_empty():
		return _invalid("missing_obligation:%s" % obligation_id)
	if str(obligation.get("status", "open")) != "open":
		return _invalid("obligation_not_open:%s" % obligation_id)

	var trigger_key := str(tick_event.get("trigger_key", ""))
	if str(obligation.get("deadline_key", "")) != trigger_key:
		return _invalid("obligation_deadline_mismatch:%s" % obligation_id)
	if not _scope_matches(
		obligation,
		str(tick_event.get("scope_type", "")),
		str(tick_event.get("scope_id", ""))
	):
		return _invalid("obligation_scope_mismatch:%s" % obligation_id)
	if _already_due_for_trigger(obligation, trigger_key):
		return _invalid("obligation_already_due:%s" % obligation_id)

	var template_id := _template_id(
		obligation,
		"due_template_id",
		DEFAULT_OBLIGATION_DUE_TEMPLATE_ID
	)
	return _resolve(template_id, _obligation_bindings(snapshot, obligation, tick_event))


func trigger_exchange_due(snapshot: Variant, exchange_id: String, tick_event: Dictionary) -> Variant:
	var exchange := _find_exchange(snapshot, exchange_id)
	if exchange.is_empty():
		return _invalid("missing_exchange:%s" % exchange_id)
	if str(exchange.get("status", "open")) != "open":
		return _invalid("exchange_not_open:%s" % exchange_id)

	var trigger_key := str(tick_event.get("trigger_key", ""))
	if str(exchange.get("deadline_key", "")) != trigger_key:
		return _invalid("exchange_deadline_mismatch:%s" % exchange_id)
	if not _scope_matches(
		exchange,
		str(tick_event.get("scope_type", "")),
		str(tick_event.get("scope_id", ""))
	):
		return _invalid("exchange_scope_mismatch:%s" % exchange_id)
	if _already_due_for_trigger(exchange, trigger_key):
		return _invalid("exchange_already_due:%s" % exchange_id)

	var template_id := _template_id(
		exchange,
		"due_template_id",
		DEFAULT_EXCHANGE_DUE_TEMPLATE_ID
	)
	return _resolve(template_id, _exchange_bindings(snapshot, exchange, tick_event))


func trigger_due_for_tick(snapshot: Variant, tick_event: Dictionary) -> Dictionary:
	var obligation_results: Array = []
	var exchange_results: Array = []

	if _has_due_kind(tick_event, "obligation"):
		for obligation: Dictionary in find_due_obligations(snapshot, tick_event):
			var obligation_id := str(obligation.get("obligation_id", ""))
			if obligation_id == "":
				continue
			obligation_results.append(trigger_obligation_due(snapshot, obligation_id, tick_event))

	if _has_due_kind(tick_event, "exchange"):
		for exchange: Dictionary in find_due_exchanges(snapshot, tick_event):
			var exchange_id := str(exchange.get("exchange_id", ""))
			if exchange_id == "":
				continue
			exchange_results.append(trigger_exchange_due(snapshot, exchange_id, tick_event))

	return {
		"obligation_results": obligation_results,
		"exchange_results": exchange_results,
		"obligation_due_count": obligation_results.size(),
		"exchange_due_count": exchange_results.size(),
	}


func _resolve(template_id: String, bindings: Dictionary) -> Variant:
	var result = effect_template_resolver.resolve_template_with_bindings(template_id, bindings)
	result.mark_resolved(MODE_DUE_TRIGGER)
	return result


func _invalid(reason: String) -> Variant:
	var result = TransactionResultModel.new()
	result.mark_invalid_contract(MODE_DUE_TRIGGER, reason)
	return result


func _obligation_bindings(
	snapshot: Variant,
	obligation: Dictionary,
	tick_event: Dictionary
) -> Dictionary:
	return _base_bindings(snapshot, obligation, tick_event, {
		"actor_id": str(obligation.get("owner_id", _player_id(snapshot))),
		"target_id": str(obligation.get("target_id", "")),
		"obligation_id": str(obligation.get("obligation_id", "")),
	})


func _exchange_bindings(snapshot: Variant, exchange: Dictionary, tick_event: Dictionary) -> Dictionary:
	return _base_bindings(snapshot, exchange, tick_event, {
		"actor_id": str(exchange.get("party_a", _player_id(snapshot))),
		"target_id": str(exchange.get("party_b", "")),
		"exchange_id": str(exchange.get("exchange_id", "")),
	})


func _base_bindings(
	snapshot: Variant,
	record: Dictionary,
	tick_event: Dictionary,
	values: Dictionary
) -> Dictionary:
	var record_scope_type := _record_scope_type(record, tick_event)
	var record_scope_id := _record_scope_id(record, tick_event)
	var bindings := {
		"actor_id": _player_id(snapshot),
		"target_id": "",
		"location_id": _location_id(snapshot, record, tick_event),
		"rule_id": "due_trigger_system",
		"obligation_id": "",
		"exchange_id": "",
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"trigger_key": str(tick_event.get("trigger_key", "")),
		"scope_type": record_scope_type,
		"scope_id": record_scope_id,
	}
	for key: String in values.keys():
		bindings[key] = values[key]
	return bindings


func _template_id(record: Dictionary, key: String, default_template_id: String) -> String:
	var value := str(record.get(key, ""))
	return default_template_id if value == "" else value


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


func _open_obligations(snapshot: Variant) -> Array:
	if snapshot != null and snapshot.has_method("get_open_obligations"):
		return snapshot.get_open_obligations()

	var rows: Array = []
	for obligation: Dictionary in _obligations(snapshot):
		if str(obligation.get("status", "open")) == "open":
			rows.append(obligation.duplicate(true))
	return rows


func _open_exchanges(snapshot: Variant) -> Array:
	if snapshot != null and snapshot.has_method("get_open_exchanges"):
		return snapshot.get_open_exchanges()

	var rows: Array = []
	for exchange: Dictionary in _exchanges(snapshot):
		if str(exchange.get("status", "open")) == "open":
			rows.append(exchange.duplicate(true))
	return rows


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


func _has_due_kind(tick_event: Dictionary, kind: String) -> bool:
	var due_kinds: Variant = tick_event.get("due_kinds", ["obligation", "exchange"])
	if not due_kinds is Array:
		return kind in ["obligation", "exchange"]
	return kind in (due_kinds as Array)


func _already_due_for_trigger(record: Dictionary, trigger_key: String) -> bool:
	return (
		str(record.get("due_status", "not_due")) == "due"
		and str(record.get("last_due_trigger_key", "")) == trigger_key
	)


func _scope_matches(record: Dictionary, scope_type: String, scope_id: String) -> bool:
	if scope_type == "global":
		return true
	return (
		_record_scope_type(record, {}) == scope_type
		and _record_scope_id(record, {}) == scope_id
	)


func _record_scope_type(record: Dictionary, tick_event: Dictionary) -> String:
	var scope_type := str(record.get("scope_type", ""))
	if scope_type != "":
		return scope_type
	if str(record.get("location_id", "")) != "":
		return "location"
	return str(tick_event.get("scope_type", ""))


func _record_scope_id(record: Dictionary, tick_event: Dictionary) -> String:
	var scope_id := str(record.get("scope_id", ""))
	if scope_id != "":
		return scope_id
	var location_id := str(record.get("location_id", ""))
	if location_id != "":
		return location_id
	return str(tick_event.get("scope_id", ""))


func _location_id(snapshot: Variant, record: Dictionary, tick_event: Dictionary) -> String:
	var record_location_id := str(record.get("location_id", ""))
	if record_location_id != "":
		return record_location_id
	if _record_scope_type(record, tick_event) == "location":
		return _record_scope_id(record, tick_event)
	if str(tick_event.get("scope_type", "")) == "location":
		return str(tick_event.get("scope_id", ""))
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
