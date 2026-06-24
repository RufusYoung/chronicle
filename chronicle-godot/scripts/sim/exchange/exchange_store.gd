extends RefCounted
class_name V5ExchangeStore

var exchanges: Array = []


func add_exchange(exchange: Dictionary) -> void:
	exchanges.append(exchange.duplicate(true))


func list_exchanges() -> Array:
	return exchanges.duplicate(true)


func list_exchanges_by_actor(actor_id: String) -> Array:
	var rows: Array = []
	for exchange: Dictionary in exchanges:
		if (
			str(exchange.get("party_a", "")) == actor_id
			or str(exchange.get("party_b", "")) == actor_id
		):
			rows.append(exchange.duplicate(true))
	return rows


func find_open_exchanges() -> Array:
	var rows: Array = []
	for exchange: Dictionary in exchanges:
		if str(exchange.get("status", "open")) == "open":
			rows.append(exchange.duplicate(true))
	return rows


func find_open_due_by_deadline_and_scope(
	deadline_key: String,
	scope_type: String,
	scope_id: String
) -> Array:
	var rows: Array = []
	for exchange: Dictionary in exchanges:
		if str(exchange.get("status", "open")) != "open":
			continue
		if str(exchange.get("deadline_key", "")) != deadline_key:
			continue
		if not _scope_matches(exchange, scope_type, scope_id):
			continue
		if _already_due_for_trigger(exchange, deadline_key):
			continue
		rows.append(exchange.duplicate(true))
	return rows


func find_exchange(exchange_id: String) -> Dictionary:
	for exchange: Dictionary in exchanges:
		if str(exchange.get("exchange_id", "")) == exchange_id:
			return exchange.duplicate(true)
	return {}


func apply_exchange_update(update: Dictionary) -> bool:
	var exchange_id := str(update.get("exchange_id", ""))
	if exchange_id == "":
		return false

	for index: int in range(exchanges.size()):
		var exchange: Dictionary = exchanges[index]
		if str(exchange.get("exchange_id", "")) != exchange_id:
			continue

		var updated := exchange.duplicate(true)
		_apply_update_fields(updated, update)
		exchanges[index] = updated
		return true

	return false


func mark_settled(exchange_id: String, reason: String = "") -> bool:
	return apply_exchange_update({
		"exchange_id": exchange_id,
		"status": "settled",
		"reason": reason,
	})


func mark_failed(exchange_id: String, reason: String = "") -> bool:
	return apply_exchange_update({
		"exchange_id": exchange_id,
		"status": "failed",
		"reason": reason,
	})


func mark_due(exchange_id: String, tick_event: Dictionary) -> bool:
	return apply_exchange_update({
		"exchange_id": exchange_id,
		"due_status": "due",
		"last_due_tick_event_id": str(tick_event.get("tick_event_id", "")),
		"last_due_trigger_key": str(tick_event.get("trigger_key", "")),
		"due_count_delta": 1,
		"reason": "mark_due",
	})


func _apply_update_fields(target: Dictionary, update: Dictionary) -> void:
	var due_count_delta := int(update.get("due_count_delta", 0))
	for key: String in update.keys():
		if key == "due_count_delta":
			continue
		target[key] = update[key]
	if due_count_delta != 0:
		target["due_count"] = int(target.get("due_count", 0)) + due_count_delta


func _already_due_for_trigger(exchange: Dictionary, trigger_key: String) -> bool:
	return (
		str(exchange.get("due_status", "not_due")) == "due"
		and str(exchange.get("last_due_trigger_key", "")) == trigger_key
	)


func _scope_matches(exchange: Dictionary, scope_type: String, scope_id: String) -> bool:
	if scope_type == "global":
		return true
	return (
		str(exchange.get("scope_type", "")) == scope_type
		and str(exchange.get("scope_id", "")) == scope_id
	)
