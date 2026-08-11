extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const GRANARY_OUTBOUND := "old_chen_shop_to_abandoned_granary"
const GRANARY_RETURN := "abandoned_granary_to_old_chen_shop"
const GRANARY_PREPARE := "prepare_granary_entry"
const GRANARY_ENTER := "enter_abandoned_granary"
const ECHO_OPTION := "show_granary_measure_token_to_chen_mi"
const INVESTIGATE_OPTION := "investigate_public_granary_seal_records"
const READ_TAX_DEED := "read_visible_readable_object:old_chen_public_granary_tax_deed"
const NORTH_QUAY_OUTBOUND := "old_chen_shop_to_north_quay_record_house"
const ARCHIVE_PREPARE := "prepare_flooded_archive_search"
const ARCHIVE_SEARCH := "search_flooded_archive_stack"
const EXPEDITION_PREPARE := "prepare_mist_salt_well_expedition"
const WELL_OUTBOUND := "north_quay_record_house_to_mist_salt_well"
const WELL_RETURN := "mist_salt_well_to_north_quay_record_house"
const WELL_DESCENT := "descend_mist_salt_well_second_ring"
const WELL_TRACE_ACTION := (
	"inspect_visible_trace:mist_salt_well_mouth_crust"
)
const WELL_WARNING_ACTION := (
	"read_visible_readable_object:mist_salt_well_warning_stone"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Mist salt expedition surface loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var location_title := viewer.get_node("%LocationTitle") as Label
	var location_context := viewer.get_node("%LocationContext") as Label
	var location_description := (
		viewer.get_node("%LocationDescription") as RichTextLabel
	)
	var time_label := viewer.get_node("%TimeLabel") as Label
	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var chronicle_heading := viewer.get_node("%ChronicleHeading") as Label
	var chronicle_text := viewer.get_node("%ChronicleText") as RichTextLabel
	var risk_heading := viewer.get_node("%RiskHeading") as Label
	var risk_text := viewer.get_node("%RiskText") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	_complete_archive_record(viewer.view_model.session)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var blocked_route := _find_travel_button(
		travel_buttons,
		WELL_OUTBOUND
	)
	var prepare_button := _find_challenge_button(
		action_buttons,
		EXPEDITION_PREPARE
	)
	_check(
		location_title.text == "北埠旧档房"
		and "第 2 天　10:00" in time_label.text
		and blocked_route != null
		and blocked_route.disabled
		and "雾盐旧井" in blocked_route.text
		and "6 小时 / 2 食物" in blocked_route.text
		and "防盐面罩" in blocked_route.tooltip_text,
		"2. The discovered well route is visible but honestly blocked"
	)
	_check(
		prepare_button != null
		and "帮闻简晒卷" in prepare_button.text
		and "2小时" in prepare_button.text
		and "四份" not in player_summary.text
		and not risk_heading.visible,
		"3. Archive work appears as preparation instead of a fake danger check"
	)

	prepare_button.pressed.emit()
	await process_frame
	await process_frame
	blocked_route = _find_travel_button(
		travel_buttons,
		WELL_OUTBOUND
	)
	_check(
		"第 2 天　12:00" in time_label.text
		and feedback_title.text == "用两小时换一段远路"
		and "不肯白送" in feedback_body.text
		and "随身食物 +4" in feedback_body.text
		and "蜡布防盐面罩" in feedback_body.text,
		"4. Preparation feedback explains labor, supplies, gear, and time"
	)
	_check(
		"食物　5 份" in player_summary.text
		and "蜡布防盐面罩" in player_summary.text
		and blocked_route != null
		and not blocked_route.disabled
		and _find_challenge_button(
			action_buttons,
			EXPEDITION_PREPARE
		) == null,
		"5. Prepared inventory enables travel and cannot be collected twice"
	)

	blocked_route.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "雾盐旧井"
		and "第 2 天　18:00" in time_label.text
		and "城外荒野" in location_context.text
		and "地下遗构" in location_context.text
		and "异象区域" in location_context.text
		and "向地下盘绕" in location_description.text,
		"6. Expedition arrives at a distinct wilderness and subterranean place"
	)
	_check(
		"井口断裂的旧警石" in observations.text
		and "井口朝水弯曲的盐壳白丝" in observations.text
		and "通往第二环的盐白石阶" in observations.text,
		"7. The well shows a warning, a testable rule, and a deeper route"
	)
	_check(
		not risk_heading.visible,
		"8. Deeper risk stays hidden until the player reads the evidence"
	)

	var trace_button := _find_action_button(
		action_buttons,
		WELL_TRACE_ACTION
	)
	var descend_button := _find_challenge_button(
		action_buttons,
		WELL_DESCENT
	)
	var return_button := _find_travel_button(
		travel_buttons,
		WELL_RETURN
	)
	_check(
		trace_button != null
		and descend_button == null
		and return_button == null
		and "试探盐壳白丝" in trace_button.text,
		"9. Arrival presents the evidence before the consequential choices"
	)

	trace_button.pressed.emit()
	await process_frame
	await process_frame
	var warning_button := _find_action_button(
		action_buttons,
		WELL_WARNING_ACTION
	)
	descend_button = _find_challenge_button(
		action_buttons,
		WELL_DESCENT
	)
	return_button = _find_travel_button(
		travel_buttons,
		WELL_RETURN
	)
	_check(
		"白丝便一根根朝囊口抬起" in feedback_body.text
		and "你检查过井口朝水弯曲的盐壳白丝" in knowledge.text
		and return_button != null
		and not return_button.disabled
		and descend_button == null
		and warning_button != null,
		"10. Inspecting the mouth gives information and unlocks cautious return"
	)

	warning_button.pressed.emit()
	await process_frame
	await process_frame
	descend_button = _find_challenge_button(
		action_buttons,
		WELL_DESCENT
	)
	_check(
		risk_heading.visible
		and "眼前的风险　不可逆" in risk_heading.text
		and "不能按普通伤势处理" in risk_text.text
		and "d20 + 感知 10 / 难度 23" in risk_text.text
		and descend_button != null,
		"10a. Reading the warning reveals the irreversible descent risk"
	)

	var deep_result: Dictionary = viewer.view_model.perform_challenge(
		WELL_DESCENT,
		{"source": "test_injection", "roll_override": 13}
	)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		bool(deep_result.get("success", false))
		and str(deep_result.get("outcome", "")) == "success"
		and "第 2 天　20:00" in time_label.text
		and feedback_title.text == "逆着渗水弯曲的白丝"
		and "长期痕迹：雾盐回响·微弱" in feedback_body.text
		and "逆水白丝样本" in feedback_body.text,
		"11. Deep success visibly grants evidence without hiding its cost"
	)
	_check(
		"长期痕迹　雾盐回响·微弱" in player_summary.text
		and "逆水白丝样本" in player_summary.text
		and "第二环扶壁上的秤纹" in observations.text
		and not risk_heading.visible,
		"12. Player and scene surfaces retain echo, sample, and marker"
	)
	_check(
		"井下白丝朝水而生" in chronicle_heading.text
		and "仍然没有答案" in chronicle_text.text
		and "普通伤势消失" in chronicle_text.text
		and "依据 6 条事实、1 件物品" in chronicle_text.text,
		"13. Chronicle presents observation, cost, and unresolved fate together"
	)
	_check(
		"亲眼看见井下白丝" in knowledge.text
		and "仍不知道他后来去了哪里" in knowledge.text
		and "不会随普通伤势消失" in knowledge.text,
		"14. Knowledge uses observed and unknown language instead of false certainty"
	)

	return_button = _find_travel_button(
		travel_buttons,
		WELL_RETURN
	)
	return_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "北埠旧档房"
		and "第 3 天　02:00" in time_label.text
		and "长期痕迹　雾盐回响·微弱" in player_summary.text
		and "逆水白丝样本" in player_summary.text,
		"15. Returning to the archive preserves the expedition's long tail"
	)

	viewer.restart_session()
	await process_frame
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "第 1 天　10:00" in time_label.text
		and "长期痕迹" not in player_summary.text
		and "蜡布防盐面罩" not in player_summary.text
		and _find_travel_button(
			travel_buttons,
			WELL_OUTBOUND
		) == null,
		"16. Restart clears the complete expedition surface"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _complete_archive_record(session: Variant) -> void:
	session.travel(GRANARY_OUTBOUND)
	session.execute_challenge_option(GRANARY_PREPARE)
	session.execute_challenge_option(
		GRANARY_ENTER,
		{"source": "test_injection", "roll_override": 3}
	)
	session.travel(GRANARY_RETURN)
	session.execute_return_echo_option(ECHO_OPTION)
	session.execute_investigation_option(INVESTIGATE_OPTION)
	session.execute_action(READ_TAX_DEED)
	session.advance_time(6, "wait_for_north_quay_ferry")
	session.travel(NORTH_QUAY_OUTBOUND)
	session.execute_challenge_option(ARCHIVE_PREPARE)
	session.execute_challenge_option(
		ARCHIVE_SEARCH,
		{"source": "test_injection", "roll_override": 1}
	)


func _find_travel_button(container: Node, route_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("route_id", "")) == route_id:
			return child as Button
	return null


func _find_action_button(container: Node, action_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == action_id:
			return child as Button
	return null


func _find_challenge_button(
		container: Node,
		option_id: String
) -> Button:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("challenge_option_id", ""))
				== option_id
		):
			return child as Button
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 MIST SALT WELL EXPEDITION SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(
			"[V5 MIST SALT WELL EXPEDITION SURFACE FAIL] " + failure
		)
	print(
		"[V5 MIST SALT WELL EXPEDITION SURFACE RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 MIST SALT WELL EXPEDITION SURFACE PASS] " + message)
	else:
		failures.append(message)
