extends RefCounted
class_name V5PressureStore

var pressures: Array = []


func add_pressure_change(change: Dictionary) -> void:
	pressures.append(change.duplicate(true))


func list_pressures() -> Array:
	return pressures.duplicate(true)


func list_pressures_by_domain(domain: String) -> Array:
	var rows: Array = []
	for pressure: Dictionary in pressures:
		if str(pressure.get("domain", "")) == domain:
			rows.append(pressure.duplicate(true))
	return rows


func list_pressures_by_location(location_id: String) -> Array:
	var rows: Array = []
	for pressure: Dictionary in pressures:
		if str(pressure.get("scope_id", "")) == location_id:
			rows.append(pressure.duplicate(true))
	return rows


func get_pressure_value(scope_id: String, pressure_type: String) -> int:
	var total := 0
	for pressure: Dictionary in pressures:
		if (
			str(pressure.get("scope_id", "")) == scope_id
			and str(pressure.get("pressure_type", "")) == pressure_type
		):
			total += int(pressure.get("value", 0))
	return total


func to_save_data() -> Array:
	return list_pressures()


func load_save_data(data: Variant) -> Dictionary:
	pressures.clear()
	var errors: Array[String] = []
	if not data is Array:
		return {"ok": false, "errors": ["save_pressures_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_pressure_not_dictionary")
			continue
		add_pressure_change(value)
	return {"ok": errors.is_empty(), "errors": errors}
