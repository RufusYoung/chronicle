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
