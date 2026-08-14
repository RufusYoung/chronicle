extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_site_fixture.json"
)
const HUB_OUTPUT := "user://tests/v5_dynamic_resource_hub.png"
const FACILITY_OUTPUT := "user://tests/v5_dynamic_resource_fishery.png"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. 正式地点界面可以载入动态资源聚落")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var fixture := _read_json(FIXTURE_PATH)
	fixture["challenge_seed"] = 73001
	var generation: Dictionary = fixture.get("settlement_generation", {})
	for resource: Dictionary in generation.get("resources", []):
		if "fish" in (resource.get("tags", []) as Array):
			resource["abundance"] = 1
			resource["reliability"] = 1
	var start: Dictionary = viewer.view_model.session.start_from_fixture_data(
		fixture, RULE_PATHS
	)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var goal_summary := viewer.get_node("%GoalSummary") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var visible_observations := viewer.get_node(
		"%VisibleObservations"
	) as RichTextLabel
	var report: Dictionary = start.get("settlement_generation", {})
	_check(
		bool(start.get("success", false))
		and "近岸鱼群" in region_status.text
		and "泽岸苇草" in region_status.text
		and "坡田地力" in region_status.text
		and "浅层卤水" in region_status.text
		and "每天约恢复" in region_status.text,
		"2. 集地状态面板直接显示各资源当前水位、容量与恢复速度"
	)
	_check(
		"资源水位会随生产与恢复继续变化" in goal_summary.text,
		"3. 试玩目标明确解释生产会消耗长期库存"
	)

	var feedback_tick: Dictionary = viewer.view_model.advance_time(8)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		bool(feedback_tick.get("success", false))
		and int(feedback_tick.get("livelihood_event_count", 0)) > 0
		and feedback_title.text != "一小时过去"
		and ("居民" in feedback_body.text or "生产" in feedback_body.text),
		"4. 等待跨过生产周期后，反馈区说明居民生产与资源变化"
	)

	var depletion_tick: Dictionary = viewer.view_model.session.advance_time(
		112,
		"dynamic_resource_render_depletion",
		{"scope_type": "global", "scope_id": ""}
	)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		bool(depletion_tick.get("success", false))
		and "近岸鱼群" in region_status.text
		and "不足以开工" in region_status.text
		and "迁离倾向" in region_status.text,
		"5. 低鱼量推进五日后，正式界面显示停工水位和迁离压力"
	)
	await _save_viewport(HUB_OUTPUT, "6. 动态资源集地截图已写入")

	var fishery_location := str((
		report.get("workplace_bindings", {}) as Dictionary
	).get("net_fisher", ""))
	var fishery_route_id := ""
	for option: Dictionary in viewer.view_model.session.get_travel_options():
		if str(option.get("to_location_id", "")) == fishery_location:
			fishery_route_id = str(option.get("route_id", ""))
			break
	var route_button: Button = _route_button_to(
		travel_buttons, fishery_route_id
	)
	_check(route_button != null, "7. 渔业设施仍可从集地到达")
	if route_button != null:
		route_button.pressed.emit()
		await process_frame
		await process_frame
		_check(
			"资源水位" in visible_observations.text
			and "近岸鱼群" in visible_observations.text
			and "不足以开工" in visible_observations.text,
			"8. 进入渔业设施后，现场对象显示具体鱼群水位和停工原因"
		)
		await _save_viewport(
			FACILITY_OUTPUT, "9. 动态资源渔业设施截图已写入"
		)

	viewer.queue_free()
	await process_frame
	_finish()


func _route_button_to(container: VBoxContainer, route_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta(
			"route_id", ""
		)) == route_id:
			return child as Button
	return null


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _save_viewport(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	_check(error == OK, label)
	if error == OK:
		print("[V5 DYNAMIC RESOURCE RENDER PATH] %s" % ProjectSettings.globalize_path(
			path
		))


func _finish() -> void:
	if failures.is_empty():
		print("[V5 DYNAMIC RESOURCE RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 DYNAMIC RESOURCE RENDER RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 DYNAMIC RESOURCE RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 DYNAMIC RESOURCE RENDER FAIL] %s" % label)
