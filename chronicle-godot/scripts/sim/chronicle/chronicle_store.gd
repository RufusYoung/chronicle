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
