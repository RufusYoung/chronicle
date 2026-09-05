extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Demo.instantiate()
	viewer.save_path = "user://tests/canon_world/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	root.add_child(viewer)
	await process_frame
	_check(viewer.current_view_data.get("ready", false), "default world boots")
	if not viewer.current_view_data.get("region_map", {}).has("canon"):
		_check(false, "default entry must use original world")
	else:
		_check("回响之境" in viewer.brand_subtitle.text, "original world context visible on scene")
		viewer.surface.tabs.current_tab = 1
		await process_frame
		_check("回音港" in viewer._picture_caption.text and "尚未运行" in viewer._picture_caption.text, "atlas distinguishes geography from live simulation")
		_check(not viewer._picture.visible, "prototype art not reassigned to canon geography")
		_check(viewer._picture_caption.get_global_rect().end.y <= root.size.y, "all background fits without nested scrolling at 720p")
		_check(viewer._road_text.get_global_rect().end.y <= root.size.y, "route information fits 720p")
		await _capture("region")
		viewer.surface.tabs.current_tab = 0
		await process_frame
		var session: Variant = viewer.view_model.session
		var route := ""
		for option: Dictionary in session.get_travel_options():
			if option.to_location_id == "generated_location.echo_terrace.commons":
				route = option.route_id
		_check(route != "", "legal local route exists")
		viewer.perform_travel(route)
		var deadline := Time.get_ticks_msec() + 60000
		while viewer.busy and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(not viewer.busy and viewer.last_operation.get("result", {}).get("success", false), "legal UI travel succeeds")
		_check(viewer.view_model.session == session, "travel retains actual world instance")
		_check(viewer.current_view_data.region_map.current_settlement_id == "generated_settlement.echo_terrace", "arrival marker updated")
		_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "decisions fit after arrival")
		await _capture("arrival")
	viewer.queue_free()
	await process_frame
	print("CANON_WORLD_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func _capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests/canon_world"))
		root.get_texture().get_image().save_png("user://tests/canon_world/" + name + ".png")


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
