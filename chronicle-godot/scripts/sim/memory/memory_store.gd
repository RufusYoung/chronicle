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
