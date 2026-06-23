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
		for key: String in update.keys():
			updated[key] = update[key]
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
