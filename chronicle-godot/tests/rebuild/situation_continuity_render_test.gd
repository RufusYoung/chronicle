extends "res://tests/rebuild/situation_surface_render_test.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/situation_continuity_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "continuity_render_test"
	root.add_child(viewer)
	await settled(viewer)
	viewer._begin("load", {"slot": "situation_interest_v2_81001"})
	await settled(viewer)
	check(viewer.response.ok and viewer.response.observation.get("situation_continuity", false), "real legal-play checkpoint restores new knowledge rules")
	var gifts: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.get("intent") == "give" and c.has("clear_slots"))
	check(not gifts.is_empty(), "natural request allows sacrificing actual worn gear")
	if gifts.is_empty():
		viewer.queue_free()
		quit(1)
		return
	var gift: Dictionary = gifts[0]
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		for page: String in ["scene", "map", "talk", "trade", "rest", "journal"]:
			viewer._navigate(page)
			await process_frame
			await process_frame
			check(viewer._root.get_global_rect().end.y <= viewport_size.y, "natural continuity " + page + " fits " + str(viewport_size))
			await capture(page + "_" + str(viewport_size.x))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	viewer._navigate("trade")
	await process_frame
	await process_frame
	var button: Button = null
	for node: Node in viewer._choices.get_children():
		if node is Button and node.get_meta("choice_id", "") == gift.choice_id:
			button = node
	check(button != null and not button.disabled, "donation has an actual visible button")
	if button != null:
		button.pressed.emit()
		await process_frame
		check(viewer._dialog.visible and viewer._dialog.dialog_text.contains("失去"), "confirmation states loss of own protection")
		await capture("sacrifice_confirmation_720")
		viewer._confirm()
		viewer._dialog.hide()
		await settled(viewer)
	else:
		await act(viewer, gift)
	check(not viewer.pending_result, "donation returns directly to scene")
	check(viewer.response.observation.feedback.body.contains("防护"), "inline result explains lost protection")
	await capture("sacrifice_result_720")
	var heard := false
	for step: int in range(12):
		var next: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.enabled and c.get("intent") == "aftermath" and c.subject_id == gift.subject_id)
		if not next.is_empty():
			await act(viewer, next[0])
			heard = true
			break
		next = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.enabled and c.get("intent") == "follow" and c.subject_id == gift.subject_id)
		if next.is_empty():
			next = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.enabled and c.get("intent") == "wait" and c.minutes == 60)
		if next.is_empty():
			break
		await act(viewer, next[0])
	check(heard, "actual departure, following and later testimony reached through public actions")
	check(viewer._root.get_global_rect().end.y <= root.size.y, "follow-up remains on-screen at 720p")
	await capture("personal_followup_720")
	viewer.queue_free()
	await process_frame
	print("CONTINUITY_SURFACE_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
