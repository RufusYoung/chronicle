extends RefCounted
class_name V5RumorStore

var rumors: Array = []


func add_rumor_seed(rumor: Dictionary) -> void:
	var new_rumor := rumor.duplicate(true)
	var replacement_key := _replacement_key(new_rumor)
	if replacement_key != "":
		for index in range(rumors.size()):
			if _replacement_key(rumors[index]) == replacement_key:
				rumors[index] = new_rumor
				return
	rumors.append(new_rumor)


func list_rumors() -> Array:
	return rumors.duplicate(true)


func list_rumors_by_location(location_id: String) -> Array:
	var rows: Array = []
	for rumor: Dictionary in rumors:
		if str(rumor.get("origin_location", "")) == location_id:
			rows.append(rumor.duplicate(true))
	return rows


func find_rumors_by_source_fact(fact_type: String) -> Array:
	var rows: Array = []
	for rumor: Dictionary in rumors:
		if str(rumor.get("source_fact_type", "")) == fact_type:
			rows.append(rumor.duplicate(true))
	return rows


func to_save_data() -> Array:
	return list_rumors()


func load_save_data(data: Variant) -> Dictionary:
	rumors.clear()
	var errors: Array[String] = []
	if not data is Array:
		return {"ok": false, "errors": ["save_rumors_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_rumor_not_dictionary")
			continue
		add_rumor_seed(value)
	return {"ok": errors.is_empty(), "errors": errors}


func _replacement_key(rumor: Dictionary) -> String:
	var rumor_key := str(rumor.get("rumor_key", ""))
	var actor_id := str(rumor.get("actor_id", ""))
	var location_id := str(rumor.get(
		"current_location",
		rumor.get("origin_location", rumor.get("location_id", ""))
	))
	if rumor_key == "" or actor_id == "" or location_id == "":
		return ""
	return "%s:%s:%s" % [rumor_key, actor_id, location_id]
