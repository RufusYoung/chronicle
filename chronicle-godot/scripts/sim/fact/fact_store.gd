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


func find_facts_by_type(fact_type: String) -> Array:
	var rows: Array = []
	for fact: Dictionary in facts:
		if str(fact.get("fact_type", fact.get("type", ""))) == fact_type:
			rows.append(fact.duplicate(true))
	return rows


func clear() -> void:
	facts.clear()
