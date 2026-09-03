extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const ViewModel = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const OUTPUT := "user://tests/world_surface_profile.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := ""
	var steps := 10
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--save-path="):
			path = argument.trim_prefix("--save-path=")
		elif argument.begins_with("--steps="):
			steps = clampi(argument.trim_prefix("--steps=").to_int(), 1, 30)
	if path == "":
		push_error("Usage: -- --save-path=<generated-world-save.json> [--steps=10]")
		quit(1)
		return
	var session = Session.new()
	var loaded: Dictionary = session.load_from_path(path)
	if not bool(loaded.get("success", false)) or session.get_settlement_network_summary().is_empty():
		push_error("Generated network save required: " + JSON.stringify(loaded))
		quit(1)
		return
	var initial_time: Dictionary = session.get_time_summary()
	root.content_scale_size = Vector2i(1280, 720)
	var viewer: Control = load("res://scenes/rebuild/v5_live_location_viewer.tscn").instantiate()
	root.add_child(viewer)
	await process_frame
	viewer.view_model = ViewModel.new(session)
	var measurements: Array = []
	var passed := true
	for step: int in range(steps + 1):
		var started := Time.get_ticks_msec()
		var result: Dictionary = {"success": true}
		if step > 0:
			result = viewer.view_model.advance_time(1)
		var simulation_ms := Time.get_ticks_msec() - started
		started = Time.get_ticks_msec()
		viewer.refresh_view()
		var refresh_ms := Time.get_ticks_msec() - started
		if DisplayServer.get_name() == "headless":
			await process_frame
		else:
			await RenderingServer.frame_post_draw
		var row := {"step": step, "simulation_ms": simulation_ms,
			"refresh_ms": refresh_ms, "success": bool(result.get("success", false))}
		measurements.append(row)
		passed = passed and bool(row["success"])
		print("[WORLD SURFACE PROFILE] ", JSON.stringify(row))
	var references: Dictionary = session.validate_persistent_references()
	passed = passed and bool(references.get("ok", false))
	var report := {"passed": passed, "save_path": path, "initial_time": initial_time,
		"final_time": session.get_time_summary(), "renderer": DisplayServer.get_name(),
		"steps": steps, "measurements": measurements, "references": references,
		"method": "Automated one-hour wait and refresh calls; source save is never rewritten."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if output == null:
		push_error("Cannot write profile output: " + OUTPUT)
		passed = false
	else:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	viewer.queue_free()
	print("[WORLD SURFACE PROFILE RESULT] ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
