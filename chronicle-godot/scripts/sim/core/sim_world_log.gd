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

	return {
		"entry_count": entries.size(),
		"rule_ids": rule_ids,
		"fact_types": fact_types,
		"state_change_count": state_change_count,
		"relationship_change_count": relationship_change_count,
		"memory_count": memory_count,
		"trace_count": trace_count,
		"rumor_seed_count": rumor_seed_count,
	}


func clear() -> void:
	entries.clear()
