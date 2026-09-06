extends SceneTree

const MemoryStore = preload("res://scripts/sim/memory/memory_store.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot.gd")
const Writer = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	var source := MemoryStore.new()
	var input := {"memory_id": "old", "owner_id": "resident", "memory_type": "test",
		"nested": {"values": [1, {"count": 2}]}}
	source.add_memory(input)
	input.nested.values[1].count = 9
	_check(source.list_memories("resident")[0].nested.values[1].count == 2, "insertion isolates caller data")
	var history := source.snapshot_memories()
	_check(history[0].is_read_only() and history[0].nested.is_read_only()
		and history[0].nested.values.is_read_only() and history[0].nested.values[1].is_read_only(),
		"records are recursively frozen")
	history.clear()
	_check(source.snapshot_memories().size() == 1, "snapshot array is independent")
	for copy: Dictionary in [source.list_memories("resident")[0],
			source.find_memories_by_type("resident", "test")[0], source.to_save_data()[0]]:
		_check(not copy.is_read_only() and not copy.nested.values.is_read_only(), "public copies remain editable")
		copy.nested.values[1].count = 100
	_check(source.list_memories("resident")[0].nested.values[1].count == 2, "public edits cannot alter history")
	var direct := Snapshot.new({"memories": [input]})
	input.nested.values[1].count = 17
	_check(direct.get_memories("resident")[0].nested.values[1].count == 9,
		"direct snapshot constructor still isolates mutable caller data")
	var loaded := MemoryStore.new()
	_check(loaded.load_save_data(source.to_save_data()).ok, "native data roundtrips")
	_check(loaded.snapshot_memories()[0].nested.values[1].is_read_only(), "load reapplies recursive protection")
	var writer := Writer.new()
	var stores := {"memory_store": source}
	var preview: Dictionary = writer._build_preview_stores(stores).stores
	_check(is_same(preview.memory_store.memories[0], source.memories[0]), "preview shares frozen record identity")
	preview.memory_store.add_memory({"memory_id": "preview", "owner_id": "resident"})
	_check(source.list_memories("resident").size() == 1, "uncommitted append stays private")
	writer._commit_preview(preview, stores)
	preview.memory_store.memories.clear()
	_check(source.list_memories("resident").size() == 2, "post-commit clear cannot alter live array")
	var first := Result.new()
	first.add_memory({"memory_id": "first_batch", "owner_id": "resident", "memory_type": "transaction"})
	var invalid := Result.new()
	invalid.add_memory({"memory_id": "failed_batch", "owner_id": "resident"})
	invalid.add_state_change({"entity_id": "missing", "key": "x", "value": 1})
	var before := JSON.stringify(source.to_save_data(), "", true, true)
	_check(not writer.apply_results([first, invalid], stores), "invalid batch is rejected")
	_check(before == JSON.stringify(source.to_save_data(), "", true, true), "entire batch rolls back")
	_check(writer.apply_result(first, stores), "valid memory transaction commits")
	first.memories_added[0].memory_type = "changed"
	_check(source.find_memories_by_type("resident", "transaction").size() == 1,
		"editing result cannot mutate committed memory")
	print("MEMORY_HISTORY_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
