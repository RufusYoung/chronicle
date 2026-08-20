extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const REED_BAY_OUTPUT := "user://tests/v5_network_reed_bay.png"
const ROUTE_PRESSURE_OUTPUT := "user://tests/v5_network_route_pressure.png"
const RIVER_STEPS_OUTPUT := "user://tests/v5_network_river_steps.png"
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
	_check(packed != null, "1. 正式地点界面可以载入三聚落网络")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var start: Dictionary = viewer.view_model.session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	var tick: Dictionary = viewer.view_model.session.advance_time(
		24,
		"settlement_network_render",
		{"scope_type": "global", "scope_id": ""}
	)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var location_title := viewer.get_node("%LocationTitle") as Label
	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var goal_summary := viewer.get_node("%GoalSummary") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	_check(
		bool(start.get("success", false))
		and bool(tick.get("success", false))
		and int(tick.get("network_event_count", 0)) > 0,
		"2. 三聚落网络启动并在一天内形成可展示的货流"
	)
	_check(
		"苇岸埠" in location_title.text
		and "聚落人口" in region_status.text
		and "苇湾鱼群" in region_status.text
		and "相邻聚落" in region_status.text
		and "石渡坞" in region_status.text
		and "最近货流" in region_status.text
		and "日运力 5.0" in region_status.text,
		"3. 苇岸埠面板显示本地人口、资源、邻居与最近货流"
	)
	_check(
		"道路已经产生真实货流" in goal_summary.text,
		"4. 试玩目标说明货流来自世界模拟而非预写事件"
	)
	await _save_viewport(REED_BAY_OUTPUT, "5. 苇岸埠网络截图已写入")

	var pressure_tick: Dictionary = {}
	for day_offset: int in range(1, 9):
		var candidate: Dictionary = viewer.view_model.session.advance_time(
			24,
			"settlement_network_pressure_render_day%d" % day_offset,
			{"scope_type": "global", "scope_id": ""}
		)
		if _has_local_route_pressure_event(
			candidate, viewer.view_model.session, "generated_settlement.reed_bay"
		):
			pressure_tick = candidate
			break
	_check(
		not pressure_tick.is_empty(),
		"6. 无测试注入等待时，苇岸埠相邻道路会自主出现环境压力"
	)
	if not pressure_tick.is_empty():
		viewer.view_model.latest_event_type = "world_tick"
		viewer.view_model.latest_result = pressure_tick.duplicate(true)
		viewer.refresh_view()
		await process_frame
		await process_frame
		var feedback_title := viewer.get_node("%FeedbackTitle") as Label
		var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
		_check(
			"道路受阻" in region_status.text
			and "有效日运力" in region_status.text
			and "受阻至第" in region_status.text,
			"7. 地点面板显示受阻道路、当前有效运力与结束日期"
		)
		_check(
			"道路通行受阻" in feedback_title.text
			and "预计持续" in feedback_body.text
			and "道路风险上升" in feedback_body.text,
			"8. 时间推进反馈说明事故成因、持续时间与机械影响"
		)
		await _save_viewport(
			ROUTE_PRESSURE_OUTPUT, "9. 自主道路压力截图已写入"
		)
	viewer.view_model.session.stores["fact_store"].add_fact({
		"fact_id": "fact.test_injection.household_migrated",
		"fact_type": "household_migrated",
		"actor_id": "generated_settlement.reed_bay",
		"target_id": "generated_settlement.river_steps",
		"source_settlement_id": "generated_settlement.reed_bay",
		"destination_settlement_id": "generated_settlement.river_steps",
		"member_ids": ["test_injection.person.01", "test_injection.person.02"],
		"summary": "测试注入的一户居民从苇岸埠迁往石渡坞。",
	})
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		"最近迁移" in region_status.text
		and "迁出 2 人" in region_status.text,
		"10. 测试注入的迁移事实会显示方向与整户人数"
	)

	var target_hub := "generated_location.river_steps.commons"
	var route_id := ""
	for option: Dictionary in viewer.view_model.session.get_travel_options():
		if str(option.get("to_location_id", "")) == target_hub:
			route_id = str(option.get("route_id", ""))
			break
	var route_button := _route_button_to(travel_buttons, route_id)
	_check(route_button != null, "11. 生成道路允许从苇岸埠前往石渡坞")
	if route_button != null:
		route_button.pressed.emit()
		await process_frame
		await process_frame
		_check(
			"石渡坞" in location_title.text
			and "河阶深土" in region_status.text
			and "苇岸埠" in region_status.text
			and "白坡坞" in region_status.text
			and "苇湾鱼群" not in region_status.text,
			"12. 抵达石渡坞后切换为当地资源和两侧邻接关系"
		)
		await _save_viewport(
			RIVER_STEPS_OUTPUT, "13. 石渡坞网络截图已写入"
		)

	viewer.queue_free()
	await process_frame
	_finish()


func _route_button_to(container: VBoxContainer, route_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("route_id", "")) == route_id:
			return child as Button
	return null


func _has_local_route_pressure_event(
		tick: Dictionary, session: Variant, settlement_id: String
) -> bool:
	var local_links: Dictionary = {}
	for link: Dictionary in session.get_settlement_network_summary().get(
		"links", []
	):
		if settlement_id in [
			str(link.get("settlement_a_id", "")),
			str(link.get("settlement_b_id", "")),
		]:
			local_links[str(link.get("link_id", ""))] = true
	for event: Dictionary in tick.get("network_events", []):
		if (
			str(event.get("event_type", ""))
			== "regional_route_pressure_started"
			and local_links.has(str(event.get("link_id", "")))
		):
			return true
	return false


func _save_viewport(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	_check(error == OK, label)
	if error == OK:
		print("[V5 SETTLEMENT NETWORK RENDER PATH] %s" % (
			ProjectSettings.globalize_path(path)
		))


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SETTLEMENT NETWORK RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 SETTLEMENT NETWORK RENDER RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SETTLEMENT NETWORK RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 SETTLEMENT NETWORK RENDER FAIL] %s" % label)
