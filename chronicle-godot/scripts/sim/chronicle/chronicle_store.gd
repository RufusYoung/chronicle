extends RefCounted
class_name V5ChronicleStore

var entries: Dictionary = {}


func add_entry(entry: Dictionary) -> void:
	var entry_id := str(entry.get("entry_id", ""))
	if entry_id == "" or entries.has(entry_id):
		return
	entries[entry_id] = entry.duplicate(true)


func get_entry(entry_id: String) -> Dictionary:
	if not entries.has(entry_id):
		return {}
	return (entries[entry_id] as Dictionary).duplicate(true)


func list_entries() -> Array:
	var rows: Array = []
	for entry: Dictionary in entries.values():
		rows.append(entry.duplicate(true))
	return rows


func list_entries_for_subject(subject_id: String) -> Array:
	var rows: Array = []
	for entry: Dictionary in entries.values():
		if str(entry.get("subject_id", "")) == subject_id:
			rows.append(entry.duplicate(true))
	return rows


func to_save_data() -> Array:
	var rows := list_entries()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("entry_id", "")) < str(b.get("entry_id", ""))
	)
	return rows


func load_save_data(data: Variant) -> Dictionary:
	entries.clear()
	var errors: Array[String] = []
	if not data is Array:
		return {"ok": false, "errors": ["save_chronicle_entries_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_chronicle_entry_not_dictionary")
			continue
		var entry := value as Dictionary
		var entry_id := str(entry.get("entry_id", ""))
		if entry_id == "" or entries.has(entry_id):
			errors.append("invalid_or_duplicate_chronicle_entry_id:%s" % entry_id)
			continue
		add_entry(entry)
	return {"ok": errors.is_empty(), "errors": errors}
