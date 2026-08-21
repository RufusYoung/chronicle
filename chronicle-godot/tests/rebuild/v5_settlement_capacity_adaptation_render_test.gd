extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/generated_settlement_network_fixture.json"
)
const OUTPUT_PATH := "user://tests/v5_settlement_capacity_adaptation.png"
const CapacitySystemModel = preload(
	"res://scripts/sim/settlement/settlement_capacity_adaptation_system.gd"
)
const TransactionWorldWriterModel = preload(
	"res://scripts/sim/transaction/transaction_world_writer.gd"
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
	_check(packed != null, "1. 正式地点界面可以载入容量适应场景")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var session: Variant = viewer.view_model.session
	var start: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH, RULE_PATHS, {"challenge_seed_override": 81001}
	)
	var runtime: Dictionary = session.get_settlement_network_summary()
	var rules: Dictionary = runtime.get("capacity_adaptation", {}).duplicate(true)
	rules["housing_pressure_ratio_percent"] = 1
	rules["housing_pressure_days_required"] = 1
	rules["housing_construction_cooldown_days"] = 0
	rules["labor_pressure_days_required"] = 999999
	runtime["capacity_adaptation"] = rules
	var snapshot: Variant = session.snapshot_builder.build_snapshot(
		session.context, session.stores, true,
		{"day": 50, "hour": 8, "period": "morning"}
	)
	var data: Dictionary = CapacitySystemModel.new().resolve_daily_tick(
		snapshot, {"day": 50, "elapsed_hours": 1}, runtime,
		session.npc_livelihood_profiles, session.context.get_locations()
	)
	var applied := TransactionWorldWriterModel.new().apply_results(
		data.get("results", []), session.stores
	)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	_check(
		bool(start.get("success", false)) and applied,
		"2. 测试注入的持续住房压力通过正式容量事务建成住屋"
	)
	_check(
		"聚落扩建" in region_status.text
		and "住宅承载 +4" in region_status.text
		and "人口持续逼近承载上限" in region_status.text,
		"3. 左侧聚落状态显示扩建类型、容量增量与触发原因"
	)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	_check(error == OK, "4. 容量适应界面截图已写入")
	if error == OK:
		print("[V5 SETTLEMENT CAPACITY ADAPTATION RENDER PATH] %s" % (
			ProjectSettings.globalize_path(OUTPUT_PATH)
		))
	viewer.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SETTLEMENT CAPACITY ADAPTATION RENDER PASS] %s" % label)
		return
	failures.append(label)
	print("[V5 SETTLEMENT CAPACITY ADAPTATION RENDER FAIL] %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SETTLEMENT CAPACITY ADAPTATION RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	print("[V5 SETTLEMENT CAPACITY ADAPTATION RENDER RESULT] FAIL %d" % failures.size())
	quit(1)
