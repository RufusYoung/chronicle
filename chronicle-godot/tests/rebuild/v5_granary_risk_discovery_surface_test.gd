extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const OUTBOUND_ROUTE := "old_chen_shop_to_abandoned_granary"
const RETURN_ROUTE := "abandoned_granary_to_old_chen_shop"
const PREPARE_OPTION := "prepare_granary_entry"
const ENTER_OPTION := "enter_abandoned_granary"
const DISCOVERY_ITEM := "lake_town_granary_measure_token"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Granary risk surface loads")
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
	var observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var history := viewer.get_node("%HistoryText") as RichTextLabel
	var risk_heading := viewer.get_node("%RiskHeading") as Label
	var risk_text := viewer.get_node("%RiskText") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	_check(
		not risk_heading.visible
		and "健康　100" in player_summary.text
		and "发现物　无" in player_summary.text,
		"2. Shop starts without a local risk and shows health and inventory"
	)

	var outbound := _find_travel_button(travel_buttons, OUTBOUND_ROUTE)
	outbound.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "废弃粮仓"
		and risk_heading.visible
		and risk_text.visible
		and "眼前的风险　高" in risk_heading.text,
		"3. Arrival makes the granary risk visible"
	)
	_check(
		"朽木地板" in risk_text.text
		and "d20 + 感知 10 / 难度 21" in risk_text.text
		and "不会死亡" in risk_text.text
		and "也可返回" in risk_text.text,
		"4. Risk panel explains formula, preparation, retreat, and failure"
	)

	var prepare_button := _find_challenge_button(
		action_buttons,
		PREPARE_OPTION
	)
	var enter_button := _find_challenge_button(
		action_buttons,
		ENTER_OPTION
	)
	_check(
		prepare_button != null
		and enter_button != null
		and "准备" in prepare_button.text
		and "危险" in enter_button.text,
		"5. Preparation and direct-entry controls come from live challenge options"
	)

	prepare_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"15:00" in time_label.text
		and feedback_title.text == "在门外做好准备"
		and "白灰圈了出来" in feedback_body.text,
		"6. Preparation advances time and gives concrete scene feedback"
	)
	_check(
		"准备已经完成" in risk_text.text
		and "准备 10" in risk_text.text
		and _find_challenge_button(action_buttons, PREPARE_OPTION) == null
		and _find_challenge_button(action_buttons, ENTER_OPTION) != null,
		"7. Preparation changes the formula and cannot be repeated"
	)

	enter_button = _find_challenge_button(action_buttons, ENTER_OPTION)
	enter_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"16:00" in time_label.text
		and feedback_title.text == "梁柱后的旧物"
		and "掷骰" in feedback_body.text
		and "准备 10" in feedback_body.text
		and "旧粮仓验粮铜牌" in feedback_body.text,
		"8. Entry shows the real roll formula and successful discovery"
	)
	_check(
		"塌粮架后的墙龛" in observations.text
		and "旧粮仓验粮铜牌" in player_summary.text
		and "健康　100" in player_summary.text,
		"9. Success reveals the site and adds the item without injury"
	)
	_check(
		"检查了朽木地板" in knowledge.text
		and "通过了废弃粮仓的危险检定" in knowledge.text
		and "找到了旧粮仓验粮铜牌" in knowledge.text
		and "遮住口鼻" in history.text
		and "踏进粮仓深处" in history.text,
		"10. Preparation, check, discovery, and history are player-readable"
	)
	_check(
		not risk_heading.visible
		and _find_challenge_button(action_buttons, ENTER_OPTION) == null,
		"11. Resolved challenge disappears instead of allowing duplicate loot"
	)

	var item: Dictionary = viewer.view_model.session.stores[
		"item_store"
	].get_item(DISCOVERY_ITEM)
	var provenance: Dictionary = item.get("provenance", {})
	_check(
		str(provenance.get("discovered_at", ""))
			== "abandoned_granary"
		and int(provenance.get("discovered_hour", 0)) == 16,
		"12. UI result is backed by stored item provenance"
	)

	var return_button := _find_travel_button(travel_buttons, RETURN_ROUTE)
	return_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "20:00" in time_label.text
		and "旧粮仓验粮铜牌" in player_summary.text
		and "半掩的门板" in observations.text,
		"13. Discovery returns to the changed shop in the same world"
	)
	_check(
		viewer.view_model.session.challenge_preparation_count == 1
		and viewer.view_model.session.challenge_count == 1
		and viewer.view_model.session.travel_count == 2
		and viewer.view_model.session.world_tick_count == 4,
		"14. UI keeps preparation, check, travel, and ticks distinct"
	)

	viewer.restart_session()
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "10:00" in time_label.text
		and "健康　100" in player_summary.text
		and "发现物　无" in player_summary.text
		and not risk_heading.visible,
		"15. Restart resets the complete risk and discovery loop"
	)

	viewer.queue_free()
	await process_frame
	_finish()


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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GRANARY RISK DISCOVERY SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 GRANARY RISK DISCOVERY SURFACE FAIL] " + failure)
	print(
		"[V5 GRANARY RISK DISCOVERY SURFACE RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 GRANARY RISK DISCOVERY SURFACE PASS] " + message)
	else:
		failures.append(message)
