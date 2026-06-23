extends RefCounted
class_name V5SimWorldLog

var entries: Array = []


func append_entry(entry: Dictionary) -> void:
	entries.append(entry.duplicate(true))


func list_entries() -> Array:
	return entries.duplicate(true)


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
		"resolved_count": resolved_count,
		"candidate_only_count": candidate_only_count,
		"invalid_contract_count": invalid_contract_count,
	}


func clear() -> void:
	entries.clear()
