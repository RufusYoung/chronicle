extends RefCounted
class_name V5InvestigationLeadStore

var leads: Dictionary = {}


func apply_change(change: Dictionary) -> void:
	match str(change.get("operation", "")):
		"create":
			var lead: Variant = change.get("lead", {})
			if lead is Dictionary:
				_create_lead(lead)
		"update":
			_update_lead(change)


func get_lead(lead_id: String) -> Dictionary:
	if not leads.has(lead_id):
		return {}
	return (leads[lead_id] as Dictionary).duplicate(true)


func list_leads() -> Array:
	var rows: Array = []
	for lead: Dictionary in leads.values():
		rows.append(lead.duplicate(true))
	return rows


func list_open_leads() -> Array:
	var rows: Array = []
	for lead: Dictionary in leads.values():
		if str(lead.get("status", "open")) == "open":
			rows.append(lead.duplicate(true))
	return rows


func list_open_leads_at_location(location_id: String) -> Array:
	var rows: Array = []
	for lead: Dictionary in leads.values():
		if (
			str(lead.get("status", "open")) == "open"
			and str(lead.get("location_id", "")) == location_id
		):
			rows.append(lead.duplicate(true))
	return rows


func to_save_data() -> Array:
	var rows := list_leads()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("lead_id", "")) < str(b.get("lead_id", ""))
	)
	return rows


func load_save_data(data: Variant) -> Dictionary:
	leads.clear()
	var errors: Array[String] = []
	if not data is Array:
		return {"ok": false, "errors": ["save_investigation_leads_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_investigation_lead_not_dictionary")
			continue
		var lead := value as Dictionary
		var lead_id := str(lead.get("lead_id", lead.get("id", "")))
		if lead_id == "" or leads.has(lead_id):
			errors.append("invalid_or_duplicate_lead_id:%s" % lead_id)
			continue
		_create_lead(lead)
	return {"ok": errors.is_empty(), "errors": errors}


func _create_lead(lead: Dictionary) -> void:
	var lead_id := str(lead.get("lead_id", lead.get("id", "")))
	if lead_id == "" or leads.has(lead_id):
		return
	var stored := lead.duplicate(true)
	stored["lead_id"] = lead_id
	stored["status"] = str(stored.get("status", "open"))
	stored["disposition"] = str(
		stored.get("disposition", "fresh")
	)
	stored["history"] = (
		stored.get("history", []) as Array
	).duplicate(true)
	leads[lead_id] = stored


func _update_lead(change: Dictionary) -> void:
	var lead_id := str(change.get("lead_id", ""))
	if lead_id == "" or not leads.has(lead_id):
		return
	var stored: Dictionary = (
		leads[lead_id] as Dictionary
	).duplicate(true)
	var fields: Variant = change.get("fields", {})
	if fields is Dictionary:
		for key: String in (fields as Dictionary).keys():
			stored[key] = (fields as Dictionary)[key]
	var history_entry: Variant = change.get("history_entry", {})
	if history_entry is Dictionary and not history_entry.is_empty():
		var history: Array = (
			stored.get("history", []) as Array
		).duplicate(true)
		history.append((history_entry as Dictionary).duplicate(true))
		stored["history"] = history
	leads[lead_id] = stored
