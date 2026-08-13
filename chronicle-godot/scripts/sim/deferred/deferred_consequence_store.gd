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


func find_pending_by_trigger_and_scope(
	trigger_key: String,
	scope_type: String,
	scope_id: String
) -> Array:
	var rows: Array = []
	for consequence: Dictionary in deferred_consequences:
		if str(consequence.get("status", "pending")) != "pending":
			continue
		if str(consequence.get("trigger_key", "")) != trigger_key:
			continue
		if not _scope_matches(consequence, scope_type, scope_id):
			continue
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


func to_save_data() -> Array:
	return list_deferred_consequences()


func load_save_data(data: Variant) -> Dictionary:
	deferred_consequences.clear()
	var errors: Array[String] = []
	var seen_ids: Dictionary = {}
	if not data is Array:
		return {"ok": false, "errors": ["save_deferred_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_deferred_not_dictionary")
			continue
		var consequence := value as Dictionary
		var deferred_id := str(consequence.get("deferred_id", ""))
		if deferred_id == "" or seen_ids.has(deferred_id):
			errors.append("invalid_or_duplicate_deferred_id:%s" % deferred_id)
			continue
		seen_ids[deferred_id] = true
		add_deferred_consequence(consequence)
	return {"ok": errors.is_empty(), "errors": errors}


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


func _scope_matches(consequence: Dictionary, scope_type: String, scope_id: String) -> bool:
	if scope_type == "global":
		return true
	return (
		str(consequence.get("scope_type", "")) == scope_type
		and str(consequence.get("scope_id", "")) == scope_id
	)
