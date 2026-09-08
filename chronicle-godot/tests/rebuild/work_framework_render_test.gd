extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []
var output := "user://tests/work_framework_render"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	root.add_child(viewer)
	await process_frame
	_check(viewer.current_view_data.get("ready", false), "new world UI is ready")
	_check(viewer.view_model.session.fixture_source_data.has("work_rules"), "default new world and agent opt-in share work rules")
	_check(viewer._work_rules.button_pressed and not viewer._work_rules.disabled, "explicit new-world control is visible and usable")
	await _capture("start")
	var route := ""
	for option: Dictionary in viewer.view_model.session.get_travel_options():
		if option.to_location_id == "generated_location.echo_landing.work_shed":
			route = option.route_id
	_check(route != "", "observer has a legal route to workshop")
	viewer.perform_travel(route)
	await _settle(viewer)
	var observed := false
	for day: int in range(3):
		viewer._begin_operation("advance_time", [24])
		await _settle(viewer)
		var text := JSON.stringify(viewer.current_view_data, "", false)
		if "现场货柜" in text and "纤维绳索" in text and "耐久" in text:
			observed = true
			break
	_check(observed, "ordinary production is shown as actual nonfood inventory and durability")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "actions remain in 720p viewport")
	_check(viewer.view_model.session.action_count == 0, "no NPC action injected by the observer")
	await _capture("workshop")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "actions remain in 900p viewport")
	await _capture("workshop_900")
	viewer.queue_free()
	await process_frame
	print("WORK_FRAMEWORK_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func _settle(viewer: Variant) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not viewer.busy and viewer.last_operation.get("result", {}).get("success", false), "formal UI operation completed")
	await process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + label + ".png")


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
