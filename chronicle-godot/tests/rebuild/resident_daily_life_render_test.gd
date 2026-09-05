extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array[String] = []
var output := "user://tests/resident_daily_life_render"


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
	_check(viewer.current_view_data.visible_people.is_empty(), "residents start at home, not preplaced for screenshot")
	for i: int in range(2):
		viewer.wait_button.pressed.emit()
		await _settle(viewer)
	_check(not viewer.current_view_data.visible_people.is_empty(), "waiting alone brings real residents through commons")
	_check("抵达" in viewer.visible_people.text, "arrival information is rendered")
	_check("抵达这里" in str(viewer.current_view_data.feedback.get("body", "")), "local arrival is prioritized over distant resource recovery")
	await _screenshot("commons_10am.png")
	var route_id := ""
	for route: Dictionary in viewer.view_model.session.get_travel_options():
		if str(route.to_location_id) == "generated_location.reed_bay.landing":
			route_id = str(route.route_id)
	viewer.perform_travel(route_id)
	await _settle(viewer)
	for i: int in range(2):
		viewer.wait_button.pressed.emit()
		await _settle(viewer)
	_check(viewer.current_view_data.location.id == "generated_location.reed_bay.landing", "traveler reaches workplace through legal route")
	_check("在岗做工" in viewer.visible_people.text, "same workers are visibly at work")
	_check("开始在这里做工" in str(viewer.current_view_data.feedback.get("body", "")), "local work transition has concrete feedback")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "people do not push action dock outside viewport")
	await _screenshot("landing_1pm.png")
	viewer.queue_free()
	await process_frame
	print("RESIDENT_DAILY_LIFE_RENDER_RESULT ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func _settle(viewer: Variant) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	if viewer.busy:
		# Join before closing to preserve worker ownership even on a failed test.
		viewer._worker.wait_to_finish()
		viewer._worker = null
		viewer.busy = false
		_check(false, "operation timeout")
	await process_frame
	_check(viewer.last_operation.get("result", {}).get("success", false), "UI operation succeeded")


func _screenshot(filename: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + filename)


func _check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)
