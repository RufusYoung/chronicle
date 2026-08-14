extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_site_fixture.json"
)
const HUB_OUTPUT := "user://tests/v5_generated_settlement_hub.png"
const FACILITY_OUTPUT := "user://tests/v5_generated_settlement_facility.png"
const SEED := 73001
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
	_check(packed != null, "1. 正式地点界面可以载入生成聚落")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var start: Dictionary = viewer.view_model.session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": SEED}
	)
	var report: Dictionary = start.get("settlement_generation", {})
	viewer.refresh_view()
	await process_frame
	await process_frame

	var brand_subtitle := viewer.get_node("%BrandSubtitle") as Label
	var location_title := viewer.get_node("%LocationTitle") as Label
	var location_context := viewer.get_node("%LocationContext") as Label
	var location_description := viewer.get_node("%LocationDescription") as RichTextLabel
	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var goal_title := viewer.get_node("%GoalTitle") as Label
	var goal_summary := viewer.get_node("%GoalSummary") as RichTextLabel
	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var travel_heading := viewer.get_node("%TravelHeading") as Label
	var travel_scroll := viewer.get_node("%TravelScroll") as ScrollContainer
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var visible_observations := viewer.get_node(
		"%VisibleObservations"
	) as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var viewport_size := root.get_visible_rect().size
	var settlement_name := str(report.get("settlement_name", ""))
	var capacity := int(report.get("resident_capacity", 0))
	var population := int(report.get("population_target", 0))

	_check(
		bool(start.get("success", false))
		and "生成聚落现场" in brand_subtitle.text
		and settlement_name in location_title.text
		and settlement_name in player_summary.text
		and "湖湾镇" not in player_summary.text
		and "生成地点" in location_context.text
		and "支撑约 %d 人" % capacity in location_description.text,
		"2. 页眉与地点正文显示当前生成结果，不再误写成湖湾镇剧情"
	)
	_check(
		goal_title.text == "认识这座生成聚落"
		and "地形、资源与交通" in goal_summary.text
		and "粮食压力" in region_status.text
		and "交通隔绝" in region_status.text
		and "水患风险" in region_status.text,
		"3. 目标和压力面板解释这座聚落为何形成及当前约束"
	)
	_check(
		settlement_name in knowledge.text
		and "可长期支撑约 %d 人" % capacity in knowledge.text
		and "初始人口目标为 %d 人" % population in knowledge.text,
		"4. 知识面板提供容量与人口关键信息，而不是只有生成结论"
	)
	_check(
		action_buttons.get_child_count() == 1
		and "查看" in (action_buttons.get_child(0) as Button).text,
		"5. 生成集地提供可执行的现场检查，不再显示零项空行动区"
	)
	_check(
		travel_buttons.get_child_count() == (
			report.get("industry_ids", []) as Array
		).size()
		and travel_buttons.get_child_count() >= 4
		and travel_scroll.get_v_scroll_bar().visible
		and _inside_viewport(travel_scroll.get_global_rect(), viewport_size),
		"6. 多设施旅行列表在 1280x720 内使用局部滚动，不挤掉其他信息"
	)
	await _save_viewport(HUB_OUTPUT, "7. 生成聚落集地截图已写入")

	var first_button := travel_buttons.get_child(0) as Button
	var route_id := str(first_button.get_meta("route_id", ""))
	first_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		not route_id.is_empty()
		and "生成聚落现场" in brand_subtitle.text
		and goal_title.text == "查看产业如何占据地点"
		and "因地形成" in location_context.text
		and settlement_name in visible_observations.text
		and feedback_title.text == "聚落里的短路"
		and "居民反复走出的路" in feedback_body.text
		and action_buttons.get_child_count() == 1
		and travel_heading.text == "可以前往　1 处",
		"8. 点击生成道路后进入实际设施，并显示观察、行动、反馈和返回入口"
	)
	_check(
		"聚落内部一段由实际设施形成的道路" in knowledge.text
		and _inside_viewport(location_description.get_global_rect(), viewport_size)
		and _inside_viewport(visible_observations.get_global_rect(), viewport_size),
		"9. 旅行事实与设施内容在正式界面保持可读"
	)
	await _save_viewport(FACILITY_OUTPUT, "10. 生成设施截图已写入")

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


func _save_viewport(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	_check(error == OK, label)
	if error == OK:
		print("[V5 GENERATED SETTLEMENT RENDER PATH] %s" % ProjectSettings.globalize_path(
			path
		))


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED SETTLEMENT RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 GENERATED SETTLEMENT RENDER RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED SETTLEMENT RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 GENERATED SETTLEMENT RENDER FAIL] %s" % label)
