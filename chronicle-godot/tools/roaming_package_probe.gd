extends SceneTree
## Run with the console engine --main-pack <pck> --script <absolute harness path>.
## Pack-resource validation is separate from the standalone EXE startup probe.

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	check(not ResourceLoader.exists("res://tests/rebuild/roaming_player_render_test.gd"), "using exported pack without test resources")
	var scene: PackedScene = load("res://scenes/rebuild/roaming_player.tscn")
	var viewer = scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "roaming_package_probe_isolated"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.add_child(viewer)
	await settled(viewer)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--probe-slot="):
			viewer._begin("load", {"slot": argument.trim_prefix("--probe-slot=")})
			await settled(viewer)
	check(viewer.response.get("ok", false), "native startup/load succeeded")
	var initial_time: Dictionary = viewer.response.observation.time.duplicate(true)
	var output := "user://tests/roaming_package_probe"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for viewport: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = viewport
		root.content_scale_size = viewport
		for page: String in ["scene", "map", "inventory", "character", "journal", "trade", "rest"]:
			viewer._navigate(page)
			var total: int = viewer.response.observation.equipment_journal.items.size() if page == "inventory" else 1
			for offset: int in range(0, total, 2):
				viewer.offset = offset
				viewer._render()
				await process_frame
				await process_frame
				check(viewer._picture.texture != null, "packaged texture loaded")
				check(viewer._root.get_global_rect().end.y <= root.size.y, "packaged page fits " + page + str(offset))
				if page in ["scene", "inventory"]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(output + "/" + page + str(offset) + "_" + str(viewport.x) + ".png")
	check(viewer.response.observation.time == initial_time, "render/navigation leaves loaded time intact")
	print("ROAMING_PACKAGE_PROBE " + JSON.stringify({"ok": failures.is_empty(), "time": initial_time, "failures": failures, "renderer": RenderingServer.get_current_rendering_method()}))
	viewer.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func settled(viewer: Variant) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	await process_frame
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(not viewer.busy, "worker completed")
	await process_frame


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
