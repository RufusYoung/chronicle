extends "res://tests/rebuild/goal_pressure_render_test.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/journey_utility_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "utility_render_isolated"
	root.add_child(viewer)
	await settled(viewer)
	check(viewer.response.observation.journey_utility_version == 1, "new game uses explicitly versioned utility profile")
	viewer._begin("set_goal", {"goal_id": "visit:generated_location.echo_terrace.commons"})
	await settled(viewer)
	for page: String in ["scene", "map"]:
		viewer._navigate(page)
		await process_frame
		await process_frame
		check(viewer.Presentation.build(viewer.response, page).choices.any(func(c: Dictionary) -> bool: return c.id.begins_with("rush:")), "hurry reachable in actual " + page)
		check(viewer._root.get_global_rect().end.y <= root.size.y, "road alternatives fit 720p " + page)
		await capture("road_" + page)
	await act_id(viewer, "rush:generated_route.network.echo_shore_road.a_to_b")
	check(viewer.response.observation.time.hour == 12 and not viewer.pending_result, "real callback hurries without a continue gate")
	viewer._begin("set_goal", {"goal_id": "recover_energy"})
	await settled(viewer)
	viewer._navigate("scene")
	await process_frame
	await capture("tired_scene")
	# Controlled rendering fixture, not a natural guesthouse encounter.
	var session: Variant = viewer.agent.model.session
	var host: Dictionary = session.fixture_source_data.entities.filter(func(e: Dictionary) -> bool: return e.has("guesthouse_rules"))[0]
	var place := str(host.guesthouse_rules.location_id)
	var injection = preload("res://scripts/sim/transaction/transaction_result.gd").new()
	for id: String in [str(session.context.actor_id), str(host.id)]:
		injection.add_state_change({"entity_id": id, "key": "location_id", "to": place})
		injection.add_state_change({"entity_id": id, "key": "daily_route_id", "to": ""})
	injection.add_state_change({"entity_id": str(session.context.actor_id), "key": "fatigue", "to": 8})
	injection.mark_resolved("test_injection")
	check(session.writer.apply_result(injection, session.stores), "controlled host and fatigue for renderer")
	session.context.set_current_location(place)
	session.current_hour = 18
	viewer.agent._refresh()
	viewer._begin("observe")
	await settled(viewer)
	viewer._navigate("scene")
	await process_frame
	await process_frame
	check(viewer._choices.get_children().any(func(node: Node) -> bool: return node is Button and node.text.contains("借床休整")), "paid durations fold into one primary choice")
	check(viewer._choices.get_children().any(func(node: Node) -> bool: return node is Button and node.get_meta("choice_id", "") == "player_life/rest"), "free alternative is not displaced by three paid durations")
	await capture("bed_scene")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer._navigate("rest")
		viewer.family = "借床休整"
		viewer._render()
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= root.size.y, "duration picker fits " + str(root.size))
		check(viewer._choices.get_global_rect().end.y <= root.size.y - 40, "paid alternatives visible " + str(root.size))
		await capture("bed_" + str(root.size.x))
	await act_id(viewer, "service:bed:1")
	check(viewer.response.observation.feedback.body.contains("支付1铜币"), "paid outcome visible through actual UI action")
	check(not viewer.pending_result, "paid rest never forces continue gate")
	viewer.queue_free()
	await process_frame
	print("JOURNEY_UTILITY_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
