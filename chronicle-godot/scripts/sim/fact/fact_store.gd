extends RefCounted
class_name V5FactStore

var facts: Array = []


func add_fact(fact: Dictionary) -> void:
	var fact_id := str(fact.get("fact_id", ""))
	if fact_id != "":
		for existing: Dictionary in facts:
			if str(existing.get("fact_id", "")) == fact_id:
				return
	facts.append(fact.duplicate(true))


func list_facts() -> Array:
	return facts.duplicate(true)


func get_fact(fact_id: String) -> Dictionary:
	if fact_id == "":
		return {}
	for fact: Dictionary in facts:
		if str(fact.get("fact_id", "")) == fact_id:
			return fact.duplicate(true)
	return {}


func find_facts_by_type(fact_type: String) -> Array:
	var rows: Array = []
	for fact: Dictionary in facts:
		if str(fact.get("fact_type", fact.get("type", ""))) == fact_type:
			rows.append(fact.duplicate(true))
	return rows


func clear() -> void:
	facts.clear()


func to_save_data() -> Array:
	return list_facts()


func load_save_data(data: Variant) -> Dictionary:
	clear()
	var errors: Array[String] = []
	var seen_ids: Dictionary = {}
	if not data is Array:
		return {"ok": false, "errors": ["save_facts_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_fact_not_dictionary")
			continue
		var fact := value as Dictionary
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id == "":
			errors.append("save_fact_missing_id")
			continue
		if seen_ids.has(fact_id):
			errors.append("duplicate_fact_id:%s" % fact_id)
			continue
		seen_ids[fact_id] = true
		add_fact(fact)
	return {"ok": errors.is_empty(), "errors": errors}
