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


func find_open_due_by_deadline_and_scope(
	deadline_key: String,
	scope_type: String,
	scope_id: String
) -> Array:
	var rows: Array = []
	for obligation: Dictionary in obligations:
		if str(obligation.get("status", "open")) != "open":
			continue
		if str(obligation.get("deadline_key", "")) != deadline_key:
			continue
		if not _scope_matches(obligation, scope_type, scope_id):
			continue
		if _already_due_for_trigger(obligation, deadline_key):
			continue
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
		_apply_update_fields(updated, update)
		obligations[index] = updated
		return true

	return false


func to_save_data() -> Array:
	return list_obligations()


func load_save_data(data: Variant) -> Dictionary:
	obligations.clear()
	var errors: Array[String] = []
	var seen_ids: Dictionary = {}
	if not data is Array:
		return {"ok": false, "errors": ["save_obligations_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_obligation_not_dictionary")
			continue
		var obligation := value as Dictionary
		var obligation_id := str(obligation.get("obligation_id", ""))
		if obligation_id == "" or seen_ids.has(obligation_id):
			errors.append("invalid_or_duplicate_obligation_id:%s" % obligation_id)
			continue
		seen_ids[obligation_id] = true
		add_obligation(obligation)
	return {"ok": errors.is_empty(), "errors": errors}


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


func mark_due(obligation_id: String, tick_event: Dictionary) -> bool:
	return apply_obligation_update({
		"obligation_id": obligation_id,
		"due_status": "due",
		"last_due_tick_event_id": str(tick_event.get("tick_event_id", "")),
		"last_due_trigger_key": str(tick_event.get("trigger_key", "")),
		"due_count_delta": 1,
		"reason": "mark_due",
	})


func _apply_update_fields(target: Dictionary, update: Dictionary) -> void:
	var due_count_delta := int(update.get("due_count_delta", 0))
	var resolution_count_delta := int(update.get("resolution_count_delta", 0))
	for key: String in update.keys():
		if key == "due_count_delta" or key == "resolution_count_delta":
			continue
		target[key] = update[key]
	if due_count_delta != 0:
		target["due_count"] = int(target.get("due_count", 0)) + due_count_delta
	if resolution_count_delta != 0:
		target["resolution_count"] = int(target.get("resolution_count", 0)) + resolution_count_delta


func _already_due_for_trigger(obligation: Dictionary, trigger_key: String) -> bool:
	return (
		str(obligation.get("due_status", "not_due")) == "due"
		and str(obligation.get("last_due_trigger_key", "")) == trigger_key
	)


func _scope_matches(obligation: Dictionary, scope_type: String, scope_id: String) -> bool:
	if scope_type == "global":
		return true
	return (
		str(obligation.get("scope_type", "")) == scope_type
		and str(obligation.get("scope_id", "")) == scope_id
	)
