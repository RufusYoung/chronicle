extends "res://tests/rebuild/roaming_player_render_test.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/situation_surface_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "situation_render_test"
	root.add_child(viewer)
	await settled(viewer)
	check(viewer.response.observation.situation_mode, "new default is the situation prototype")
	check(viewer.agent.model.session.fixture_source_data.journey_rules.events.is_empty(), "renderer consumes zero story nodes")
	var waits: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.get("intent") == "wait" and c.minutes == 10)
	check(not waits.is_empty(), "in-place wait on a location without interactions")
	viewer._begin("act", {"choice_id": waits[0].choice_id})
	await settled(viewer)
	check(not viewer.pending_result, "ordinary wait does not open a blocking result page")
	check(viewer._story.find_child("InlineOutcome", true, false) != null, "immediate inline consequence visible")
	check(viewer._status.text.contains("10:10"), "existing clock continues to display minutes after actual morning history")
	var subjects: Array = viewer.response.observation.situations
	if not subjects.is_empty():
		var questions: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool:
			return c.get("intent") == "ask" and c.subject_id == subjects[0].subject_id)
		if not questions.is_empty():
			await act(viewer, questions[0])
			check(not viewer.pending_result, "ordinary question stays on scene")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer._render()
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= viewport_size.y, "whole prototype fits " + str(viewport_size))
		await capture("scene_" + str(viewport_size.x))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var routes: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel" and ".network." in str(c.id))
	await act(viewer, routes[0])
	while viewer.response.observation.player.travel_remaining > 0:
		await act(viewer, viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.id == "continue")[0])
	check(not viewer.pending_result, "arrival does not demand an extra continue click")
	for page: String in ["scene", "map", "talk", "trade", "rest", "work", "inventory", "character", "journal"]:
		viewer._navigate(page)
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= root.size.y, "prototype page fits 720p " + page)
		await capture(page + "_720")
	viewer._begin("save", {"slot": viewer.slot, "overwrite": true})
	await settled(viewer)
	var saved: Dictionary = viewer.response.observation.time.duplicate(true)
	viewer._begin("load", {"slot": viewer.slot})
	await settled(viewer)
	check(viewer.response.ok and viewer.response.observation.time == saved, "UI native load preserves situation time")
	check(viewer.before_view.is_empty(), "load clears stale prior-action feedback")
	if "--saved-situation" in OS.get_cmdline_user_args():
		await saved_situation(viewer)
	viewer.queue_free()
	await process_frame
	print("SITUATION_SURFACE_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func act(viewer: Variant, choice: Dictionary) -> void:
	viewer._begin("act", {"choice_id": choice.choice_id, "confirm": true})
	await settled(viewer)
	check(viewer.response.ok, "legal UI action " + str(choice.label))


func saved_situation(viewer: Variant) -> void:
	viewer._begin("load", {"slot": "situation_interest_81001"})
	await settled(viewer)
	check(viewer.response.ok, "load an actual legal-play situation, not an injected scene")
	var funds: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.get("intent") == "fund")
	check(not funds.is_empty(), "natural heard request offers a real use of own coins")
	if funds.is_empty():
		return
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer._navigate("scene")
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= viewport_size.y, "natural situation fits " + str(viewport_size))
		await capture("natural_request_" + str(viewport_size.x))
	var coins: int = viewer.response.observation.player.coins
	await act(viewer, funds[0])
	check(viewer.response.observation.player.coins == coins - int(funds[0].amount), "UI spends actual money in the saved natural situation")
	check(not viewer.pending_result, "funding does not add a continue gate")
	check(viewer.response.choices.any(func(c: Dictionary) -> bool: return c.get("intent") == "fund" and str(c.label).begins_with("再资助")), "further voluntary funding is clearly distinguished from the completed gift")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	viewer._render()
	await process_frame
	await process_frame
	check(viewer._root.get_global_rect().end.y <= root.size.y, "natural funding feedback fits 720p")
	await capture("natural_funding_720")
