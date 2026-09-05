extends SceneTree

const FactStore = preload("res://scripts/sim/fact/fact_store.gd")
const Writer = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := FactStore.new()
	var input := {"fact_id": "old", "fact_type": "test", "nested": {"values": [1, {"count": 2}]}}
	source.add_fact(input)
	input.nested.values[1].count = 9
	_check(source.get_fact("old").nested.values[1].count == 2, "insertion isolates caller data")
	var history := source.snapshot_facts()
	_check(history[0].is_read_only(), "historical fact is frozen")
	_check(history[0].nested.is_read_only() and history[0].nested.values.is_read_only()
		and history[0].nested.values[1].is_read_only(), "nested dictionaries and arrays are frozen")
	history.clear()
	_check(source.snapshot_facts().size() == 1, "snapshot container cannot clear live history")
	for copy: Variant in [source.get_fact("old"), source.list_facts()[0],
			source.find_facts_by_type("test")[0], source.to_save_data()[0]]:
		_check(not copy.is_read_only() and not copy.nested.values.is_read_only(), "public deep copies remain editable")
		copy.nested.values[1].count = 100
	_check(source.get_fact("old").nested.values[1].count == 2, "public edits cannot change recorded facts")
	var loaded := FactStore.new()
	_check(loaded.load_save_data(source.to_save_data()).ok, "save restores facts")
	_check(loaded.snapshot_facts()[0].nested.values[1].is_read_only(), "load reapplies recursive protection")
	var writer := Writer.new()
	var stores := {"fact_store": source}
	var preview: Dictionary = writer._build_preview_stores(stores).stores
	_check(is_same(preview.fact_store.facts[0], source.facts[0]), "preview shares only frozen record identity")
	preview.fact_store.add_fact({"fact_id": "preview", "fact_type": "test"})
	_check(source.get_fact("preview").is_empty() and source.find_facts_by_type("test").size() == 1,
		"uncommitted append cannot enter live array or index")
	writer._commit_preview(preview, stores)
	preview.fact_store.clear()
	_check(source.get_fact("preview").fact_id == "preview" and source.find_facts_by_type("test").size() == 2,
		"post-commit preview clear cannot erase live containers")
	var first := Result.new()
	first.add_fact({"fact_id": "first_batch", "fact_type": "test"})
	var invalid := Result.new()
	invalid.add_fact({"fact_id": "failed_batch", "fact_type": "test"})
	invalid.add_state_change({"entity_id": "missing", "key": "x", "value": 1})
	var before := JSON.stringify(source.to_save_data(), "", true, true)
	_check(not writer.apply_results([first, invalid], stores), "batch rejects missing state store")
	_check(before == JSON.stringify(source.to_save_data(), "", true, true), "failed batch rolls back even earlier facts")
	_check(source.get_fact("first_batch").is_empty() and source.get_fact("failed_batch").is_empty(), "rollback preserves fact index")
	_check(writer.apply_result(first, stores), "successful fact transaction commits")
	first.facts_added[0]["fact_type"] = "caller_changed"
	_check(source.get_fact("first_batch").fact_type == "test", "transaction result cannot mutate committed history")
	source.add_fact({"fact_id": "first_batch", "fact_type": "duplicate"})
	_check(source.find_facts_by_type("duplicate").is_empty(), "duplicate IDs remain idempotent")
	print("FACT_HISTORY_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
