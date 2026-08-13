extends RefCounted
class_name V5MemoryStore

var memories: Array = []


func add_memory(memory: Dictionary) -> void:
	memories.append(memory.duplicate(true))


func list_memories(owner_id: String) -> Array:
	var rows: Array = []
	for memory: Dictionary in memories:
		if str(memory.get("owner_id", "")) == owner_id:
			rows.append(memory.duplicate(true))
	return rows


func find_memories_by_type(owner_id: String, memory_type: String) -> Array:
	var rows: Array = []
	for memory: Dictionary in memories:
		if (
			str(memory.get("owner_id", "")) == owner_id
			and str(memory.get("memory_type", "")) == memory_type
		):
			rows.append(memory.duplicate(true))
	return rows


func to_save_data() -> Array:
	return memories.duplicate(true)


func load_save_data(data: Variant) -> Dictionary:
	memories.clear()
	var errors: Array[String] = []
	var seen_ids: Dictionary = {}
	if not data is Array:
		return {"ok": false, "errors": ["save_memories_not_array"]}
	for value: Variant in data:
		if not value is Dictionary:
			errors.append("save_memory_not_dictionary")
			continue
		var memory := value as Dictionary
		var memory_id := str(memory.get("memory_id", ""))
		if memory_id == "" or seen_ids.has(memory_id):
			errors.append("invalid_or_duplicate_memory_id:%s" % memory_id)
			continue
		seen_ids[memory_id] = true
		add_memory(memory)
	return {"ok": errors.is_empty(), "errors": errors}
