extends RefCounted
class_name V5FactStore

var facts: Array = []


func add_fact(fact: Dictionary) -> void:
	facts.append(fact.duplicate(true))


func list_facts() -> Array:
	return facts.duplicate(true)


func clear() -> void:
	facts.clear()
