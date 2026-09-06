extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []
var output := "user://tests/household_life_render"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_livelihood_rules = true
	root.add_child(viewer)
	await process_frame
	_check(viewer.view_model.session.fixture_source_data.resident_daily_life.food_access.has("subsistence"), "actual UI new-world preset starts integrated rules")
	var s: Variant = viewer.view_model.session
	for destination: String in ["generated_location.echo_terrace.commons", "generated_location.echo_terrace.terraces"]:
		var route := ""
		for option: Dictionary in s.get_travel_options():
			if option.to_location_id == destination:
				route = option.route_id
		_check(route != "", "legal observer travel to " + destination)
		if route == "":
			break
		viewer.perform_travel(route)
		await _settle(viewer)
	var saw_foraging := false
	var saw_cargo := false
	for hour: int in range(48):
		viewer.wait_button.pressed.emit()
		await _settle(viewer)
		for person: Dictionary in viewer.current_view_data.visible_people:
			if "正在采食口粮" in str(person.state_text):
				_check(str(person.name) in viewer.surface.scene_record.text and "正在采食口粮" in viewer.surface.scene_record.text, "full scene record retains every resident's changed livelihood")
				if not saw_foraging and str(person.name) in viewer.visible_people.text and "正在采食口粮" in viewer.visible_people.text:
					saw_foraging = true
					await _capture("foraging")
			if "托运货包" in str(person.state_text):
				saw_cargo = true
		if saw_foraging and saw_cargo:
			break
	_check(saw_foraging, "natural need leads to visible adaptive work without NPC injection")
	_check(viewer.visible_people.get_content_height() <= viewer.visible_people.size.y + 2 and not viewer.visible_people.scroll_active, "visible residents are not clipped or placed behind an inner scrollbar")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "720p controls remain available")
	_check(s.validate_persistent_references().ok and s.action_count == 0, "program-driven legal observation preserves the world; not human play")
	_check(s.save_to_path(output + "/observed.json").ok, "save actual rendered world")
	var before_dialog: Dictionary = s.get_time_summary()
	viewer.restart_button.pressed.emit()
	await process_frame
	_check(viewer.restart_dialog.visible and viewer._livelihood_rules.button_pressed, "new-world form makes integrated rules explicit")
	await _capture("new_world")
	viewer.restart_dialog.get_cancel_button().pressed.emit()
	await process_frame
	_check(before_dialog == s.get_time_summary(), "inspecting new-world options does not advance or replace the current world")
	viewer.queue_free()
	await process_frame
	print("HOUSEHOLD_LIFE_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
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
