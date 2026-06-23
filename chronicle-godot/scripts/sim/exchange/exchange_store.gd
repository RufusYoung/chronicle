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
