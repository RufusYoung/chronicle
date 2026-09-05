extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []
var output := "user://tests/household_provisioning_render"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.initial_seed = 81001
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	root.add_child(viewer)
	await process_frame
	for destination: String in ["generated_location.echo_terrace.commons", "generated_location.echo_terrace.terraces"]:
		var route := ""
		for option: Dictionary in viewer.view_model.session.get_travel_options():
			if option.to_location_id == destination:
				route = option.route_id
		_check(route != "", "legal route to " + destination)
		if route == "":
			break
		viewer.perform_travel(route)
		await _settle(viewer)
	var saw_purchase := false
	var saw_return := false
	for hour: int in range(36):
		viewer.wait_button.pressed.emit()
		await _settle(viewer)
		var body := str(viewer.current_view_data.get("feedback", {}).get("body", ""))
		if "这批口粮准备带回给" in body:
			saw_purchase = true
			_check("高遥" in body or "高岑" in body, "purchase identifies who needs the goods")
			_check("铜币" in body and "耐寒块根" in body, "purchase reveals real goods and cost")
			await _capture("purchase")
		if saw_purchase and "带粮回家" in body:
			saw_return = true
			await _capture("return")
			break
	_check(saw_purchase and saw_return, "formal UI shows autonomous family purchase and purposeful departure")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "actions stay within 720p")
	_check(viewer.view_model.session.action_count == 0, "program-driven observer uses travel and wait, no NPC injection")
	_check(viewer.view_model.session.validate_persistent_references().ok, "observed world keeps valid references")
	viewer.queue_free()
	await process_frame
	print("HOUSEHOLD_PROVISIONING_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
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
	_check(viewer.last_operation.get("result", {}).get("success", false), "UI operation succeeds")


func _capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + name + ".png")


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
