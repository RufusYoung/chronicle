extends RefCounted
class_name V5ConsequenceTriggerSystem

const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")

const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const MODE_CONSEQUENCE_TRIGGER := "consequence_trigger"
const DEFAULT_FULFILL_TEMPLATE_ID := "obligation_fulfilled_effect"
const DEFAULT_BREACH_TEMPLATE_ID := "obligation_breached_effect"
const DEFAULT_SETTLE_TEMPLATE_ID := "exchange_settled_effect"
const DEFAULT_TRIGGER_TEMPLATE_ID := "deferred_consequence_triggered_effect"

var effect_template_resolver: Variant = null


func _init() -> void:
	effect_template_resolver = EffectTemplateResolverModel.new()
	effect_template_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)


func fulfill_obligation(snapshot: Variant, obligation_id: String) -> Variant:
	var obligation := _find_obligation(snapshot, obligation_id)
	if obligation.is_empty():
		return _invalid("missing_obligation:%s" % obligation_id)
	if str(obligation.get("status", "open")) != "open":
		return _invalid("obligation_not_open:%s" % obligation_id)

	var template_id := _template_id(
		obligation,
		"fulfill_template_id",
		DEFAULT_FULFILL_TEMPLATE_ID
	)
	return _resolve(template_id, _obligation_bindings(snapshot, obligation))


func breach_obligation(snapshot: Variant, obligation_id: String) -> Variant:
	var obligation := _find_obligation(snapshot, obligation_id)
	if obligation.is_empty():
		return _invalid("missing_obligation:%s" % obligation_id)
	if str(obligation.get("status", "open")) != "open":
		return _invalid("obligation_not_open:%s" % obligation_id)

	var template_id := _template_id(
		obligation,
		"breach_template_id",
		DEFAULT_BREACH_TEMPLATE_ID
	)
	return _resolve(template_id, _obligation_bindings(snapshot, obligation))


func settle_exchange(snapshot: Variant, exchange_id: String) -> Variant:
	var exchange := _find_exchange(snapshot, exchange_id)
	if exchange.is_empty():
		return _invalid("missing_exchange:%s" % exchange_id)
	if str(exchange.get("status", "open")) != "open":
		return _invalid("exchange_not_open:%s" % exchange_id)

	var template_id := _template_id(
		exchange,
		"settle_template_id",
		DEFAULT_SETTLE_TEMPLATE_ID
	)
	return _resolve(template_id, _exchange_bindings(snapshot, exchange))


func trigger_deferred_by_key(snapshot: Variant, trigger_key: String) -> Array:
	var results: Array = []
	for consequence: Dictionary in _deferred_consequences(snapshot):
		if str(consequence.get("trigger_key", "")) != trigger_key:
			continue
		if str(consequence.get("status", "pending")) != "pending":
			continue
		results.append(trigger_deferred(snapshot, str(consequence.get("deferred_id", ""))))
	return results


func trigger_deferred(snapshot: Variant, deferred_id: String) -> Variant:
	var consequence := _find_deferred_consequence(snapshot, deferred_id)
	if consequence.is_empty():
		return _invalid("missing_deferred_consequence:%s" % deferred_id)
	if str(consequence.get("status", "pending")) != "pending":
		return _invalid("deferred_consequence_not_pending:%s" % deferred_id)

	var template_id := _template_id(
		consequence,
		"trigger_template_id",
		DEFAULT_TRIGGER_TEMPLATE_ID
	)
	return _resolve(template_id, _deferred_bindings(snapshot, consequence))


func _resolve(template_id: String, bindings: Dictionary) -> Variant:
	var result = effect_template_resolver.resolve_template_with_bindings(template_id, bindings)
	result.mark_resolved(MODE_CONSEQUENCE_TRIGGER)
	return result


func _invalid(reason: String) -> Variant:
	var result = TransactionResultModel.new()
	result.mark_invalid_contract(MODE_CONSEQUENCE_TRIGGER, reason)
	return result


func _obligation_bindings(snapshot: Variant, obligation: Dictionary) -> Dictionary:
	return _base_bindings(snapshot, {
		"actor_id": str(obligation.get("owner_id", _player_id(snapshot))),
		"target_id": str(obligation.get("target_id", "")),
		"obligation_id": str(obligation.get("obligation_id", "")),
	})


func _exchange_bindings(snapshot: Variant, exchange: Dictionary) -> Dictionary:
	return _base_bindings(snapshot, {
		"actor_id": str(exchange.get("party_a", _player_id(snapshot))),
		"target_id": str(exchange.get("party_b", "")),
		"exchange_id": str(exchange.get("exchange_id", "")),
	})


func _deferred_bindings(snapshot: Variant, consequence: Dictionary) -> Dictionary:
	var bindings := _base_bindings(snapshot, {
		"actor_id": str(consequence.get("source_actor_id", _player_id(snapshot))),
		"target_id": str(consequence.get("target_id", "")),
		"deferred_id": str(consequence.get("deferred_id", "")),
		"trigger_key": str(consequence.get("trigger_key", "")),
		"location_id": str(consequence.get("location_id", _location_id(snapshot))),
	})
	for key: String in consequence.keys():
		if not bindings.has(key):
			bindings[key] = consequence[key]
	return bindings


func _base_bindings(snapshot: Variant, values: Dictionary) -> Dictionary:
	var bindings := {
		"actor_id": _player_id(snapshot),
		"target_id": "",
		"location_id": _location_id(snapshot),
		"rule_id": "consequence_trigger_system",
		"obligation_id": "",
		"exchange_id": "",
		"deferred_id": "",
		"trigger_key": "",
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


func _find_deferred_consequence(snapshot: Variant, deferred_id: String) -> Dictionary:
	for consequence: Dictionary in _deferred_consequences(snapshot):
		if str(consequence.get("deferred_id", "")) == deferred_id:
			return consequence.duplicate(true)
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


func _deferred_consequences(snapshot: Variant) -> Array:
	if snapshot == null:
		return []
	var value: Variant = snapshot.get("deferred_consequences")
	return (value as Array).duplicate(true) if value is Array else []


func _player_id(snapshot: Variant) -> String:
	if snapshot != null and snapshot.has_method("get_player_value"):
		return str(snapshot.get_player_value("id", "player"))
	return "player"


func _location_id(snapshot: Variant) -> String:
	if snapshot == null:
		return ""
	var direct_value: Variant = snapshot.get("location_id")
	if direct_value != null and str(direct_value) != "":
		return str(direct_value)

	var location: Dictionary = snapshot.get("location") if snapshot.get("location") is Dictionary else {}
	return str(location.get("id", ""))
