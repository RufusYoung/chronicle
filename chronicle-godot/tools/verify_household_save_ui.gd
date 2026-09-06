extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not FileAccess.file_exists(args[0]) or DisplayServer.get_name() == "headless":
		push_error("Expected an existing native checkpoint and output directory, with a real renderer.")
		quit(1)
		return
	var output := args[1]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Demo.instantiate()
	viewer.save_path = args[0]
	root.add_child(viewer)
	await process_frame
	_check(viewer.current_view_data.get("ready", false) and not viewer.busy, "native world is ready in actual UI")
	var s: Variant = viewer.view_model.session
	var elapsed := int(s.get_time_summary().get("elapsed_hours", 0))
	_check(elapsed == 720 and s.fixture_source_data.resident_daily_life.food_access.has("subsistence"), "loaded integrated thirty-day world, not a fresh fallback")
	_check(not viewer.wait_button.disabled and viewer.action_dock.get_global_rect().end.y <= root.size.y, "controls fit and are enabled at 720p")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/loaded_day30.png")
	var began := Time.get_ticks_msec()
	viewer.wait_button.pressed.emit()
	var deadline := began + 120000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	if viewer.busy:
		viewer._worker.wait_to_finish()
		viewer._worker = null
		viewer.busy = false
		_check(false, "operation timed out")
	await process_frame
	await RenderingServer.frame_post_draw
	var wait_ms := Time.get_ticks_msec() - began
	_check(viewer.last_operation.get("result", {}).get("success", false), "UI wait committed successfully")
	_check(int(s.get_time_summary().get("elapsed_hours", 0)) == elapsed + 1 and not viewer.wait_button.disabled, "old world advances exactly one hour and controls recover")
	_check(s.validate_persistent_references().ok, "continued world references remain valid")
	root.get_texture().get_image().save_png(output + "/continued_day30.png")
	_check(s.save_to_path(output + "/continued.json").ok, "save continued world without overwriting source")
	var result := {"passed": failures.is_empty(), "failures": failures, "elapsed_hours_before": elapsed,
		"elapsed_hours_after": s.get_time_summary().get("elapsed_hours"), "checkpoint": args[0],
		"renderer": RenderingServer.get_current_rendering_method(), "wait_through_draw_ms": wait_ms,
		"operation_ms": viewer.last_operation.get("operation_ms"), "projection_ms": viewer.last_operation.get("projection_ms"),
		"scope": "Program-driven real UI of a native thirty-day world, with a legal wait. Not human play or a latency distribution."}
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("HOUSEHOLD_SAVE_UI_RESULT " + JSON.stringify(result))
	viewer.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	print("[PASS] " if ok else "[FAIL] ", label)
	if not ok:
		failures.append(label)
