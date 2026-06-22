extends RefCounted
class_name V5FactStore

var facts: Array = []


func add_fact(fact: Dictionary) -> void:
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
