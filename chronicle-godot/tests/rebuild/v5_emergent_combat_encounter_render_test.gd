extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const FIXTURE_PATH := (
	"res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const BOAR_ID := "mist_salt_well_brine_boar"
const BOAR_NEGOTIATE := "combat:mist_salt_well_brine_boar:negotiate"
const ENCOUNTER_OUTPUT := "user://tests/v5_emergent_brine_boar_encounter.png"
const RESULT_OUTPUT := "user://tests/v5_emergent_brine_boar_result.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. 多候选遭遇界面可以载入")
	if packed == null:
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var start: Dictionary = viewer.view_model.session.start_from_fixture_path(
		FIXTURE_PATH,
		RULE_PATHS,
		{"challenge_seed_override": 517}
	)
	_check(
		bool(start.get("success", false))
		and _reach_well(viewer.view_model.session),
		"2. 种子 517 的正式流程抵达雾盐旧井"
	)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var visible_observations := (
		viewer.get_node("%VisibleObservations") as RichTextLabel
	)
	var risk_text := viewer.get_node("%RiskText") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var wait_button := viewer.get_node("%WaitButton") as Button
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var knowledge_text := viewer.get_node("%KnowledgeText") as RichTextLabel
	var viewport_size := root.get_visible_rect().size
	_check(
		"盐壳獠豕" in visible_observations.text
		and "前蹄反复刨地" in risk_text.text
		and "筛出" not in risk_text.text
		and _all_combat_buttons(action_buttons, BOAR_ID),
		"3. 界面只显示被导演选中的野兽、证据和三个处理方式"
	)
	_check(
		wait_button.disabled
		and travel_buttons.get_child_count() == 0
		and "先处理眼前的遭遇" in wait_button.tooltip_text,
		"4. 未解决遭遇会同时锁定等待和旅行"
	)
	_check(
		_inside_viewport(risk_text.get_global_rect(), viewport_size)
		and _children_inside(
			action_buttons,
			(action_buttons.get_parent() as Control).get_global_rect()
		),
		"5. 候选来源、风险和三个按钮在 1280x720 内完整显示"
	)
	await _save_viewport(ENCOUNTER_OUTPUT, "6. 野兽遭遇截图已写入")

	var result: Dictionary = viewer.perform_combat_encounter(
		BOAR_NEGOTIATE,
		{"source": "test_injection", "roll_override": 3}
	)
	await process_frame
	await process_frame
	_check(
		bool(result.get("success", false))
		and str(result.get("outcome", "")) == "success"
		and not wait_button.disabled
		and not _has_combat_button(action_buttons)
		and action_buttons.get_child_count() > 0
		and "盐壳獠豕" not in visible_observations.text
		and "掷骰 3 + 影响 10 = 13 / 难度 13" in feedback_body.text
		and "追着空粮袋的谷物气味离开了井口" in knowledge_text.text,
		"7. 结算后候选组消失、等待恢复并显示完整公式"
	)
	await _save_viewport(RESULT_OUTPUT, "8. 野兽结算截图已写入")

	viewer.queue_free()
	await process_frame
	_finish()


func _reach_well(session: Variant) -> bool:
	var results: Array[Dictionary] = [
		session.travel("old_chen_shop_to_abandoned_granary"),
		session.execute_challenge_option("prepare_granary_entry"),
		session.execute_challenge_option(
			"enter_abandoned_granary",
			{"source": "test_injection", "roll_override": 3}
		),
		session.travel("abandoned_granary_to_old_chen_shop"),
		session.execute_return_echo_option(
			"show_granary_measure_token_to_chen_mi"
		),
		session.execute_investigation_option(
			"investigate_public_granary_seal_records"
		),
		session.execute_action(
			"read_visible_readable_object:old_chen_public_granary_tax_deed"
		),
		session.advance_time(6, "wait_for_north_quay_ferry"),
		session.travel("old_chen_shop_to_north_quay_record_house"),
		session.execute_challenge_option("prepare_flooded_archive_search"),
		session.execute_challenge_option(
			"search_flooded_archive_stack",
			{"source": "test_injection", "roll_override": 1}
		),
		session.execute_challenge_option(
			"prepare_mist_salt_well_expedition"
		),
		session.travel("north_quay_record_house_to_mist_salt_well"),
	]
	for result: Dictionary in results:
		if not bool(result.get("success", false)):
			return false
	return str(session.context.location_id) == "mist_salt_well"


func _all_combat_buttons(container: Node, encounter_id: String) -> bool:
	if container.get_child_count() != 3:
		return false
	for child: Node in container.get_children():
		if not child is Button:
			return false
		var option_id := str(child.get_meta("combat_option_id", ""))
		if not option_id.begins_with("combat:%s:" % encounter_id):
			return false
	return true


func _has_combat_button(container: Node) -> bool:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("combat_option_id", "")) != ""
		):
			return true
	return false


func _inside_viewport(rect: Rect2, viewport_size: Vector2) -> bool:
	return (
		rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= viewport_size.x
		and rect.end.y <= viewport_size.y
	)


func _children_inside(container: Control, visible_rect: Rect2) -> bool:
	for child: Node in container.get_children():
		if child is Control and not visible_rect.encloses(
			(child as Control).get_global_rect()
		):
			return false
	return true


func _save_viewport(path: String, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[V5 EMERGENT COMBAT RENDER SKIP] Headless texture unavailable")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"user://tests"
	))
	var image: Image = root.get_texture().get_image()
	_check(image.save_png(path) == OK, label)
	print("[V5 EMERGENT COMBAT RENDER PATH] %s" % (
		ProjectSettings.globalize_path(path)
	))


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 EMERGENT COMBAT RENDER PASS] " + message)
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 EMERGENT COMBAT RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 EMERGENT COMBAT RENDER FAIL] " + failure)
	print(
		"[V5 EMERGENT COMBAT RENDER RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)
