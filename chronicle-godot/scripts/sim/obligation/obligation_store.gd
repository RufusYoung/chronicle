extends RefCounted
class_name V5ObligationStore

var obligations: Array = []


func add_obligation(obligation: Dictionary) -> void:
	obligations.append(obligation.duplicate(true))


func list_obligations() -> Array:
	return obligations.duplicate(true)


func list_obligations_by_owner(owner_id: String) -> Array:
	var rows: Array = []
	for obligation: Dictionary in obligations:
		if str(obligation.get("owner_id", "")) == owner_id:
			rows.append(obligation.duplicate(true))
	return rows


func list_obligations_by_target(target_id: String) -> Array:
	var rows: Array = []
	for obligation: Dictionary in obligations:
		if str(obligation.get("target_id", "")) == target_id:
			rows.append(obligation.duplicate(true))
	return rows


func find_open_obligations() -> Array:
	var rows: Array = []
	for obligation: Dictionary in obligations:
		if str(obligation.get("status", "open")) == "open":
			rows.append(obligation.duplicate(true))
	return rows


func find_obligation(obligation_id: String) -> Dictionary:
	for obligation: Dictionary in obligations:
		if str(obligation.get("obligation_id", "")) == obligation_id:
			return obligation.duplicate(true)
	return {}


func apply_obligation_update(update: Dictionary) -> bool:
	var obligation_id := str(update.get("obligation_id", ""))
	if obligation_id == "":
		return false

	for index: int in range(obligations.size()):
		var obligation: Dictionary = obligations[index]
		if str(obligation.get("obligation_id", "")) != obligation_id:
			continue

		var updated := obligation.duplicate(true)
		for key: String in update.keys():
			updated[key] = update[key]
		obligations[index] = updated
		return true

	return false


func mark_fulfilled(obligation_id: String, reason: String = "") -> bool:
	return apply_obligation_update({
		"obligation_id": obligation_id,
		"status": "fulfilled",
		"reason": reason,
	})


func mark_breached(obligation_id: String, reason: String = "") -> bool:
	return apply_obligation_update({
		"obligation_id": obligation_id,
		"status": "breached",
		"reason": reason,
	})
