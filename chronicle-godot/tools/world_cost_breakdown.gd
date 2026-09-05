extends SceneTree
## Independent read-only microprobes; their times overlap, never sum them.

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Writer = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
var rows: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := Live.new()
	var loaded := model.load_from_path("user://tests/world_runtime_probe/day7.json")
	if not loaded.get("success", false):
		push_error(str(loaded))
		quit(1)
		return
	var writer := Writer.new()
	var state := _state(model)
	_measure("snapshot", model.session.get_snapshot)
	_measure("world_projection", model.build_view_data)
	_measure("transaction_preview_all_stores", writer._build_preview_stores.bind(model.session.stores))
	for key: String in model.session.stores:
		var source: Variant = model.session.stores[key]
		var target: Variant = source.get_script().new()
		_measure("transaction_copy/" + key, writer._copy_script_properties.bind(source, target, false, {}))
	var unchanged := _state(model) == state
	var output := "user://tests/world_action_profile"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var tag := "breakdown" if OS.get_cmdline_user_args().is_empty() else OS.get_cmdline_user_args()[0].validate_filename()
	var file := FileAccess.open(output + "/" + tag + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "unchanged": unchanged,
		"counts": model.session.get_store_summary(), "scope": "Warm microprobes; overlapping costs, not tick attribution."}, "  "))
	file.close()
	print(JSON.stringify(rows))
	print("COST_BREAKDOWN_RESULT " + ("PASS" if unchanged else "FAIL"))
	quit(0 if unchanged else 1)


func _measure(label: String, operation: Callable) -> void:
	var durations: Array[float] = []
	for i: int in 5:
		var began := Time.get_ticks_usec()
		operation.call()
		durations.append((Time.get_ticks_usec() - began) / 1000.0)
	rows.append({"phase": label, "samples_ms": durations})


func _state(model: Variant) -> String:
	var envelope: Dictionary = model.session.build_save_envelope()
	return JSON.stringify({"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states,
		"world_log": envelope.world_log}, "", true, true)
