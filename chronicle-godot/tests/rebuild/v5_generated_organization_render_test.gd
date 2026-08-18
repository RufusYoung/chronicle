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
	_check(
		bool(start.get("success", false))
		and int(session.organization_generation_report.get(
			"organization_count", 0
		)) == 3,
		"2. 同一正式会话生成三个可展示组织"
	)
	_check(
		"当地组织" in region_status.text
		and "苇岸埠行路同业会" in region_status.text
		and "路货经办" in region_status.text
		and "路况见证人" in region_status.text
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

	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	for _hour: int in range(60):
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
		"6. 创始成员迁出后界面保留组织并把两个职位显示为空缺"
	)
	await _save_viewport(
		VACANCY_OUTPUT_PATH, "7. 白坡坞职位空缺截图已写入"
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
