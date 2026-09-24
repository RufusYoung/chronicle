extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Expected native UI checkpoint and output directory")
		quit(1)
		return
	var loaded := Saves.new().load_from_path(args[0])
	if not loaded.ok or loaded.envelope.stores.facts.any(func(f: Dictionary) -> bool: return f.get("fact_type") == "test_injection"):
		push_error("Expected a valid non-injected checkpoint")
		quit(1)
		return
	var output := ProjectSettings.globalize_path(args[1])
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Demo.instantiate()
	viewer.save_path = args[0]
	root.add_child(viewer)
	await process_frame
	await process_frame
	var checks := {"restored": viewer._startup_message.begins_with("已继续上次保存的世界。"),
		"hours": viewer.view_model.session.elapsed_hours_since_start == loaded.envelope.world_time.elapsed_hours,
		"layout_720": viewer.action_dock.get_global_rect().end.y <= root.size.y,
		"header_720": viewer.get_node("%WorldHeader").get_global_rect().position.y >= 0}
	var seen_routes: Array = []
	if viewer.surface.has("travel_paging"):
		var paging: Dictionary = viewer.surface.travel_paging
		for page: int in viewer.travel_buttons.get_child_count():
			for button: Button in viewer.travel_buttons.get_children():
				if button.visible and button.get_meta("route_id") not in seen_routes:
					seen_routes.append(button.get_meta("route_id"))
			if paging.next.disabled:
				break
			paging.next.pressed.emit()
		checks["all_routes_reachable"] = seen_routes.size() == viewer.travel_buttons.get_child_count()
		while not paging.previous.disabled:
			paging.previous.pressed.emit()
	await RenderingServer.frame_post_draw
	checks["scene_720"] = root.get_texture().get_image().save_png(output.path_join("scene_720.png")) == OK
	(viewer.get_node("%OpenResultReceipt") as LinkButton).pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	checks["record_720"] = root.get_texture().get_image().save_png(output.path_join("record_720.png")) == OK
	(viewer.get_node("%BackToScene") as Button).pressed.emit()
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	await RenderingServer.frame_post_draw
	checks["layout_900"] = viewer.action_dock.get_global_rect().end.y <= root.size.y
	checks["scene_900"] = root.get_texture().get_image().save_png(output.path_join("scene_900.png")) == OK
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	await process_frame
	await process_frame
	checks["resize_back_720"] = viewer.action_dock.get_global_rect().end.y <= root.size.y and viewer.get_node("%WorldHeader").get_global_rect().position.y >= 0
	var after: Dictionary = JSON.parse_string(JSON.stringify(viewer.view_model.session.build_save_envelope(), "", true, true))
	for key: String in ["stores", "world_time", "session", "rng_states", "world_log"]:
		checks["truth:" + key] = after[key] == loaded.envelope[key]
	var passed := checks.values().all(func(ok: bool) -> bool: return ok)
	var report := {"passed": passed, "checks": checks, "checkpoint": args[0], "hours": after.world_time.elapsed_hours,
		"visible_followups": viewer.current_view_data.player_life_followups,
		"scope": "Actual renderer of the supplied native checkpoint; this check performs no game action, injection or human UI play. Native world truth unchanged."}
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	viewer.queue_free()
	await process_frame
	print("LIFE_CHECKPOINT_RENDER_RESULT " + ("PASS" if passed else "FAIL"))
	quit(0 if passed else 1)
