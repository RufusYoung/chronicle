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
const DISCOVERY_ITEM := "lake_town_granary_measure_token"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Returning relic echo surface loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var location_title := viewer.get_node("%LocationTitle") as Label
	var time_label := viewer.get_node("%TimeLabel") as Label
	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var receipt := viewer.get_node("%ResultReceipt") as RichTextLabel
	var history := viewer.get_node("%HistoryText") as RichTextLabel
	var chronicle_heading := viewer.get_node("%ChronicleHeading") as Label
	var chronicle_text := viewer.get_node("%ChronicleText") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	_check(
		not chronicle_heading.visible
		and _find_return_echo_button(
			action_buttons,
			ECHO_OPTION
		) == null,
		"2. Chronicle and recognition choice stay hidden at the initial shop"
	)

	_find_action_button(action_buttons, READ_NOTICE).pressed.emit()
	await process_frame
	_find_action_button(action_buttons, SHOP_TRACE).pressed.emit()
	await process_frame
	await process_frame
	_find_travel_button(
		travel_buttons,
		OUTBOUND_ROUTE
	).pressed.emit()
	await process_frame
	await process_frame
	_find_action_button(action_buttons, GRANARY_TRACE).pressed.emit()
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
	_check(
		location_title.text == "废弃粮仓"
		and "旧粮仓验粮铜牌" in player_summary.text
		and not chronicle_heading.visible
		and _find_return_echo_button(
			action_buttons,
			ECHO_OPTION
		) == null,
		"3. Finding the token does not fabricate a return chronicle"
	)

	_find_travel_button(
		travel_buttons,
		RETURN_ROUTE
	).pressed.emit()
	await process_frame
	await process_frame
	var echo_button := _find_return_echo_button(
		action_buttons,
		ECHO_OPTION
	)
	_check(
		location_title.text == "老陈铺子"
		and "23:00" in time_label.text
		and echo_button != null
		and "旧物" in echo_button.text
		and "陈米" in echo_button.tooltip_text,
		"4. Returning with the token exposes a clear NPC recognition action"
	)
	_check(
		not chronicle_heading.visible,
		"5. Chronicle remains absent until recognition actually resolves"
	)

	echo_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"第 2 天　00:00" in time_label.text
		and feedback_title.text == "铜牌背后的旧粮仓"
		and "霉粮被查出后封了门" in feedback_body.text,
		"6. Recognition takes an hour and gives concrete local-history feedback"
	)
	_check(
		"信任 +12" in feedback_body.text
		and "熟悉 +15" in feedback_body.text
		and "新线索" in receipt.text
		and "个人纪事新增" in receipt.text
		and "物品履历" in receipt.text,
		"7. Feedback exposes relationship, clue, chronicle, and item history"
	)
	_check(
		"陈米认出了你带回的旧粮仓验粮铜牌" in knowledge.text
		and "公仓曾在霉粮被查出后封闭" in knowledge.text,
		"8. Recognition and local history appear in confirmed knowledge"
	)
	_check(
		chronicle_heading.visible
		and chronicle_text.visible
		and "被认出的验粮铜牌" in chronicle_heading.text
		and "第2天00:00" in chronicle_text.text
		and "废弃粮仓" in chronicle_text.text
		and "依据 7 条事实、1 件物品" in chronicle_text.text,
		"9. Personal chronicle shows its real event and evidence count"
	)
	_check(
		"旧粮仓验粮铜牌" in player_summary.text
		and _find_return_echo_button(
			action_buttons,
			ECHO_OPTION
		) == null
		and "把验粮铜牌拿给陈米看" in history.text,
		"10. The token remains owned while the one-shot echo leaves the action list"
	)

	var session: Variant = viewer.view_model.session
	var item: Dictionary = session.get_snapshot().get_item(
		DISCOVERY_ITEM
	)
	_check(
		int(session.get_snapshot().get_relation(
			"chen_mi",
			"player",
			"trust",
			0
		)) == 12
		and (item.get("history", []) as Array).size() == 1
		and session.get_snapshot().get_player_chronicle_entries().size()
			== 1,
		"11. Visible response is backed by relationship, item, and chronicle stores"
	)

	viewer.restart_session()
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "10:00" in time_label.text
		and "食物　3 份" in player_summary.text
		and not chronicle_heading.visible
		and not chronicle_text.visible,
		"12. Restart clears the complete return echo surface"
	)

	viewer.queue_free()
	await process_frame
	_finish()


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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RETURNING RELIC ECHO SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 RETURNING RELIC ECHO SURFACE FAIL] " + failure)
	print(
		"[V5 RETURNING RELIC ECHO SURFACE RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 RETURNING RELIC ECHO SURFACE PASS] " + message)
	else:
		failures.append(message)
