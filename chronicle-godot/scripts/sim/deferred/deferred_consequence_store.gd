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


func find_deferred_consequence(deferred_id: String) -> Dictionary:
	for consequence: Dictionary in deferred_consequences:
		if str(consequence.get("deferred_id", "")) == deferred_id:
			return consequence.duplicate(true)
	return {}


func apply_deferred_consequence_update(update: Dictionary) -> bool:
	var deferred_id := str(update.get("deferred_id", ""))
	if deferred_id == "":
		return false

	for index: int in range(deferred_consequences.size()):
		var consequence: Dictionary = deferred_consequences[index]
		if str(consequence.get("deferred_id", "")) != deferred_id:
			continue

		var updated := consequence.duplicate(true)
		for key: String in update.keys():
			updated[key] = update[key]
		deferred_consequences[index] = updated
		return true

	return false


func mark_triggered(deferred_id: String, reason: String = "") -> bool:
	return apply_deferred_consequence_update({
		"deferred_id": deferred_id,
		"status": "triggered",
		"reason": reason,
	})


func mark_resolved(deferred_id: String, reason: String = "") -> bool:
	return apply_deferred_consequence_update({
		"deferred_id": deferred_id,
		"status": "resolved",
		"reason": reason,
	})
