extends RefCounted
class_name V5SimWorldLog

var entries: Array = []


func append_entry(entry: Dictionary) -> void:
	entries.append(entry.duplicate(true))


func list_entries() -> Array:
	return entries.duplicate(true)


func to_save_data() -> Array:
	return list_entries()


func load_save_data(data: Variant) -> Dictionary:
	clear()
	if not data is Array:
		return {"ok": false, "errors": ["save_world_log_not_array"]}
	var errors: Array[String] = []
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_world_log_entry_not_dictionary")
			continue
		append_entry(value)
	return {"ok": errors.is_empty(), "errors": errors}


func find_entries_by_fact_type(fact_type: String) -> Array:
	var rows: Array = []
	for entry: Dictionary in entries:
		var fact_types: Array = entry.get("facts_added", [])
		if fact_type in fact_types:
			rows.append(entry.duplicate(true))
	return rows


func find_entries_by_rule_id(rule_id: String) -> Array:
	var rows: Array = []
	for entry: Dictionary in entries:
		if str(entry.get("rule_id", "")) == rule_id:
			rows.append(entry.duplicate(true))
	return rows


func find_entries_by_tick_event_id(tick_event_id: String) -> Array:
	var rows: Array = []
	for entry: Dictionary in entries:
		if str(entry.get("entry_type", "")) != "tick_event":
			continue
		if str(entry.get("tick_event_id", "")) == tick_event_id:
			rows.append(entry.duplicate(true))
	return rows


func find_tick_entries_by_scope(scope_type: String, scope_id: String) -> Array:
	var rows: Array = []
	for entry: Dictionary in entries:
		if str(entry.get("entry_type", "")) != "tick_event":
			continue
		if str(entry.get("scope_type", "")) != scope_type:
			continue
		if scope_type != "global" and str(entry.get("scope_id", "")) != scope_id:
			continue
		rows.append(entry.duplicate(true))
	return rows


func summary() -> Dictionary:
	var fact_types: Array = []
	var rule_ids: Array = []
	var state_change_count := 0
	var relationship_change_count := 0
	var memory_count := 0
	var trace_count := 0
	var rumor_seed_count := 0
	var pressure_change_count := 0
	var obligation_count := 0
	var exchange_count := 0
	var deferred_consequence_count := 0
	var obligation_update_count := 0
	var exchange_update_count := 0
	var deferred_consequence_update_count := 0
	var item_change_count := 0
	var equipment_change_count := 0
	var chronicle_entry_count := 0
	var investigation_change_count := 0
	var tick_event_count := 0
	var scoped_tick_event_count := 0
	var failed_tick_event_count := 0
	var triggered_deferred_count := 0
	var skipped_deferred_count := 0
	var obligation_due_count := 0
	var exchange_due_count := 0
	var due_result_count := 0
	var autonomous_decision_count := 0
	var observed_autonomous_decision_count := 0
	var due_resolution_count := 0
	var obligation_fulfilled_count := 0
	var obligation_breached_count := 0
	var exchange_settled_count := 0
	var exchange_failed_count := 0
	var keep_due_count := 0
	var resolved_count := 0
	var candidate_only_count := 0
	var invalid_contract_count := 0

	for entry: Dictionary in entries:
		var entry_rule_id := str(entry.get("rule_id", ""))
		if entry_rule_id != "" and not (entry_rule_id in rule_ids):
			rule_ids.append(entry_rule_id)

		for fact_type: Variant in entry.get("facts_added", []):
			var fact_type_text := str(fact_type)
			if fact_type_text != "" and not (fact_type_text in fact_types):
				fact_types.append(fact_type_text)

		state_change_count += int(entry.get("state_change_count", 0))
		relationship_change_count += int(entry.get("relationship_change_count", 0))
		memory_count += int(entry.get("memory_count", 0))
		trace_count += int(entry.get("trace_count", 0))
		rumor_seed_count += int(entry.get("rumor_seed_count", 0))
		pressure_change_count += int(entry.get("pressure_change_count", 0))
		obligation_count += int(entry.get("obligation_count", 0))
		exchange_count += int(entry.get("exchange_count", 0))
		deferred_consequence_count += int(entry.get("deferred_consequence_count", 0))
		obligation_update_count += int(entry.get("obligation_update_count", 0))
		exchange_update_count += int(entry.get("exchange_update_count", 0))
		deferred_consequence_update_count += int(entry.get("deferred_consequence_update_count", 0))
		item_change_count += int(entry.get("item_change_count", 0))
		equipment_change_count += int(entry.get("equipment_change_count", 0))
		chronicle_entry_count += int(
			entry.get("chronicle_entry_count", 0)
		)
		investigation_change_count += int(
			entry.get("investigation_change_count", 0)
		)
		if str(entry.get("entry_type", "")) == "tick_event":
			tick_event_count += 1
			if str(entry.get("scope_type", "")) != "":
				scoped_tick_event_count += 1
			if str(entry.get("error_reason", "")) != "":
				failed_tick_event_count += 1
			if entry.has("triggered_count"):
				triggered_deferred_count += int(entry.get("triggered_count", 0))
			else:
				triggered_deferred_count += int(entry.get("deferred_consequence_update_count", 0))
			skipped_deferred_count += int(entry.get("skipped_count", 0))
			obligation_due_count += int(entry.get("obligation_due_count", 0))
			exchange_due_count += int(entry.get("exchange_due_count", 0))
			due_result_count += int(entry.get("due_result_count", 0))
			autonomous_decision_count += int(
				entry.get("autonomous_decision_count", 0)
			)
			observed_autonomous_decision_count += int(
				entry.get("observed_autonomous_decision_count", 0)
			)
		if str(entry.get("entry_type", "")) == "due_resolution":
			due_resolution_count += 1
			var resolution := str(entry.get("resolution", entry.get("resolution_status", "")))
			var target_kind := str(entry.get("target_kind", ""))
			if resolution == "keep_due":
				keep_due_count += 1
			elif target_kind == "obligation" and resolution == "fulfilled":
				obligation_fulfilled_count += 1
			elif target_kind == "obligation" and resolution == "breached":
				obligation_breached_count += 1
			elif target_kind == "exchange" and resolution == "settled":
				exchange_settled_count += 1
			elif target_kind == "exchange" and resolution == "failed":
				exchange_failed_count += 1

		match str(entry.get("contract_status", "")):
			"resolved":
				resolved_count += 1
			"candidate_only":
				candidate_only_count += 1
			"invalid_contract":
				invalid_contract_count += 1

	return {
		"entry_count": entries.size(),
		"rule_ids": rule_ids,
		"fact_types": fact_types,
		"state_change_count": state_change_count,
		"relationship_change_count": relationship_change_count,
		"memory_count": memory_count,
		"trace_count": trace_count,
		"rumor_seed_count": rumor_seed_count,
		"pressure_change_count": pressure_change_count,
		"obligation_count": obligation_count,
		"exchange_count": exchange_count,
		"deferred_consequence_count": deferred_consequence_count,
		"obligation_update_count": obligation_update_count,
		"exchange_update_count": exchange_update_count,
		"deferred_consequence_update_count": deferred_consequence_update_count,
		"item_change_count": item_change_count,
		"equipment_change_count": equipment_change_count,
		"chronicle_entry_count": chronicle_entry_count,
		"investigation_change_count": investigation_change_count,
		"tick_event_count": tick_event_count,
		"scoped_tick_event_count": scoped_tick_event_count,
		"failed_tick_event_count": failed_tick_event_count,
		"triggered_deferred_count": triggered_deferred_count,
		"skipped_deferred_count": skipped_deferred_count,
		"obligation_due_count": obligation_due_count,
		"exchange_due_count": exchange_due_count,
		"due_result_count": due_result_count,
		"autonomous_decision_count": autonomous_decision_count,
		"observed_autonomous_decision_count": (
			observed_autonomous_decision_count
		),
		"due_resolution_count": due_resolution_count,
		"obligation_fulfilled_count": obligation_fulfilled_count,
		"obligation_breached_count": obligation_breached_count,
		"exchange_settled_count": exchange_settled_count,
		"exchange_failed_count": exchange_failed_count,
		"keep_due_count": keep_due_count,
		"resolved_count": resolved_count,
		"candidate_only_count": candidate_only_count,
		"invalid_contract_count": invalid_contract_count,
	}


func clear() -> void:
	entries.clear()
