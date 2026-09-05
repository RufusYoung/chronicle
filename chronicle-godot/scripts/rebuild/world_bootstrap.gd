extends Node


func _ready() -> void:
	if "--agent-stdio" in OS.get_cmdline_user_args():
		var driver = load("res://scripts/agent/agent_stdio_driver.gd").new()
		get_tree().quit(driver.run())
		return
	var scene := load("res://scenes/rebuild/world_demo.tscn") as PackedScene
	var viewer = scene.instantiate()
	var probe := "--startup-probe" in OS.get_cmdline_user_args()
	if probe:
		# Isolate diagnostics from the player's manual save, including failed probes.
		viewer.save_path = ("user://tests/world_runtime_probe/day7.json"
			if "--startup-probe-day7" in OS.get_cmdline_user_args()
			else "user://tests/startup_probe/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json")
	add_child(viewer)
	if probe:
		await _probe_first_frame(viewer)


func _probe_first_frame(viewer: Variant) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Startup UI probe requires a real renderer.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var continuing := "--startup-probe-day7" in OS.get_cmdline_user_args()
	var elapsed := int(viewer.view_model.session.get_time_summary().get("elapsed_hours", 0))
	var ok: bool = viewer.current_view_data.get("ready", false) and not viewer.busy
	ok = ok and not viewer.wait_button.disabled and (not continuing or elapsed >= 168)
	print("CHRONICLE_FIRST_CONTROLLABLE_FRAME " + JSON.stringify({"ok": ok,
		"renderer": RenderingServer.get_current_rendering_method(), "elapsed_hours": elapsed,
		"profile": "day7" if continuing else "initial", "save_path": viewer.save_path,
		"startup_message": viewer._startup_message, "save_exists": FileAccess.file_exists(viewer.save_path)}))
	get_tree().quit(0 if ok else 1)
