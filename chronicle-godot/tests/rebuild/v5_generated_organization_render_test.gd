extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const OUTPUT_PATH := "user://tests/v5_generated_organization_wind_pass.png"
const VACANCY_OUTPUT_PATH := (
	"user://tests/v5_generated_organization_wind_pass_vacancy.png"
)
const RESTAFFED_OUTPUT_PATH := (
	"user://tests/v5_generated_organization_wind_pass_restaffed.png"
)
const RESPONSE_OUTPUT_PATH := (
	"user://tests/v5_generated_organization_wind_pass_patrol.png"
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
	_check(packed != null, "1. 正式地点界面可以载入生成组织场景")
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
	viewer.refresh_view()
	await process_frame
	await process_frame

	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var location_title := viewer.get_node("%LocationTitle") as Label
	var brand_subtitle := viewer.get_node("%BrandSubtitle") as Label
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var history_text := viewer.get_node("%HistoryText") as RichTextLabel
	_check(
		bool(start.get("success", false))
		and int(session.organization_generation_report.get(
			"organization_count", 0
		)) == 3,
		"2. 同一正式会话生成三个可展示组织"
	)
	_check(
		"当地组织" in region_status.text
		and "苇岸埠共食会" in region_status.text
		and "共食执事" in region_status.text
		and "仓储见证人" in region_status.text
		and "生成区域现场" in brand_subtitle.text,
		"3. 苇岸埠面板显示组织目标、职位和真实成员"
	)

	var changed: bool = session.context.set_current_location(
		"generated_location.wind_pass.commons"
	)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		changed
		and "白坡坞" in location_title.text
		and "白坡坞守路队" in region_status.text
		and "守路领班" in region_status.text
		and "警讯值守" in region_status.text,
		"4. 白坡坞面板显示由防御高地与风险道路生成的守路队"
	)
	await _save_viewport(
		OUTPUT_PATH, "5. 白坡坞创始组织截图已写入"
	)
	viewer.view_model.advance_time(1)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"organization_route_patrolled"
		).size() == 1
		and "道路巡守" in region_status.text
		and "白坡坞守路队" in region_status.text
		and "道路巡守" in feedback_title.text
		and "风险降低 1 级" in feedback_body.text
		and "风险降低 1 级" in history_text.text,
		"6. 守路队消耗真实运力后的巡守行动与结果进入正式界面"
	)
	await _save_viewport(
		RESPONSE_OUTPUT_PATH, "7. 白坡坞组织巡守截图已写入"
	)

	session = SimSessionModel.new()
	viewer.view_model.session = session
	start = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	viewer.view_model.start_result = start.duplicate(true)
	session.context.set_current_location("generated_location.wind_pass.commons")

	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	for _hour: int in range(36):
		session.advance_time(1, "generated_organization_render_migration")
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"organization_position_vacated"
		).size() == 2
		and "空缺（原" in region_status.text
		and "空缺 2" in region_status.text
		and "守路领班" in region_status.text
		and "警讯值守" in region_status.text,
		"8. 创始成员迁出后界面保留组织并把两个职位显示为空缺"
	)
	await _save_viewport(
		VACANCY_OUTPUT_PATH, "9. 白坡坞职位空缺截图已写入"
	)

	for _hour: int in range(24):
		session.advance_time(1, "generated_organization_render_restaffing")
	viewer.refresh_view()
	await process_frame
	await process_frame
	var filled_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type("organization_position_filled")
	if filled_facts.size() != 1:
		print("[V5 ORGANIZATION RESTAFF DIAGNOSTIC] %s" % JSON.stringify({
			"filled": filled_facts,
			"evaluations": session.stores["fact_store"].find_facts_by_type(
				"organization_recruitment_evaluated"
			),
			"roles": _wind_pass_roles(session),
		}))
	_check(
		filled_facts.size() == 1
		and "任职 1 / 空缺 1" in region_status.text
		and "空缺 2" not in region_status.text
		and "守路领班" in region_status.text
		and "警讯值守" in region_status.text
		and "组织补位" in region_status.text
		and _has_staffing_pressure(session, 1),
		"10. 持续迁出只剩一名成年候选时补入一人，并保留一个空缺压力"
	)
	await _save_viewport(
		RESTAFFED_OUTPUT_PATH, "11. 白坡坞自主补位截图已写入"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _save_viewport(path: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	_check(error == OK, label)
	if error == OK:
		print("[V5 GENERATED ORGANIZATION RENDER PATH] %s" % (
			ProjectSettings.globalize_path(path)
		))


func _advance(session: Variant, hours: int, source: String) -> void:
	for _hour: int in range(hours):
		session.advance_time(1, source)


func _wind_pass_roles(session: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entity: Dictionary in session.stores["entity_store"].list_entity_rows():
		var entity_id := str(entity.get("id", ""))
		if (
			str(entity.get("type", "")) == "person"
			and str(session.stores["state_store"].get_state(
				entity_id, "settlement_id", ""
			)) == "generated_settlement.wind_pass"
		):
			rows.append({
				"id": entity_id,
				"age": session.stores["state_store"].get_state(
					entity_id, "age_years", 0
				),
				"role": session.stores["state_store"].get_state(
					entity_id, "institution_role", ""
				),
			})
	return rows


func _has_staffing_pressure(session: Variant, value: int) -> bool:
	for pressure: Dictionary in session.stores[
		"pressure_store"
	].list_pressures():
		if (
			str(pressure.get("pressure_type", ""))
			== "organization_staffing_need"
			and int(pressure.get("value", 0)) == value
		):
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GENERATED ORGANIZATION RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 GENERATED ORGANIZATION RENDER RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 GENERATED ORGANIZATION RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 GENERATED ORGANIZATION RENDER FAIL] %s" % label)
