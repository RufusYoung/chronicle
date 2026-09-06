extends SceneTree
## Run the identical probe against a reference checkout and the optimized checkout.

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected native checkpoint and output JSON path.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[1].get_base_dir())
	var model := Live.new()
	var opened := model.load_from_path(args[0])
	if not opened.get("success", false):
		push_error(str(opened))
		quit(1)
		return
	var rows: Array = [_row(model, 0)]
	for hour: int in 24:
		if not model.advance_time(1).get("success", false):
			failures.append("hour failed: " + str(hour + 1))
			break
		rows.append(_row(model, hour + 1))
		if (hour + 1) % 6 == 0:
			print("CONTINUATION_HOUR ", hour + 1)
	if not model.session.validate_persistent_references().get("ok", false):
		failures.append("invalid persistent references")
	var native_path := args[1].get_basename() + ".native.json"
	var saved := model.save_to_path(native_path, true)
	var restored := Live.new()
	var roundtrip := {"numeric_changes": 0, "other_changes": 0, "maximum_absolute_delta": 0.0, "examples": []}
	if not saved.get("success", false) or not restored.load_from_path(native_path).get("success", false):
		failures.append("native save/load failed")
	else:
		_differences(_state_data(model), _state_data(restored), "", roundtrip)
		if _native_state(model) != _native_state(restored):
			failures.append("native reload state changed at the existing save precision")
		elif not model.advance_time(1).get("success", false) or not restored.advance_time(1).get("success", false):
			failures.append("reloaded continuation failed")
		elif _native_state(model) != _native_state(restored):
			failures.append("reloaded continuation diverged at the existing save precision")
		else:
			rows.append(_row(model, 25))
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "failures": failures,
		"checkpoint": args[0], "passed": failures.is_empty(), "roundtrip_differences": roundtrip,
		"scope": "Legal observer waits with UI-data projection. Row hashes compare full runtime precision across code versions. Disk continuation uses the existing SaveEnvelope canonical precision and reports numeric roundtrip differences; not bit-identical floating-point persistence or human play."}, "  "))
	file.close()
	print("WORLD_CONTINUATION_RESULT ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)


func _row(model: Variant, hour: int) -> Dictionary:
	return {"hour": hour, "elapsed_hours": model.session.get_time_summary().elapsed_hours,
		"state_sha256": _state(model).sha256_text(),
		"view_sha256": JSON.stringify(model.build_view_data(), "", true, true).sha256_text()}


func _state(model: Variant) -> String:
	return JSON.stringify(_state_data(model), "", true, true)


func _native_state(model: Variant) -> String:
	return Saves.new()._canonical_json(_state_data(model))


func _state_data(model: Variant) -> Dictionary:
	var envelope: Dictionary = model.session.build_save_envelope()
	return {"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states,
		"world_log": envelope.world_log}


func _differences(a: Variant, b: Variant, path: String, report: Dictionary) -> void:
	if a is Dictionary and b is Dictionary and a.size() == b.size():
		for key: Variant in a:
			if not b.has(key):
				report.other_changes += 1
				continue
			_differences(a[key], b[key], path + "/" + str(key), report)
		return
	if a is Array and b is Array and a.size() == b.size():
		for index: int in a.size():
			_differences(a[index], b[index], path + "/" + str(index), report)
		return
	if a == b:
		return
	if (a is float or a is int) and (b is float or b is int):
		report.numeric_changes += 1
		report.maximum_absolute_delta = maxf(report.maximum_absolute_delta, absf(float(a) - float(b)))
	else:
		report.other_changes += 1
	if report.examples.size() < 12:
		report.examples.append({"path": path, "before": a, "after": b})
