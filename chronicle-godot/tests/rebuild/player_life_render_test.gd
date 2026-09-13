extends "res://tests/rebuild/work_framework_render_test.gd"


func _run() -> void:
	output = "user://tests/player_life_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_player_life = true
	root.add_child(viewer)
	await process_frame
	_check(viewer.view_model.session.fixture_source_data.has("player_life_generated"), "new world opts into physical player")
	_check("饥饿" in viewer.surface.situation.text and "铜币" in viewer.surface.situation.text, "decision-relevant body and money are visible")
	for button: Node in viewer.action_buttons.get_children():
		if button is Button:
			_check(not button.text.strip_edges().ends_with("取舍："), "no empty tradeoff caption on life actions")
	await _capture("start_720")
	viewer.restart_dialog.popup_centered()
	await process_frame
	_check(viewer.restart_dialog.size.x <= root.size.x and viewer.restart_dialog.size.y <= root.size.y, "new-world options fit 720p")
	await _capture("new_world_720")
	viewer.restart_dialog.hide()
	for route: Dictionary in viewer.view_model.session.get_travel_options():
		if "commons_to_fishery" in str(route.route_id):
			viewer.perform_travel(route.route_id)
			await _settle(viewer)
			break
	for index: int in range(3):
		if viewer.current_view_data.actions.any(func(row: Dictionary) -> bool: return row.action_id.begins_with("help:") and row.can_execute):
			break
		viewer.advance_time()
		await _settle(viewer)
	var clicked := false
	for button: Node in viewer.action_buttons.get_children():
		if button is Button and str(button.get_meta("action_id", "")).begins_with("help:"):
			_check("至多4小时" in button.text and "产物交给对方" in button.text, "work ownership and real duration are on the button")
			button.pressed.emit()
			await _settle(viewer)
			clicked = true
			break
	_check(clicked, "actual rendered work button invokes the formal action")
	_check(viewer.current_view_data.player.coins == 3, "rendered result uses real wage balance")
	_check("领取3枚实际铜币" in JSON.stringify(viewer.current_view_data.feedback), "feedback reports actual pay and goods")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "life controls fit 720p")
	await _capture("paid_work_720")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	await _capture("paid_work_900")
	var heard := false
	for hour: int in range(36):
		for button: Node in viewer.action_buttons.get_children():
			if button is Button and str(button.get_meta("action_id", "")).begins_with("inquire:"):
				button.pressed.emit()
				await _settle(viewer)
				heard = not viewer.current_view_data.get("player_life_followups", []).is_empty()
				break
		if heard:
			break
		viewer.advance_time()
		await _settle(viewer)
	_check(heard, "actual local conversation presents the downstream food use")
	_check("你先前补充的食物" in JSON.stringify(viewer.current_view_data.feedback), "result names the reported consequence rather than generic acknowledgement")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "followup controls remain visible")
	await _capture("known_followup_900")
	for route: Dictionary in viewer.view_model.session.get_travel_options():
		if "to_commons" in str(route.route_id):
			viewer.perform_travel(route.route_id)
			await _settle(viewer)
			break
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	await _capture("known_followup_commons_720")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "known aftermath plus multiple exits fits 720p")
	for route: Dictionary in viewer.view_model.session.get_travel_options():
		if ".network." in str(route.route_id):
			viewer.perform_travel(route.route_id)
			await _settle(viewer)
			break
	_check("路上" in viewer.current_view_data.location.title, "multi-hour travel is presented as being on the road")
	_check(viewer.current_view_data.visible_people.is_empty(), "no origin or destination NPCs are falsely shown as present")
	_check(viewer.current_view_data.actions.all(func(row: Dictionary) -> bool: return row.action_id in ["continue", "journey_block"]), "only physical journey continuation is offered in transit")
	await _capture("journey_900")
	viewer.queue_free()
	await process_frame
	print("PLAYER_LIFE_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
