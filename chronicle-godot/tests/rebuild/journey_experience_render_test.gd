extends "res://tests/rebuild/player_local_life_render_test.gd"


func _run() -> void:
	output = "user://tests/journey_experience_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_content_extension = true
	root.add_child(viewer)
	await process_frame
	_check(viewer._scene_picture.is_visible_in_tree(), "pixel art is visible in Scene without visiting Region")
	_check(viewer.action_buttons.get_child(0).get_meta("action_id", "").begins_with("travel:"), "first decision is a destination, not obligatory food or work")
	_check(viewer.action_buttons.get_children().any(func(b: Button) -> bool: return "废灯台" in b.text), "route choice has a concrete adventure purpose")
	_check(not viewer.action_buttons.get_children().any(func(b: Button) -> bool: return "路上人物、组织" in b.text), "route cards do not repeat a generic world-tick disclaimer")
	await _capture("arrival_720")
	var target := _prepare_market(viewer.view_model.session)
	viewer.refresh_view()
	await process_frame
	_check(viewer.view_model.session.stores.entity_store.get_entity(target).display_name in viewer._scene_people.text, "present test buyer is named on Scene")
	var asks: Array = viewer.current_view_data.actions.filter(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("ask_local:"))
	_check(asks.size() == 1, "only one orientation choice instead of repeated introductions")
	await _click_action(viewer, str(asks[0].action_id))
	_check(viewer._intent_family == "" and viewer.surface.action_filter == "", "completed conversation returns to main choices")
	_check("哨棚" in viewer.feedback_body.text and "答复" in viewer.feedback_title.text, "useful reply is visible directly, not only in full receipt")
	_check("08:10" in viewer.time_label.text, "clock visibly reports ten-minute action")
	_check(not viewer.current_view_data.actions.any(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("ask_local:")), "answered topic no longer offered")
	await _capture("answer_720")
	var sales: Array = viewer.current_view_data.actions.filter(func(r: Dictionary) -> bool: return str(r.action_id).begins_with("sell_food:" + target) and r.can_execute)
	_check(not sales.is_empty(), "funded reserve buyer has an actual sale button")
	if not sales.is_empty():
		await _click_action(viewer, str(sales[0].action_id))
		_check("收到" in viewer.feedback_title.text, "sale feedback immediately names the money received")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer.refresh_view()
		await process_frame
		_check(viewer.action_dock.get_global_rect().end.y <= viewport_size.y, "all decision controls fit " + str(viewport_size))
		_check(viewer.feedback_body.get_global_rect().end.y < viewer.action_dock.get_global_rect().position.y, "result is not hidden behind action dock")
		_check(not viewer.feedback_body.scroll_active, "result is not a tiny scrolling box")
		await _capture("sale_" + str(viewport_size.x))
	viewer.queue_free()
	await process_frame
	print("JOURNEY_EXPERIENCE_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
