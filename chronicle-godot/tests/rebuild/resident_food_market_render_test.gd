extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []
var output := "user://tests/resident_food_market_render"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.initial_scenario = "generated_network"
	viewer.initial_seed = 81001
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	root.add_child(viewer)
	await process_frame
	var route := ""
	for option: Dictionary in viewer.view_model.session.get_travel_options():
		if str(option.to_location_id) == "generated_location.reed_bay.landing":
			route = str(option.route_id)
	_check(route != "", "legal workplace route exists")
	viewer.perform_travel(route)
	await _settle(viewer)
	var observed := false
	for hour: int in range(24):
		viewer.wait_button.pressed.emit()
		await _settle(viewer)
		var feedback: Dictionary = viewer.current_view_data.get("feedback", {})
		if "支付" in str(feedback.get("body", "")) and "食物已实际交到手中" in str(feedback.get("body", "")):
			observed = true
			_check("铜币" in str(feedback.body) and "鲜鱼" in str(feedback.body), "result includes actual goods and payment")
			_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "result leaves actions within 720p")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output + "/purchase.png")
			break
	_check(observed, "legal travel and waiting reveal autonomous food transaction in formal UI")
	_check(viewer.view_model.session.action_count == 0, "observer did not trigger NPC interaction")
	viewer.queue_free()
	await process_frame
	print("RESIDENT_FOOD_MARKET_RENDER_RESULT " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _settle(viewer: Variant) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	if viewer.busy:
		viewer._worker.wait_to_finish()
		viewer._worker = null
		viewer.busy = false
		_check(false, "operation timeout")
	await process_frame
	_check(viewer.last_operation.get("result", {}).get("success", false), "UI operation succeeded")


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
