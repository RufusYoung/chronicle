extends RefCounted
class_name V5FactStore

var facts: Array = []
var facts_by_id: Dictionary = {}
var facts_by_type: Dictionary = {}


func add_fact(fact: Dictionary) -> void:
	var fact_id := str(fact.get("fact_id", ""))
	if fact_id != "" and facts_by_id.has(fact_id):
		return
	var stored := fact.duplicate(true)
	_freeze(stored)
	facts.append(stored)
	if fact_id != "":
		facts_by_id[fact_id] = stored
	var fact_type := str(stored.get("fact_type", stored.get("type", "")))
	if fact_type != "":
		if not facts_by_type.has(fact_type):
			facts_by_type[fact_type] = []
		(facts_by_type[fact_type] as Array).append(stored)


func list_facts() -> Array:
	return facts.duplicate(true)


func snapshot_facts() -> Array:
	return facts.duplicate()


func copy_runtime_to(target: Variant) -> void:
	# Transactions own their containers; only recursively frozen facts are shared.
	target.facts = facts.duplicate()
	target.facts_by_id = facts_by_id.duplicate()
	var types := {}
	for key: String in facts_by_type:
		types[key] = (facts_by_type[key] as Array).duplicate()
	target.facts_by_type = types


func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for child: Variant in value:
			_freeze(child)
		value.make_read_only()


func get_fact(fact_id: String) -> Dictionary:
	if fact_id == "" or not facts_by_id.has(fact_id):
		return {}
	return (facts_by_id[fact_id] as Dictionary).duplicate(true)


func find_facts_by_type(fact_type: String) -> Array:
	if not facts_by_type.has(fact_type):
		return []
	return (facts_by_type[fact_type] as Array).duplicate(true)


func clear() -> void:
	facts.clear()
	facts_by_id.clear()
	facts_by_type.clear()


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
