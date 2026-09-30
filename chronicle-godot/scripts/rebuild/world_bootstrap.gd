extends Node


func _ready() -> void:
	if "--agent-stdio" in OS.get_cmdline_user_args():
		var driver = load("res://scripts/agent/agent_stdio_driver.gd").new()
		get_tree().quit(driver.run())
		return
	var legacy := "--legacy-world-viewer" in OS.get_cmdline_user_args()
	var scene := load("res://scenes/rebuild/world_demo.tscn" if legacy else "res://scenes/rebuild/roaming_player.tscn") as PackedScene
	var viewer = scene.instantiate()
	if legacy:
		viewer.initial_content_extension = true
	var probe := "--startup-probe" in OS.get_cmdline_user_args()
	var smoke := "--startup-smoke" in OS.get_cmdline_user_args()
	if (probe or smoke) and legacy:
		# Isolate diagnostics from the player's manual save, including failed probes.
		viewer.save_path = ("user://tests/world_runtime_probe/day7.json"
			if "--startup-probe-day7" in OS.get_cmdline_user_args()
			else "user://tests/startup_probe/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json")
	elif probe or smoke:
		var continuing := "--startup-probe-continued" in OS.get_cmdline_user_args()
		viewer.auto_load = continuing
		var prefix := "roaming" if "--authored-roaming" in OS.get_cmdline_user_args() else "situation"
		viewer.slot = prefix + ("_startup_continued" if continuing else "_startup_probe")
	add_child(viewer)
	if smoke:
		if legacy:
			await get_tree().process_frame
			get_tree().quit(0 if viewer.current_view_data.get("ready", false) and not viewer.busy else 1)
			return
		var deadline := Time.get_ticks_msec() + 30000
		while viewer.busy and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		get_tree().quit(0 if not viewer.busy and viewer.response.get("ok", false) else 1)
		return
	if probe:
		if legacy:
			await _probe_first_frame(viewer)
		else:
			await _probe_roaming(viewer)


func _probe_roaming(viewer: Variant) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Startup UI probe requires a real renderer.")
		get_tree().quit(1)
		return
	var deadline := Time.get_ticks_msec() + 30000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var ok: bool = not viewer.busy and viewer.response.get("ok", false) and viewer._picture.texture != null
	var elapsed: int = viewer.response.get("observation", {}).get("time", {}).get("elapsed_hours", 0)
	if "--startup-probe-continued" in OS.get_cmdline_user_args():
		ok = ok and elapsed > 2 and FileAccess.file_exists(viewer.Agent.SAVE_ROOT + "play/echo_realm/" + viewer.slot + ".json")
	var prototype: bool = viewer.response.get("observation", {}).get("situation_mode", false)
	var profile := "world_situation_v2" if viewer.response.get("observation", {}).get("situation_continuity", false) else ("world_situation_v1" if prototype else "world_roaming_v1")
	print("CHRONICLE_FIRST_CONTROLLABLE_FRAME " + JSON.stringify({"ok": ok, "elapsed_hours": elapsed, "surface": "roaming", "profile": profile, "renderer": RenderingServer.get_current_rendering_method()}))
	get_tree().quit(0 if ok else 1)


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
