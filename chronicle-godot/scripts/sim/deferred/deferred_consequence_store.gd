extends RefCounted
class_name V5DeferredConsequenceStore

var deferred_consequences: Array = []


func add_deferred_consequence(consequence: Dictionary) -> void:
	deferred_consequences.append(consequence.duplicate(true))


func list_deferred_consequences() -> Array:
	return deferred_consequences.duplicate(true)


func find_pending_consequences() -> Array:
	var rows: Array = []
	for consequence: Dictionary in deferred_consequences:
		if str(consequence.get("status", "pending")) == "pending":
			rows.append(consequence.duplicate(true))
	return rows


func find_by_trigger_key(trigger_key: String) -> Array:
	var rows: Array = []
	for consequence: Dictionary in deferred_consequences:
		if str(consequence.get("trigger_key", "")) == trigger_key:
			rows.append(consequence.duplicate(true))
	return rows
