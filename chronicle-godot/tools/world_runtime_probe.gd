extends SceneTree
## Bounded, passive-world cost probe. Deliberately excluded from ordinary test discovery.

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
var output := "user://tests/world_runtime_probe"
var rows: Array = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var model := Live.new()
	var began := Time.get_ticks_usec()
	_check(model.start({"scenario": "generated_network", "challenge_seed_override": 81001}).success, "start")
	rows.append({"phase": "start", "ms": _ms(began)})
	var checkpoint := ""
	for day: int in range(1, 8):
		began = Time.get_ticks_usec()
		var advanced: Dictionary = model.session.advance_time(24, "runtime_probe", {"scope_type": "global", "scope_id": "", "source": "passive_runtime_probe"})
		_check(advanced.get("success", false), "advance_day_%d" % day)
		rows.append({"phase": "simulation", "elapsed_days": day, "ms": _ms(began)})
		if day in [1, 7]:
			began = Time.get_ticks_usec()
			var view := model.build_view_data()
			rows.append({"phase": "projection", "elapsed_days": day, "ms": _ms(began)})
			_check(view.ready, "projection_day_%d" % day)
			began = Time.get_ticks_usec()
			var audit: Dictionary = model.session.validate_persistent_references()
			rows.append({"phase": "reference_audit", "elapsed_days": day, "ms": _ms(began), "result": audit})
			_check(audit.get("ok", false), "reference_audit_day_%d" % day)
			began = Time.get_ticks_usec()
			checkpoint = output + "/day%d.json" % day
			var saved := model.save_to_path(checkpoint, true)
			_check(saved.success, "save_day_%d" % day)
			rows.append({"phase": "save_with_integrity_readback", "elapsed_days": day, "ms": _ms(began), "byte_count": saved.get("byte_count", 0)})
			rows.append({"phase": "counts", "elapsed_days": day, "counts": model.session.get_store_summary()})
		_flush()
		print("WORLD_RUNTIME_DAY %d" % day)
	var restored := Live.new()
	began = Time.get_ticks_usec()
	_check(restored.load_from_path(checkpoint).success, "load_day7")
	rows.append({"phase": "load", "elapsed_days": 7, "ms": _ms(began)})
	var metadata := {"scope_type": "global", "scope_id": "", "source": "passive_runtime_probe"}
	_check(model.session.advance_time(1, "continuation", metadata).success, "uninterrupted_hour")
	_check(restored.session.advance_time(1, "continuation", metadata).success, "restored_hour")
	_check(_signature(model) == _signature(restored), "day7_disk_continuation_native_precision")
	_check(model.session.action_count == 0, "no_actor_actions")
	_flush()
	print("WORLD_RUNTIME_RESULT " + ("PASS" if failures.is_empty() else "FAIL"))
	print("WORLD_RUNTIME_EVIDENCE " + ProjectSettings.globalize_path(output))
	quit(0 if failures.is_empty() else 1)


func _flush() -> void:
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed": 81001, "engine": Engine.get_version_info(),
		"processor": OS.get_processor_name(), "rows": rows, "failures": failures,
		"scope": "Seven passive days, no interventions; one-hour native-precision continuation at day seven. Not a gameplay or economy acceptance."}, "  "))
	file.close()


func _ms(began: int) -> float:
	return (Time.get_ticks_usec() - began) / 1000.0


func _signature(model: Variant) -> String:
	var envelope: Dictionary = model.session.build_save_envelope()
	var value := {"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states, "world_log": envelope.world_log}
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, false)), "", true, false)


func _check(condition: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)
