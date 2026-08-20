extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const WorldTickAdapterModel = preload(
	"res://scripts/sim/world_tick/world_tick_adapter.gd"
)

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const SETTLEMENT_ID := "generated_settlement.river_steps"
const HUB_ID := "generated_location.river_steps.commons"
const ORGANIZATION_ID := (
	"runtime_organization.river_steps.provision_circle.cycle1"
)
const FORMATION_OUTPUT_PATH := (
	"user://tests/v5_organization_lifecycle_formation.png"
)
const RETIREMENT_OUTPUT_PATH := (
	"user://tests/v5_organization_lifecycle_retirement.png"
)
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
	_check(packed != null, "1. 正式地点界面可以载入组织生命周期场景")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var session = SimSessionModel.new()
	viewer.view_model.session = session
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	viewer.view_model.start_result = start.duplicate(true)
	var adapter = WorldTickAdapterModel.new()
	adapter.configure_organization_runtime(
		session.world_tick_adapter.organization_runtime_config
	)
	_check(
		bool(start.get("success", false)),
		"2. 组织生命周期渲染使用正式生成网络会话"
	)

	_inject_food_level(session, false)
	_apply_tick(adapter, session, 1, "formation_day1")
	var formation_result := _apply_tick(
		adapter, session, 2, "formation_day2"
	)
	session.context.set_current_location(HUB_ID)
	viewer.view_model.latest_event_type = "world_tick"
	viewer.view_model.latest_result = formation_result.duplicate(true)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	_check(
		"石渡坞临时共食会" in region_status.text
		and "共食执事" in region_status.text
		and "仓储见证人" in region_status.text
		and "组织成立" in region_status.text,
		"3. 正式面板显示动态组织、两个真实职位及成立状态"
	)
	_check(
		"石渡坞临时共食会成立" in feedback_title.text
		and "持续粮压" in feedback_body.text
		and "2 名当地居民" in feedback_body.text,
		"4. 行动反馈直接说明压力原因和实际创始人数"
	)
	await _save_viewport(
		FORMATION_OUTPUT_PATH, "5. 动态组织成立截图已写入"
	)

	_inject_food_level(session, true)
	_apply_tick(adapter, session, 3, "recovery_day1")
	var retirement_result := _apply_tick(
		adapter, session, 4, "recovery_day2"
	)
	viewer.view_model.latest_result = retirement_result.duplicate(true)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		"组织退场" in region_status.text
		and "结束临时职责" in region_status.text
		and "任职 2 · 石渡坞临时共食会" not in region_status.text,
		"6. 退场原因进入正式面板，退场组织不再显示为当前组织"
	)
	_check(
		"石渡坞临时共食会结束职责" in feedback_title.text
		and "粮压连续缓解" in feedback_body.text
		and str(session.stores["entity_store"].get_entity(
			ORGANIZATION_ID
		).get("lifecycle_status", "")) == "retired",
		"7. 正式反馈和实体真值一致展示软退场"
	)
	await _save_viewport(
		RETIREMENT_OUTPUT_PATH, "8. 动态组织退场截图已写入"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _apply_tick(
	adapter: Variant, session: Variant, day: int, source: String
) -> Dictionary:
	return adapter.apply_tick_event(session.context, session.stores, {
		"tick_event_id": "render.organization_lifecycle.%s.day%d" % [source, day],
		"tick_type": "test_event",
		"trigger_key": "render_organization_lifecycle",
		"scope_type": "global",
		"scope_id": "",
		"source": "v5_organization_lifecycle_render_test",
		"label": "组织生命周期渲染测试注入",
		"day": day,
		"hour": 8,
		"elapsed_hours": 0,
		"include_due_checks": false,
	})


func _inject_food_level(session: Variant, full: bool) -> void:
	for stock: Dictionary in session.stores[
		"resource_stock_store"
	].list_stocks():
		if (
			str(stock.get("settlement_id", "")) != SETTLEMENT_ID
			or "food" not in (stock.get("tags", []) as Array)
		):
			continue
		session.stores["resource_stock_store"].apply_resource_change({
			"operation": "set",
			"stock_id": str(stock.get("stock_id", "")),
			"amount": float(stock.get("capacity", 0.0)) if full else 0.0,
			"tick": 0,
			"reason": "render_test_injection_food_full" if full else "render_test_injection_food_empty",
		})


func _save_viewport(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	_check(error == OK, label)
	if error == OK:
		print("[V5 ORGANIZATION LIFECYCLE RENDER PATH] %s" % (
			ProjectSettings.globalize_path(path)
		))


func _finish() -> void:
	if failures.is_empty():
		print("[V5 ORGANIZATION LIFECYCLE RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 ORGANIZATION LIFECYCLE RENDER RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 ORGANIZATION LIFECYCLE RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 ORGANIZATION LIFECYCLE RENDER FAIL] %s" % label)
