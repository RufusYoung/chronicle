extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"

const GIVE_FOOD := "give_food_to_hungry_person:chen_mi"
const READ_NOTICE := "read_visible_readable_object:old_chen_shop_price_notice"
const SHOP_TRACE := "inspect_visible_trace:gray_grain_powder"
const GRANARY_TRACE := "inspect_visible_trace:abandoned_granary_mold_trace"
const GRANARY_OUTBOUND := "old_chen_shop_to_abandoned_granary"
const GRANARY_RETURN := "abandoned_granary_to_old_chen_shop"
const GRANARY_PREPARE := "prepare_granary_entry"
const GRANARY_ENTER := "enter_abandoned_granary"
const ECHO_OPTION := "show_granary_measure_token_to_chen_mi"
const INVESTIGATE_OPTION := "investigate_public_granary_seal_records"
const READ_TAX_DEED := "read_visible_readable_object:old_chen_public_granary_tax_deed"
const REQUEST_CHEN_FAVOR := "request_favor_from_indebted_person:chen_mi"
const WAIT_FOR_FERRY := "wait_until_north_quay_ferry"
const NORTH_QUAY_OUTBOUND := "old_chen_shop_to_north_quay_record_house"
const ARCHIVE_RULES := "read_visible_readable_object:north_quay_visiting_rules"
const ARCHIVE_TIDE := "inspect_visible_trace:north_quay_tide_marks"
const ARCHIVE_PREPARE := "prepare_flooded_archive_search"
const ARCHIVE_SEARCH := "search_flooded_archive_stack"
const EXPEDITION_PREPARE := "prepare_mist_salt_well_expedition"
const WELL_OUTBOUND := "north_quay_record_house_to_mist_salt_well"
const WELL_RETURN := "mist_salt_well_to_north_quay_record_house"
const WELL_TRACE := "inspect_visible_trace:mist_salt_well_mouth_crust"
const WELL_WARNING := "read_visible_readable_object:mist_salt_well_warning_stone"
const WELL_DESCENT := "descend_mist_salt_well_second_ring"

var viewer: Control
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	viewer = (load(VIEWER_SCENE) as PackedScene).instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	_check(
		"食物　3 份" in _text("%PlayerSummary")
		and _find_button("%TravelButtons", "route_id", GRANARY_OUTBOUND) == null,
		"1. The first screen has safe resources and no premature granary shortcut"
	)
	_check(
		(viewer.get_node("%FeedbackBody") as Control).get_global_rect().end.y
			<= (viewer.get_node("%VisiblePeople") as Control).get_global_rect().position.y,
		"2. Immediate feedback sits above secondary scene details"
	)

	await _press_action(GIVE_FOOD)
	var log_count_after_gift: int = (
		viewer.view_model.session.get_world_log_entries().size()
	)
	_check(
		"食物　2 份" in _text("%PlayerSummary")
		and "戒备已经没有先前那么重" in _text("%FeedbackBody")
		and _find_button("%ActionButtons", "action_id", GIVE_FOOD) == null,
		"3. Giving food explains the result and removes the completed choice"
	)
	var stale: Dictionary = viewer.perform_action(GIVE_FOOD)
	_check(
		not bool(stale.get("success", true))
		and viewer.view_model.session.get_world_log_entries().size()
			== log_count_after_gift,
		"4. Repeating a completed choice cannot duplicate facts or history"
	)

	await _press_action(READ_NOTICE)
	await _press_action(SHOP_TRACE)
	var granary_button := _find_button(
		"%TravelButtons",
		"route_id",
		GRANARY_OUTBOUND
	)
	_check(
		granary_button != null
		and not granary_button.disabled
		and _find_button("%ActionButtons", "action_id", READ_NOTICE) == null
		and _find_button("%ActionButtons", "action_id", SHOP_TRACE) == null
		and "已经读过" in _text("%SceneDetailsRecord")
		and "已经检查" in _text("%VisibleObservations"),
		"5. Two specific observations unlock travel and then disappear"
	)

	await _press_travel(GRANARY_OUTBOUND)
	_check(
		"食物　1 份" in _text("%PlayerSummary")
		and _find_button("%TravelButtons", "route_id", GRANARY_RETURN) != null
		and _find_button(
			"%ActionButtons",
			"challenge_option_id",
			GRANARY_ENTER
		) == null,
		"6. The generous route reaches the granary without a return softlock"
	)
	await _press_action(GRANARY_TRACE)
	_check(
		"有人不久前搬过粮袋" in _text("%FeedbackTitle")
		and _find_button(
			"%ActionButtons",
			"challenge_option_id",
			GRANARY_ENTER
		) != null,
		"7. Reading the granary trace reveals its risk choices"
	)
	await _press_travel(GRANARY_RETURN)
	_check(
		_text("%LocationTitle") == "老陈铺子"
		and "食物　0 份" in _text("%PlayerSummary"),
		"8. A legal generous opening always permits the full round trip"
	)

	viewer.restart_session()
	await process_frame
	await process_frame
	await _press_action(GIVE_FOOD)
	await _press_action(READ_NOTICE)
	await _press_action(SHOP_TRACE)
	await _press_travel(GRANARY_OUTBOUND)
	await _press_action(GRANARY_TRACE)
	await _press_challenge(GRANARY_PREPARE)
	await _press_challenge(GRANARY_ENTER)
	await _press_travel(GRANARY_RETURN)
	await _press_echo(ECHO_OPTION)
	await _press_investigation(INVESTIGATE_OPTION)

	_check(
		_find_button("%ActionButtons", "action_id", READ_TAX_DEED) != null,
		"9. The revealed tax deed is offered as a readable clue"
	)
	await _press_action(READ_TAX_DEED)
	_check(
		"验粮吏陆槐" in _text("%FeedbackBody")
		and "北埠档房移存" in _text("%FeedbackBody")
		and "验粮吏陆槐" in _text("%KnowledgeText")
		and "已经读过" in _text("%SceneDetailsRecord")
		and _find_button("%ActionButtons", "action_id", READ_TAX_DEED) == null,
		"10. Reading exposes the actual clue, records it, and removes the choice"
	)

	await _press_action(REQUEST_CHEN_FAVOR)
	var log_count_after_favor: int = (
		viewer.view_model.session.get_world_log_entries().size()
	)
	_check(
		"去北埠的早船" in _text("%FeedbackTitle")
		and "06:00 至 18:00" in _text("%FeedbackBody")
		and _find_button("%ActionButtons", "action_id", REQUEST_CHEN_FAVOR) == null,
		"11. Chen Mi gives contextual Chinese help and the favor disappears"
	)
	var stale_favor: Dictionary = viewer.perform_action(REQUEST_CHEN_FAVOR)
	_check(
		not bool(stale_favor.get("success", true))
		and viewer.view_model.session.get_world_log_entries().size()
			== log_count_after_favor,
		"12. Re-clicking the spent favor cannot duplicate facts or history"
	)

	var ferry_button := _find_button(
		"%TravelButtons",
		"route_id",
		NORTH_QUAY_OUTBOUND
	)
	_check(
		int(viewer.view_model.session.get_time_summary().get("hour", -1)) == 6
		and ferry_button != null
		and not ferry_button.disabled
		and _find_button("%ActionButtons", "action_id", WAIT_FOR_FERRY) == null,
		"13. Earlier conversations consume time: by 06:00 the ferry opens without an extra waiting step"
	)
	var stale_wait: Dictionary = viewer.wait_until_north_quay_ferry()
	_check(
		not bool(stale_wait.get("success", true))
		and int(viewer.view_model.session.get_time_summary().get("hour", -1)) == 6,
		"14. Reusing the completed rest action cannot skip another day"
	)
	await _press_travel(NORTH_QUAY_OUTBOUND)

	_check(
		_find_button(
			"%ActionButtons",
			"challenge_option_id",
			ARCHIVE_SEARCH
		) == null,
		"15. The archive danger is hidden before its rules and tide are read"
	)
	await _press_action(ARCHIVE_RULES)
	await _press_action(ARCHIVE_TIDE)
	_check(
		_find_button(
			"%ActionButtons",
			"challenge_option_id",
			ARCHIVE_SEARCH
		) != null,
		"16. Archive evidence unlocks the preparation and danger choices"
	)
	await _press_challenge(ARCHIVE_PREPARE)
	await _press_challenge(ARCHIVE_SEARCH)
	await _press_challenge(EXPEDITION_PREPARE)
	await _press_travel(WELL_OUTBOUND)

	_check(
		_find_button("%TravelButtons", "route_id", WELL_RETURN) == null
		and _find_button(
			"%ActionButtons",
			"challenge_option_id",
			WELL_DESCENT
		) == null,
		"17. The well does not reveal consequences before the evidence"
	)
	var combat_retreat := _combat_option_id("retreat")
	await _press_combat(combat_retreat)
	_check(
		"掷骰" in _text("%FeedbackBody")
		and "耐久降至" in _text("%FeedbackBody")
		and "原来的三个选择已从行动栏撤下" in _text("%ResultReceipt")
		and viewer.view_model.session.get_combat_encounter_options().is_empty(),
		"17a. A real encounter explains its result and consumes every approach"
	)
	await _press_action(WELL_TRACE)
	_check(
		"白丝便一根根朝囊口抬起" in _text("%FeedbackBody")
		and _find_button("%TravelButtons", "route_id", WELL_RETURN) != null
		and _find_button(
			"%ActionButtons",
			"challenge_option_id",
			WELL_DESCENT
		) == null,
		"18. Testing the filaments gives information and unlocks return"
	)
	await _press_action(WELL_WARNING)
	_check(
		_find_button(
			"%ActionButtons",
			"challenge_option_id",
			WELL_DESCENT
		) != null
		and (viewer.get_node("%RiskHeading") as Label).visible,
		"19. Reading the warning reveals the irreversible descent choice"
	)
	await _press_travel(WELL_RETURN)

	var history_count: int = viewer.view_model.action_history.size()
	_check(
		bool(viewer.current_view_data.get("playtest", {}).get("completed", false))
		and history_count >= 23
		and "档房的潮桩重新出现" in _text("%HistoryText"),
		"20. A UI-only successful run has a readable ending and at least 23 steps"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _press_action(action_id: String) -> void:
	await _press("%ActionButtons", "action_id", action_id)


func _press_challenge(option_id: String) -> void:
	await _press("%ActionButtons", "challenge_option_id", option_id)


func _press_combat(option_id: String) -> void:
	await _press("%ActionButtons", "combat_option_id", option_id)


func _combat_option_id(action_type: String) -> String:
	for option: Dictionary in viewer.view_model.session.get_combat_encounter_options():
		if (
			str(option.get("action_type", "")) == action_type
			and bool(option.get("can_execute", false))
		):
			return str(option.get("option_id", ""))
	return ""


func _press_echo(option_id: String) -> void:
	await _press("%ActionButtons", "return_echo_option_id", option_id)


func _press_investigation(option_id: String) -> void:
	await _press("%ActionButtons", "investigation_option_id", option_id)


func _press_travel(route_id: String) -> void:
	await _press("%TravelButtons", "route_id", route_id)


func _press(container_path: String, meta_key: String, meta_value: String) -> void:
	var button := _find_button(container_path, meta_key, meta_value)
	_check(
		button != null and not button.disabled,
		"Required button is available: %s" % meta_value
	)
	if button == null or button.disabled:
		return
	if container_path in ["%ActionButtons", "%TravelButtons"]:
		var next := viewer.get_node("%NextActions" if container_path == "%ActionButtons" else "%NextTravel") as Button
		var previous := viewer.get_node("%PreviousActions" if container_path == "%ActionButtons" else "%PreviousTravel") as Button
		while not previous.disabled:
			previous.pressed.emit()
		while not button.is_visible_in_tree() and not next.disabled:
			next.pressed.emit()
		for frame: int in 4:
			await process_frame
	_check(button.is_visible_in_tree(), "Choice is reachable on a visible page: %s" % meta_value)
	button.pressed.emit()
	for frame: int in 4:
		await process_frame
	var layout_errors: Array[String] = []
	_audit_layout(viewer, layout_errors)
	_check(layout_errors.is_empty(), "Layout after %s: %s" % [meta_value, "; ".join(layout_errors)])
	if not layout_errors.is_empty() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
		root.get_texture().get_image().save_png("user://tests/agency_route_%d.png" % failures.size())
	if DisplayServer.get_name() != "headless" and meta_value in [
		READ_TAX_DEED, ARCHIVE_TIDE, WELL_WARNING, WELL_RETURN]:
		var name: String = {READ_TAX_DEED: "tax_deed", ARCHIVE_TIDE: "archive_risk",
			WELL_WARNING: "well_risk", WELL_RETURN: "return"}[meta_value]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
		root.get_texture().get_image().save_png("user://tests/agency_playthrough_%s.png" % name)


func _audit_layout(node: Node, errors: Array[String]) -> void:
	if node is Control and not node.is_visible_in_tree():
		return
	if node is RichTextLabel:
		if node.scroll_active or node.get_content_height() > node.size.y + 2:
			errors.append("clipped_or_scroll:%s" % node.name)
	if node is RichTextLabel or node is Button:
		if not Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1).encloses(node.get_global_rect()):
			errors.append("outside_viewport:%s" % node.name)
	for child: Node in node.get_children():
		_audit_layout(child, errors)


func _find_button(
		container_path: String,
		meta_key: String,
		meta_value: String
) -> Button:
	for child: Node in viewer.get_node(container_path).get_children():
		if child is Button and str(child.get_meta(meta_key, "")) == meta_value:
			return child as Button
	return null


func _text(node_path: String) -> String:
	return str(viewer.get_node(node_path).get("text"))


func _finish() -> void:
	if failures.is_empty():
		print("[V5 PLAYTEST UX REGRESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 PLAYTEST UX REGRESSION FAIL] " + failure)
	print(
		"[V5 PLAYTEST UX REGRESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 PLAYTEST UX REGRESSION PASS] " + message)
	else:
		failures.append(message)
