extends "res://tests/rebuild/goal_pressure_render_test.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/wilderness_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "wilderness_render_isolated"
	root.add_child(viewer)
	await settled(viewer)
	check(viewer.response.observation.get("wilderness_version") == 1, "new GUI defaults to explicitly versioned wilderness")
	await act_id(viewer, "wilderness_route.generated_location.echo_landing.commons.wilderness_location.north_shore_breach")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer._navigate("scene")
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= root.size.y, "site fits " + str(root.size))
		check(viewer._paragraph.get_line_count() <= viewer._paragraph.max_lines_visible, "water and retreat not clipped " + str(root.size))
		await capture("arrival_" + str(root.size.x))
	await click_choice(viewer, "player_life/shore_survey:rubble")
	check(viewer.response.observation.wilderness.features[0].surveyed and not viewer.pending_result, "bound survey callback stays in scene")
	await act_id(viewer, "shore_survey:cleft")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	viewer._navigate("scene")
	await process_frame
	await process_frame
	check(viewer._root.get_global_rect().end.y <= root.size.y, "discovered-item groups fit 720p")
	check(viewer._paragraph.get_line_count() <= viewer._paragraph.max_lines_visible, "all known prospects and retreat fit main paragraph")
	await capture("surveyed_720")
	viewer._begin("set_goal", {"goal_id": "prepare_main_hand"})
	await settled(viewer)
	check(viewer._root.get_global_rect().end.y <= root.size.y, "selected equipment goal and wilderness fit together at 720p")
	var relevant: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("shore_take:") and int(c.get("goal_priority", 0)) > 0)
	check(relevant.size() == 4, "known main-hand prospects actually promoted for equipment goal")
	var primary: Array = viewer._choices.get_children().filter(func(n: Node) -> bool: return n is Button and n.text.begins_with("取回"))
	check(primary.size() == 2 and primary.all(func(n: Button) -> bool: return not n.text.contains("结绳带")), "equipment goal puts main-hand groups ahead of unrelated utility gear")
	if relevant.size() != 4:
		print("WILDERNESS_GOAL_DEBUG ", JSON.stringify(viewer.response.observation.goal_pressure))
	check(viewer._paragraph.get_line_count() <= viewer._paragraph.max_lines_visible, "selected goal does not clip water, goods or retreat")
	await capture("equipment_goal_720")
	viewer._begin("set_goal", {"goal_id": ""})
	await settled(viewer)
	var families: Array = viewer._choices.get_children().filter(func(n: Node) -> bool: return n is Button and n.text.begins_with("取回"))
	check(not families.is_empty(), "same item methods fold into one group")
	if not families.is_empty():
		families[0].pressed.emit()
		await process_frame
		await process_frame
		check(viewer._choices.get_children().any(func(n: Node) -> bool: return n is Button and str(n.get_meta("choice_id", "")).ends_with(":hand")), "group exposes actual bare-hand choice")
		check(viewer._choices.get_children().any(func(n: Node) -> bool: return n is Button and str(n.get_meta("choice_id", "")).ends_with(":rope")), "group exposes rope alternative and denial")
		check(viewer._root.get_global_rect().end.y <= root.size.y, "method comparison fits 720p")
		await capture("methods_720")
		var hands: Array = viewer._choices.get_children().filter(func(n: Node) -> bool: return n is Button and str(n.get_meta("choice_id", "")).ends_with(":hand") and not n.disabled)
		if not hands.is_empty():
			var time_before: Dictionary = viewer.response.observation.time.duplicate(true)
			hands[0].pressed.emit()
			await process_frame
			check(viewer._dialog.visible and viewer._dialog.dialog_text.contains("失败"), "real risk confirmation explains failure before spending time")
			check(viewer.response.observation.time == time_before, "opening risk confirmation is read only")
			await capture("risk_confirmation_720")
			viewer._dialog.hide()
			viewer._dialog.confirmed.emit()
			await settled(viewer)
			check(viewer.response.ok and viewer.response.observation.time != time_before, "confirmed UI choice executes formal world action")
			check(not viewer.pending_result and viewer._root.get_global_rect().end.y <= root.size.y, "risk outcome stays readable in scene without continue gate")
			await capture("outcome_720")
	viewer._navigate("map")
	await process_frame
	await process_frame
	check(viewer.Presentation.build(viewer.response, "map").choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel").size() == 2, "two exits remain accessible")
	await capture("exits_720")
	viewer.queue_free()
	await process_frame
	print("WILDERNESS_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func click_choice(viewer: Variant, id: String) -> void:
	var buttons: Array = viewer._choices.get_children().filter(func(n: Node) -> bool: return n is Button and n.get_meta("choice_id", "") == id)
	check(not buttons.is_empty(), "actual survey button visible")
	if not buttons.is_empty():
		buttons[0].pressed.emit()
		await settled(viewer)
