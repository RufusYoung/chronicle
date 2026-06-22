extends RefCounted
class_name V5RumorStore

var rumors: Array = []


func add_rumor_seed(rumor: Dictionary) -> void:
	rumors.append(rumor.duplicate(true))


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
