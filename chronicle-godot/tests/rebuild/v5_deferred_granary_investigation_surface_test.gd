extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const READ_NOTICE := "read_visible_readable_object:old_chen_shop_price_notice"
const SHOP_TRACE := "inspect_visible_trace:gray_grain_powder"
const GRANARY_TRACE := "inspect_visible_trace:abandoned_granary_mold_trace"
const OUTBOUND_ROUTE := "old_chen_shop_to_abandoned_granary"
const RETURN_ROUTE := "abandoned_granary_to_old_chen_shop"
const PREPARE_OPTION := "prepare_granary_entry"
const ENTER_OPTION := "enter_abandoned_granary"
const ECHO_OPTION := "show_granary_measure_token_to_chen_mi"
const INVESTIGATE_OPTION := "investigate_public_granary_seal_records"
const DEFER_OPTION := "defer_public_granary_seal_records"
const LEAD_ID := "public_granary_seal_records"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Deferred investigation surface loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var time_label := viewer.get_node("%TimeLabel") as Label
	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var visible_people := viewer.get_node("%VisiblePeople") as RichTextLabel
	var observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var chronicle_heading := viewer.get_node("%ChronicleHeading") as Label
	var chronicle_text := viewer.get_node("%ChronicleText") as RichTextLabel
	var action_dock := viewer.get_node("%ActionDock") as PanelContainer
	var investigation_bar := viewer.get_node("%InvestigationBar") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var wait_button := viewer.get_node("%WaitButton") as Button

	_check(
		not investigation_bar.visible
		and _find_investigation_button(
			action_buttons,
			INVESTIGATE_OPTION
		) == null,
		"2. No investigation appears before the causal clue exists"
	)

	await _complete_return_echo(
		action_buttons,
		travel_buttons
	)
	await process_frame
	await process_frame
	var investigate_button := _find_investigation_button(
		action_buttons,
		INVESTIGATE_OPTION
	)
	var defer_button := _find_investigation_button(
		action_buttons,
		DEFER_OPTION
	)
	_check(
		investigation_bar.visible
		and action_dock.custom_minimum_size.y == 174.0
		and "调查方向　公仓封存记录" in investigation_bar.text
		and "等待决定" in investigation_bar.text,
		"3. Token recognition opens a visible investigation direction"
	)
	_check(
		investigate_button != null
		and defer_button != null
		and action_buttons.get_child(0) == investigate_button
		and action_buttons.get_child(1) == defer_button
		and "追查" in investigate_button.text
		and "3小时" in investigate_button.text
		and "生活" in defer_button.text
		and "1小时" in defer_button.text,
		"4. UI presents investigation and daily-life time choices together"
	)
	_check(
		"新的调查方向：公仓封存记录" in feedback_body.text
		and "旧税契" in investigation_bar.text,
		"5. Recognition feedback explains where the new choice came from"
	)

	defer_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"22:00" in time_label.text
		and feedback_title.text == "把旧事留到以后"
		and "没有消失" in feedback_body.text,
		"6. Deferring consumes an hour and confirms the lead remains"
	)
	_check(
		investigation_bar.visible
		and "已搁置，仍可追查" in investigation_bar.text
		and _find_investigation_button(
			action_buttons,
			DEFER_OPTION
		) == null
		and _find_investigation_button(
			action_buttons,
			INVESTIGATE_OPTION
		) != null,
		"7. Deferred state removes repeat defer but preserves investigation"
	)
	_check(
		"旧事：替你留着税契匣" in visible_people.text
		and "留到以后追查的旧事" in chronicle_heading.text
		and "第1天22:00" in chronicle_text.text,
		"8. Chen Mi stance and defer chronicle are visible in the scene"
	)

	wait_button.pressed.emit()
	await process_frame
	wait_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"第 2 天　00:00" in time_label.text
		and investigation_bar.visible
		and _find_investigation_button(
			action_buttons,
			INVESTIGATE_OPTION
		) != null,
		"9. Player can continue ordinary life while the lead persists"
	)

	investigate_button = _find_investigation_button(
		action_buttons,
		INVESTIGATE_OPTION
	)
	investigate_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"第 2 天　03:00" in time_label.text
		and feedback_title.text == "重新翻开的税契匣"
		and "一直留在柜台下" in feedback_body.text,
		"10. Resumed search consumes three hours and recalls the defer path"
	)
	_check(
		"信任 +4" in feedback_body.text
		and "熟悉 +5" in feedback_body.text
		and "陆槐" in feedback_body.text
		and "北埠旧档房" in feedback_body.text,
		"11. Search feedback exposes relationship and follow-up direction"
	)
	_check(
		"夹在税契里的公仓封印抄件" in observations.text
		and "陆槐" in observations.text
		and "北埠档房移存" in observations.text,
		"12. Investigation reveals a concrete readable record in the scene"
	)
	_check(
		"翻查过陈家保存的旧税契" in knowledge.text
		and "验粮吏陆槐与北埠旧档房" in knowledge.text
		and "旧事：和你查到深夜" in visible_people.text,
		"13. Facts and Chen Mi's resolved stance remain player-readable"
	)
	_check(
		not investigation_bar.visible
		and action_dock.custom_minimum_size.y == 174.0
		and _find_investigation_button(
			action_buttons,
			INVESTIGATE_OPTION
		) == null
		and "税契夹页上的名字" in chronicle_heading.text
		and "第2天03:00" in chronicle_text.text
		and "搁置线索后" in chronicle_text.text,
		"14. Resolved lead disappears and shows the resumed chronicle branch"
	)
	_check(
		"旧粮仓验粮铜牌" in player_summary.text
		and _history_has_label(
			viewer.view_model.action_history,
			"今晚先不翻税契"
		)
		and _history_has_label(
			viewer.view_model.action_history,
			"翻查陈家旧税契"
		),
		"15. Item and action history preserve both choices"
	)

	var session: Variant = viewer.view_model.session
	var lead: Dictionary = session.get_snapshot().get_investigation_lead(
		LEAD_ID
	)
	var item: Dictionary = session.get_snapshot().get_item(
		"lake_town_granary_measure_token"
	)
	_check(
		str(lead.get("status", "")) == "resolved"
		and bool(lead.get("resumed_after_defer", false))
		and session.get_snapshot().get_player_chronicle_entries().size()
			== 3
		and (item.get("history", []) as Array).size() == 2,
		"16. UI outcome is backed by lead, chronicle, and item stores"
	)

	viewer.restart_session()
	await process_frame
	_check(
		"第 1 天　10:00" in time_label.text
		and "随身物品　旅行口粮 ×3" in player_summary.text
		and not investigation_bar.visible
		and not chronicle_heading.visible,
		"17. Restart clears the complete investigation branch"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _complete_return_echo(
	action_buttons: Node,
	travel_buttons: Node
) -> void:
	_find_action_button(
		action_buttons,
		READ_NOTICE
	).pressed.emit()
	await process_frame
	_find_action_button(
		action_buttons,
		SHOP_TRACE
	).pressed.emit()
	await process_frame
	await process_frame
	_find_travel_button(
		travel_buttons,
		OUTBOUND_ROUTE
	).pressed.emit()
	await process_frame
	await process_frame
	_find_action_button(
		action_buttons,
		GRANARY_TRACE
	).pressed.emit()
	await process_frame
	await process_frame
	_find_challenge_button(
		action_buttons,
		PREPARE_OPTION
	).pressed.emit()
	await process_frame
	await process_frame
	_find_challenge_button(
		action_buttons,
		ENTER_OPTION
	).pressed.emit()
	await process_frame
	await process_frame
	_find_travel_button(
		travel_buttons,
		RETURN_ROUTE
	).pressed.emit()
	await process_frame
	await process_frame
	_find_return_echo_button(
		action_buttons,
		ECHO_OPTION
	).pressed.emit()
	await process_frame


func _find_action_button(container: Node, action_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == action_id:
			return child as Button
	return null


func _find_travel_button(container: Node, route_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("route_id", "")) == route_id:
			return child as Button
	return null


func _find_challenge_button(container: Node, option_id: String) -> Button:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("challenge_option_id", "")) == option_id
		):
			return child as Button
	return null


func _find_return_echo_button(
		container: Node,
		option_id: String
) -> Button:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("return_echo_option_id", ""))
				== option_id
		):
			return child as Button
	return null


func _find_investigation_button(
		container: Node,
		option_id: String
) -> Button:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("investigation_option_id", ""))
				== option_id
		):
			return child as Button
	return null


func _history_has_label(entries: Array, text: String) -> bool:
	for entry: Dictionary in entries:
		if text in str(entry.get("label", "")):
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 DEFERRED GRANARY INVESTIGATION SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 DEFERRED GRANARY INVESTIGATION SURFACE FAIL] " + failure)
	print(
		"[V5 DEFERRED GRANARY INVESTIGATION SURFACE RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 DEFERRED GRANARY INVESTIGATION SURFACE PASS] " + message)
	else:
		failures.append(message)
