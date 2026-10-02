extends "res://tests/rebuild/situation_surface_render_test.gd"
## Renders actual saved hand-played states; it does not generate those outcomes.


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/situation_selfplay_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "selfplay_render_only"
	root.add_child(viewer)
	await settled(viewer)
	for slot: String in ["selfplay_20261002_empty_watch", "selfplay_20261002_field_contact", "selfplay_20261002_field_aftermath", "selfplay_20261002_returned"]:
		viewer._begin("load", {"slot": slot})
		await settled(viewer)
		check(viewer.response.ok, "actual stepwise-play native save loads: " + slot)
		if not viewer.response.ok:
			continue
		for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
			root.size = viewport_size
			root.content_scale_size = viewport_size
			for page: String in ["scene", "map", "talk", "rest", "journal"]:
				viewer._navigate(page)
				await process_frame
				await process_frame
				check(viewer._root.get_global_rect().end.y <= viewport_size.y, slot + " " + page + " fits " + str(viewport_size))
				if page == "scene" or (page == "map" and viewport_size.y == 720):
					await capture(slot + "_" + page + "_" + str(viewport_size.y))
	# Exercise actual Control callbacks on a naturally reached encounter.
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	viewer._begin("load", {"slot": "selfplay_20261002_field_contact"})
	await settled(viewer)
	var time_before: Dictionary = viewer.response.observation.time.duplicate(true)
	var guard: Button
	for child: Node in viewer._choices.get_children():
		if child is Button and str(child.get_meta("choice_id", "")).ends_with(":guard"):
			guard = child
	check(guard != null, "natural encounter has a visible defense button")
	if guard != null:
		guard.pressed.emit()
		await process_frame
		await process_frame
		check(viewer._dialog.visible and viewer._dialog.dialog_text.contains("进攻-1"), "defense confirmation discloses long-term downside")
		check(viewer._dialog.size.y < root.size.y, "growth warning confirmation fits 720p")
		await capture("defense_confirmation_720")
		viewer._dialog.get_cancel_button().pressed.emit()
		await process_frame
		check(not viewer._dialog.visible and viewer.response.observation.time == time_before, "cancelled defense does not spend time")
		guard.pressed.emit()
		await process_frame
		viewer._dialog.get_ok_button().pressed.emit()
		await settled(viewer)
		check(viewer.response.ok and viewer.response.observation.time.elapsed_hours == time_before.elapsed_hours + 1, "confirmed UI defense executes exactly once")
		check(not viewer.pending_result and viewer._story.find_child("InlineOutcome", true, false) != null, "actual UI action displays immediate inline result without continue gate")
		var inline_result: Label = viewer._story.find_child("InlineOutcome", true, false)
		check(not inline_result.text.begins_with("掷骰") and inline_result.text.contains("优势"), "the effect of defense precedes dice arithmetic on the actual UI")
		check(not viewer.agent.model.session.PlayerLife.Equipment.combat_growth_warning(viewer.agent.model.session, "guard").contains("进攻-1"), "acquired trait is not advertised as a new recurring penalty")
		await capture("defense_result_720")
	viewer.queue_free()
	await process_frame
	print("SELFPLAY_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
