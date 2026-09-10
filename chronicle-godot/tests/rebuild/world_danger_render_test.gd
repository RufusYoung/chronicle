extends "res://tests/rebuild/work_framework_render_test.gd"


func _run() -> void:
	output = "user://tests/world_danger_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_world_danger = true
	root.add_child(viewer)
	await process_frame
	_check(viewer.view_model.session.fixture_source_data.has("world_danger_generated"), "new-world checkbox enables the real danger world")
	viewer.restart_dialog.popup_centered()
	await process_frame
	await _capture("new_world")
	_check(viewer.restart_dialog.size.y <= root.size.y, "new-world options fit 720p")
	viewer.restart_dialog.hide()
	for hint: String in [".network.", "commons_to_terrace_farming"]:
		var route := ""
		for option: Dictionary in viewer.view_model.session.get_travel_options():
			if hint in str(option.route_id):
				route = str(option.route_id)
				break
		_check(route != "", "ordinary travel is available")
		viewer.perform_travel(route)
		await _settle(viewer)
	_check(viewer.current_view_data.risk.active, "physical arrival presents current threat")
	_check("身体状况" in JSON.stringify(viewer.current_view_data), "threat body and current advantage are visible")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "combat controls fit 720p")
	await _capture("contact_720")
	for approach: String in ["attack", "withdraw"]:
		var options: Array = viewer.view_model.session.get_combat_encounter_options()
		var choice: Dictionary = options.filter(func(row: Dictionary) -> bool: return row.approach_id == approach)[0]
		viewer.perform_combat_encounter(choice.option_id)
		await _settle(viewer)
		await _capture(approach + "_720")
	_check(not viewer.current_view_data.risk.active, "successful retreat restores ordinary options")
	var route: Dictionary = viewer.view_model.session.get_travel_options()[0]
	viewer.perform_travel(route.route_id)
	await _settle(viewer)
	_check(viewer.current_view_data.actions.any(func(row: Dictionary) -> bool: return row.get("event_type") == "recovery"), "injury offers a concrete recovery action")
	viewer.rest_for_recovery()
	await _settle(viewer)
	_check(viewer.current_view_data.player.food_count == 1, "rest consumes an actual portion")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "recovery controls fit 720p")
	await _capture("recovery_720")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	await _capture("recovery_900")
	viewer.queue_free()
	await process_frame
	print("WORLD_DANGER_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
