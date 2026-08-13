extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_seventh_outpost_viewer.tscn"
const OUTPUT_PATH := "user://tests/v5_second_year_reception_render.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(VIEWER_SCENE) as PackedScene
	if packed == null:
		failures.append("viewer_scene_not_loaded")
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame
	viewer.view_model.start({}, "first_year_close")
	for unused: int in range(9):
		viewer.perform_duty(
			"month_preserve_rations", {"incident_roll_override": 100}
		)
		await process_frame
	viewer.resolve_milestone()
	await process_frame
	var action_buttons := viewer.get_node("%ActionButtons") as Control
	_check(
		action_buttons.get_child_count() == 1
		and str((action_buttons.get_child(0) as Button).text).contains(
			"进入第二年接收"
		),
		"1. Resolved year-end UI leaves one explicit second-year entry button"
	)
	var entered: Dictionary = viewer.enter_second_year_reception()
	await process_frame
	var viewport_size := root.get_visible_rect().size
	var action_scroll := action_buttons.get_parent() as Control
	var people_text := viewer.get_node("%PeopleText") as Control
	var feedback_body := viewer.get_node("%FeedbackBody") as Control
	_check(
		bool(entered.get("success", false))
		and str(viewer.get_node("%Subtitle").text).contains("第二年")
		and str(viewer.get_node("%DayLabel").text).contains("第 1 / 3 周")
		and action_buttons.get_child_count() >= 2
		and _inside_viewport(action_scroll.get_global_rect(), viewport_size)
		and _inside_viewport(people_text.get_global_rect(), viewport_size)
		and _inside_viewport(feedback_body.get_global_rect(), viewport_size),
		"2. Second-year status, people, feedback, and action controls fit 1280x720"
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"user://tests"
	))
	if DisplayServer.get_name() == "headless":
		print("[V5 SECOND YEAR RENDER SKIP] Dummy renderer has no readable texture")
	else:
		var image: Image = root.get_texture().get_image()
		_check(
			image.save_png(OUTPUT_PATH) == OK,
			"3. Second-year reception screenshot is written"
		)
		print("[V5 SECOND YEAR RENDER PATH] %s" % ProjectSettings.globalize_path(
			OUTPUT_PATH
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
		print("[V5 SECOND YEAR RENDER PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SECOND YEAR RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SECOND YEAR RENDER FAIL] " + failure)
	print("[V5 SECOND YEAR RENDER RESULT] FAIL (%d)" % failures.size())
	quit(1)
