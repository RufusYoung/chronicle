extends "res://tests/rebuild/work_framework_render_test.gd"


func _run() -> void:
	output = "user://tests/community_life_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_community_rules = true
	root.add_child(viewer)
	await process_frame
	_check(viewer.current_view_data.get("ready", false), "community world UI starts")
	_check(viewer.view_model.session.fixture_source_data.has("community_generated"), "explicit UI option reaches native community rules")
	_check(viewer._community_rules.button_pressed and not viewer._community_rules.disabled, "community control is available")
	_check("地方联络人" in JSON.stringify(viewer.current_view_data), "local organization has understandable membership information")
	await _capture("start")
	var witnessed := false
	for day: int in range(7):
		viewer._begin_operation("advance_time", [24])
		await _settle(viewer)
		var data: Dictionary = viewer.view_model._local_resident_activity_feedback(viewer.view_model.latest_result)
		if "从" in JSON.stringify(data) and "那里听说" in JSON.stringify(data):
			witnessed = true
			await _capture("conversation")
			break
	_check(witnessed, "autonomous locally heard message reaches UI feedback with its actual content")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "720p actions remain reachable")
	viewer.restart_dialog.popup_centered()
	await process_frame
	await _capture("new_world_options")
	_check(viewer.restart_dialog.size.y <= root.size.y, "new-world options fit supported height")
	viewer.restart_dialog.hide()
	viewer._work_rules.button_pressed = false
	_check(viewer._community_rules.disabled, "missing work dependency disables community option")
	_check(not viewer._world_options(81001, true, false, true).has("community_rules_version"), "disabled dependency cannot enable new behavior")
	_check(viewer.view_model.session.action_count == 0, "program-driven render did not inject NPC actions")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	await _capture("community_900")
	viewer.queue_free()
	await process_frame
	print("COMMUNITY_LIFE_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
