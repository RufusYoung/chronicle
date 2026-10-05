extends "res://tests/rebuild/roaming_player_render_test.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/goal_pressure_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "goal_render_test"
	root.add_child(viewer)
	await settled(viewer)
	var selector: OptionButton = viewer._root.find_child("GoalSelector", true, false)
	check(selector != null, "actual default UI offers intent selection")
	var before: Dictionary = viewer.response.observation.time.duplicate(true)
	selector.item_selected.emit(1)
	await settled(viewer)
	check(not viewer.response.observation.goal_pressure.selected.is_empty(), "real selection callback sets intent")
	check(viewer.response.observation.time == before and not viewer.pending_result, "selection neither spends time nor opens continue gate")
	await act_id(viewer, "situation:ask:generated_resident.echo_landing.008:")
	await act_id(viewer, "generated_route.network.echo_shore_road.a_to_b")
	await act_id(viewer, "situation:ask:generated_resident.echo_terrace.006:")
	viewer._begin("set_goal", {"goal_id": "visit:generated_location.echo_terrace.terraces"})
	await settled(viewer)
	await act_id(viewer, "generated_route.echo_terrace.commons_to_terrace_farming")
	await act_id(viewer, "situation:follow:generated_resident.echo_terrace.008:generated_route.echo_terrace.terrace_farming_to_commons")
	await act_id(viewer, "situation:ask:generated_resident.echo_terrace.008:")
	await act_id(viewer, "situation:give:generated_resident.echo_terrace.008:item_instance.danger.worn_cloak")
	await act_id(viewer, "generated_route.echo_terrace.commons_to_reed_craft")
	check(viewer.response.observation.goal_pressure.pressure.contains("赠出"), "own sacrifice visible beside continuing goal")
	var promoted: Array = viewer.Presentation.build(viewer.response).choices.filter(func(c: Dictionary) -> bool: return c.id.begins_with("buy:") and int(c.get("goal_priority", 0)) > 0)
	check(not promoted.is_empty(), "actual alternate equipment offer reachable from scene")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer._navigate("scene")
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= viewport_size.y, "goal scene fits " + str(viewport_size))
		check(viewer._choices.get_global_rect().end.y <= viewport_size.y - 40, "primary alternatives visible " + str(viewport_size))
		await capture("goal_workshop_" + str(viewport_size.x))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	viewer._navigate("all")
	await process_frame
	await process_frame
	check(viewer._root.get_global_rect().end.y <= root.size.y, "more actions fits 720p")
	check(viewer.Presentation.build(viewer.response, "all").choices.size() == viewer.response.choices.size(), "nothing removed by goal focus")
	await capture("all_720")
	viewer._begin("set_goal", {"goal_id": ""})
	await settled(viewer)
	check(viewer.response.observation.goal_pressure.selected.is_empty(), "goal can be abandoned")
	viewer.queue_free()
	await process_frame
	print("GOAL_PRESSURE_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func act_id(viewer: Variant, id: String) -> void:
	var offered: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.id == id and c.enabled)
	check(not offered.is_empty(), "recorded natural action still legal " + id)
	if offered.is_empty():
		return
	viewer._begin("act", {"choice_id": offered[0].choice_id, "confirm": true})
	await settled(viewer)
	check(viewer.response.ok, "action settled " + id)
