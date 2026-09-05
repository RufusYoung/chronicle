extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
var failures: Array[String] = []
var samples: Array = []
var checks := 0
var path := "user://tests/world_demo_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
var output := "user://tests/world_demo_evidence"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/rebuild/world_bootstrap.tscn", "formal project entry dispatches through world bootstrap")
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var began := Time.get_ticks_usec()
	var viewer = Demo.instantiate()
	viewer.save_path = path
	root.add_child(viewer)
	await process_frame
	await process_frame
	samples.append({"method": "startup_to_frame", "ms": (Time.get_ticks_usec() - began) / 1000.0})
	_check(viewer.current_view_data.playtest.mode == "generated_settlement_network", "formal demo opens generated world")
	_check(viewer.current_view_data.region_map.sites.size() == 3 and viewer.current_view_data.region_map.roads.size() == 2, "region reflects actual three-site topology")
	_check(viewer.current_view_data.region_map.current_settlement_id == "generated_settlement.reed_bay", "map locates traveler")
	var signature := _signature(viewer.view_model)
	viewer.surface.tabs.current_tab = 1
	await process_frame
	_check(not viewer.action_dock.visible, "map page does not compete with action dock")
	_check(_signature(viewer.view_model) == signature, "viewing region changes no Stores or RNG")
	viewer._request_quit()
	_check(viewer._quit_dialog.visible and not auto_accept_quit, "window exit protects unsaved work")
	viewer._quit_dialog.hide()
	await _screenshot("region_1280.png")
	viewer.surface.tabs.current_tab = 0
	await process_frame
	await _screenshot("scene_1280.png")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "action dock fits 720p viewport")

	viewer._request_load()
	_check("还没有" in viewer._status.text and not viewer.busy, "missing save gives actionable feedback")
	viewer._request_save()
	await _settle(viewer)
	_check(FileAccess.file_exists(path), "UI writes isolated native world save")
	var checkpoint := _signature(viewer.view_model)
	var checkpoint_view := _native(viewer.current_view_data)
	viewer._request_save()
	_check(viewer._save_dialog.visible and not viewer.busy, "overwrite requires confirmation")
	viewer._save_dialog.hide()
	_check(_signature(viewer.view_model) == checkpoint, "cancelled overwrite does not advance world")

	var river := _route_to(viewer.view_model, "generated_location.river_steps.commons")
	var same_session: Variant = viewer.view_model.session
	viewer.perform_travel(river)
	_check(viewer.busy and viewer.wait_button.disabled, "worker rejects duplicate actions while busy")
	_check(viewer.advance_time().error == "operation_in_progress", "duplicate action rejected before execution")
	viewer._request_quit()
	_check(not viewer._quit_dialog.visible, "quit waits for in-flight settlement")
	var frames := await _settle(viewer)
	_check(frames > 1, "UI frames continue during settlement")
	_check(viewer.view_model.session == same_session, "cross-town travel keeps same live session")
	_check(viewer.current_view_data.region_map.current_settlement_id == "generated_settlement.river_steps", "arrival moves map marker")
	_check(not viewer._picture.visible, "reed-bank illustration is not reused as a different town")
	var after_travel := _signature(viewer.view_model)
	viewer._request_load()
	_check(viewer._load_dialog.visible and not viewer.busy, "restoring save requires confirmation")
	viewer._load_dialog.hide()
	viewer._load_dialog.confirmed.emit()
	await _settle(viewer)
	_check(checkpoint == _signature(viewer.view_model), "disk load restores every Store, time and RNG at native precision")
	_check(checkpoint_view == _native(viewer.current_view_data), "disk load restores feedback, choices and map")
	viewer.perform_travel(river)
	await _settle(viewer)
	_check(after_travel == _signature(viewer.view_model), "travel after disk load reproduces uninterrupted continuation")
	viewer.perform_travel(_route_to(viewer.view_model, "generated_location.wind_pass.commons"))
	await _settle(viewer)
	_check(viewer.current_view_data.region_map.current_settlement_id == "generated_settlement.wind_pass", "second cross-town arrival stays in same world")
	viewer.perform_travel(_route_to(viewer.view_model, "generated_location.wind_pass.road_yard"))
	await _settle(viewer)
	_check(viewer.current_view_data.region_map.current_settlement_id == "generated_settlement.wind_pass", "interior facility retains correct town marker")
	viewer.advance_time()
	await _settle(viewer)
	viewer._begin_operation("save_to_path", [path, true])
	await _settle(viewer)
	var saved := _signature(viewer.view_model)
	viewer.queue_free()
	await process_frame
	var continued = Demo.instantiate()
	continued.save_path = path
	root.add_child(continued)
	await process_frame
	await process_frame
	_check(saved == _signature(continued.view_model), "fresh viewer continues saved world instead of regenerating it")
	_check("继续" in continued._status.text, "startup tells player it resumed the save")
	var old_session: Variant = continued.view_model.session
	_check(not continued.view_model.load_from_path(path + ".missing").success and continued.view_model.session == old_session, "failed read leaves live session intact")
	var malformed: Dictionary = Saves.new().load_from_path(path).envelope
	malformed.live_surface_runtime.action_history = ["invalid"]
	Saves.new().save_to_path(path + ".bad", Saves.new().finalize_envelope(malformed))
	_check(not continued.view_model.load_from_path(path + ".bad").success and saved == _signature(continued.view_model), "malformed surface runtime is rejected atomically")
	continued._request_restart()
	await process_frame
	await _screenshot("new_world_confirmation.png")
	_check(continued.restart_dialog.visible, "new world requires confirmation and exposes seed")
	continued.restart_dialog.hide()
	continued._seed_input.value = 82002
	continued.restart_session()
	await _settle(continued)
	_check(continued.current_view_data.region_map.seed == 82002, "new world uses selected generation seed")
	_check(_signature_from_save(path) == saved, "new world does not overwrite existing disk save")
	root.content_scale_size = Vector2i(1600, 900)
	root.size = Vector2i(1600, 900)
	continued.surface.tabs.current_tab = 1
	await process_frame
	await process_frame
	await _screenshot("region_1600_seed82002.png")
	continued.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bad"))
	var evidence := {"checks": checks, "failures": failures, "samples": samples,
		"engine": Engine.get_version_info(), "processor": OS.get_processor_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"note": "Script-driven UI and native save tests, not unassisted human play. Native JSON precision comparison."}
	var file := FileAccess.open(output + "/surface_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "  "))
	file.close()
	print("WORLD_DEMO_EVIDENCE " + ProjectSettings.globalize_path(output))
	print("WORLD_DEMO_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _settle(viewer: Variant) -> int:
	var frames := 0
	var deadline := Time.get_ticks_msec() + 120000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
	_check(not viewer.busy, "bounded worker completion")
	if viewer.busy:
		quit(1)
		return frames
	_check(viewer.last_operation.result.get("success", false), "formal operation succeeds: " + str(viewer.last_operation.method))
	var sample: Dictionary = viewer.last_operation.duplicate()
	sample.erase("view")
	sample.erase("result")
	sample["ui_frames"] = frames
	samples.append(sample)
	await process_frame
	return frames


func _route_to(model: Variant, destination: String) -> String:
	for route: Dictionary in model.session.get_travel_options():
		if route.get("to_location_id", "") == destination:
			return str(route.route_id)
	_check(false, "route offered to " + destination)
	return ""


func _signature(model: Variant) -> String:
	var envelope: Dictionary = model.session.build_save_envelope()
	return _native({"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states, "world_log": envelope.world_log})


func _signature_from_save(source: String) -> String:
	var model := Live.new()
	model.load_from_path(source)
	return _signature(model)


func _native(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, false)), "", true, false)


func _screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output + "/" + filename) == OK, "render saved: " + filename)


func _check(condition: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)
