extends SceneTree

const Scene = preload("res://scenes/rebuild/roaming_player.tscn")
var failures: Array = []
var output := "user://tests/roaming_player_render"


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Actual renderer required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Scene.instantiate()
	viewer.auto_load = false
	viewer.slot = "render_test_isolated"
	root.add_child(viewer)
	await settled(viewer)
	check(not viewer.response.is_empty(), "formal world ready")
	check(viewer._heading.text == "风从三条路上来", "single focal situation")
	check(viewer._picture.texture != null, "licensed pixel image visible")
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		viewer._render()
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= viewport_size.y, "whole UI fits " + str(viewport_size))
		check(viewer._choices.get_global_rect().end.y <= viewport_size.y - 50, "all initial choices visible")
		await capture("opening_" + str(viewport_size.x))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var offered = viewer._choices.get_child(0)
	check(offered.has_meta("choice_id"), "real choice button is bound")
	offered.pressed.emit()
	await settled(viewer)
	check(viewer.pending_result, "action opens persistent result, not another list")
	check(viewer._paragraph.text.contains("桥索"), "specific learned information shown immediately")
	check(viewer._status.text.contains("08:10"), "minute clock visible")
	await capture("result_1280")
	var hour: int = viewer.agent.model.session.elapsed_hours_since_start
	for page: String in ["map", "inventory", "character", "journal", "talk", "trade", "rest", "work", "scene"]:
		viewer._navigate(page)
		await process_frame
		await process_frame
		check(viewer._root.get_global_rect().end.y <= root.size.y, page + " fits 720p")
		await capture(page + "_1280")
	check(viewer.pending_result and viewer._paragraph.text.contains("桥索"), "reading another page does not discard result")
	check(viewer.agent.model.session.elapsed_hours_since_start == hour, "navigation does not run simulation")
	viewer._menu.popup_centered()
	await process_frame
	check(viewer._menu.size.y <= root.size.y, "help and sound fit 720p " + str(viewer._menu.size))
	viewer._menu.hide()
	viewer._ask("quit", "退出确认")
	check(viewer._discard_button.visible, "explicit quit without saving")
	viewer._dialog.hide()
	viewer._ask("load", "读取确认")
	check(not viewer._discard_button.visible, "load dialog does not offer destructive exit")
	viewer._dialog.hide()
	check(viewer._audio.play_count > 0 or viewer._audio.level == 0, "actual action sound or explicit user mute")
	viewer.queue_free()
	await process_frame
	print("ROAMING_PLAYER_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func settled(viewer: Variant) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 20000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(not viewer.busy, "worker finishes within 20s")
	await process_frame
	await process_frame


func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output + "/" + name + ".png")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
