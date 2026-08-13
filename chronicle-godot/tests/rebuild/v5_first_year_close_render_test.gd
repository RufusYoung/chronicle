extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_seventh_outpost_viewer.tscn"
const OUTPUT_PATH := "user://tests/v5_first_year_close_render.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(VIEWER_SCENE) as PackedScene
	if packed == null:
		_fail("viewer_scene_not_loaded")
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame
	var start: Dictionary = viewer.view_model.start({}, "first_year_close")
	viewer.refresh_view()
	await process_frame
	_check(bool(start.get("success", false)), "1. Render state opens the annual phase")
	var viewport_size := root.get_visible_rect().size
	var action_buttons := viewer.get_node("%ActionButtons") as Control
	var action_scroll := action_buttons.get_parent() as Control
	var people_text := viewer.get_node("%PeopleText") as Control
	var feedback_body := viewer.get_node("%FeedbackBody") as Control
	_check(
		viewport_size == Vector2(1280, 720)
		and _inside_viewport(action_scroll.get_global_rect(), viewport_size)
		and _inside_viewport(people_text.get_global_rect(), viewport_size)
		and _inside_viewport(feedback_body.get_global_rect(), viewport_size)
		and action_buttons.get_child_count() >= 4,
		"2. Monthly controls and core panels stay inside the 1280x720 viewport"
	)
	for unused: int in range(9):
		viewer.perform_duty("month_preserve_rations", {"incident_roll_override": 100})
		await process_frame
	await process_frame
	_check(
		str(viewer.get_node("%ActionHeading").text).contains("年末点名")
		and action_buttons.get_child_count() == 1
		and str((action_buttons.get_child(0) as Button).text).contains("完成年末点名"),
		"3. The year-end threshold summary leaves one explicit settlement action"
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"user://tests"
	))
	if DisplayServer.get_name() == "headless":
		print("[V5 FIRST YEAR RENDER SKIP] Dummy renderer has no readable texture")
	else:
		var texture: ViewportTexture = root.get_texture()
		var image: Image = texture.get_image()
		var error := image.save_png(OUTPUT_PATH)
		_check(error == OK, "4. Annual phase render screenshot is written")
		print("[V5 FIRST YEAR RENDER PATH] %s" % (
			ProjectSettings.globalize_path(OUTPUT_PATH)
		))
	viewer.queue_free()
	await process_frame
	_finish()


func _inside_viewport(rect: Rect2, viewport_size: Vector2) -> bool:
	return (
		rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= viewport_size.x
		and rect.end.y <= viewport_size.y
	)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 FIRST YEAR RENDER PASS] " + label)
		return
	failures.append(label)


func _fail(label: String) -> void:
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 FIRST YEAR RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 FIRST YEAR RENDER FAIL] " + failure)
	print("[V5 FIRST YEAR RENDER RESULT] FAIL (%d)" % failures.size())
	quit(1)
