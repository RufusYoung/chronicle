extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const OUTPUT_PATH := "user://tests/v5_settlement_absorption.png"
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
	_check(packed != null, "1. 正式地点界面可以载入迁入吸纳场景")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var session: Variant = SimSessionModel.new()
	viewer.view_model.session = session
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	viewer.view_model.start_result = start.duplicate(true)
	var runtime: Dictionary = session.get_settlement_network_summary()
	for link: Dictionary in runtime.get("links", []):
		link["capacity_per_day"] = 0.0
	session.settlement_network_runtime = runtime.duplicate(true)
	session.world_tick_adapter.configure_settlement_network(runtime)
	for _hour: int in range(60):
		session.advance_time(1, "settlement_absorption_render")

	var evaluations: Array = session.stores["fact_store"].find_facts_by_type(
		"migrant_absorption_evaluated"
	)
	var latest: Dictionary = evaluations.back() if not evaluations.is_empty() else {}
	var destination_id := str(latest.get("destination_settlement_id", ""))
	var destination_hub := _settlement_hub(runtime, destination_id)
	var location_changed: bool = session.context.set_current_location(
		destination_hub
	)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var goal_summary := viewer.get_node("%GoalSummary") as RichTextLabel
	var expected_member_count := int(latest.get("member_count", 0))
	var expected_reemployed_count := int(latest.get("reemployed_count", 0))
	_check(
		bool(start.get("success", false))
		and not evaluations.is_empty()
		and destination_hub != ""
		and location_changed,
		"2. 世界模拟自行产生迁徙吸纳并定位到目的聚落"
	)
	_check(
		"迁入安顿" in region_status.text
		and "%d 人入住" % expected_member_count in region_status.text
		and "%d 人就业" % expected_reemployed_count in region_status.text,
		"3. 区域面板显示真实入住人数与本地再就业人数"
	)
	_check(
		"真实住房容量与职业空缺" in goal_summary.text,
		"4. 试玩目标解释迁入家庭受住房和岗位约束"
	)
	await _save_viewport()

	viewer.queue_free()
	await process_frame
	_finish()


func _settlement_hub(runtime: Dictionary, settlement_id: String) -> String:
	for site: Dictionary in runtime.get("sites", []):
		if str(site.get("settlement_id", "")) == settlement_id:
			return str(site.get("hub_location_id", ""))
	return ""


func _save_viewport() -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	_check(error == OK, "5. 迁入吸纳界面截图已写入")
	if error == OK:
		print("[V5 SETTLEMENT ABSORPTION RENDER PATH] %s" % (
			ProjectSettings.globalize_path(OUTPUT_PATH)
		))


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SETTLEMENT ABSORPTION RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 SETTLEMENT ABSORPTION RENDER RESULT] FAIL %d" % failures.size())
	quit(1)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SETTLEMENT ABSORPTION RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 SETTLEMENT ABSORPTION RENDER FAIL] %s" % label)
