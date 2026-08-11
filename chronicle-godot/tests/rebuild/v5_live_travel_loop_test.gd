extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const GIVE_FOOD := "give_food_to_hungry_person:chen_mi"
const READ_NOTICE := "read_visible_readable_object:old_chen_shop_price_notice"
const SHOP_TRACE := "inspect_visible_trace:gray_grain_powder"
const OUTBOUND_ROUTE := "old_chen_shop_to_abandoned_granary"
const RETURN_ROUTE := "abandoned_granary_to_old_chen_shop"
const GRANARY_INSPECT_ACTION := (
	"inspect_visible_trace:abandoned_granary_mold_trace"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Travel viewer scene loads")
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
	var people := viewer.get_node("%VisiblePeople") as RichTextLabel
	var observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var history := viewer.get_node("%HistoryText") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	var outbound_button := _find_travel_button(
		travel_buttons,
		OUTBOUND_ROUTE
	)
	_check(
		location_title.text == "老陈铺子"
		and outbound_button == null
		and "废弃粮仓" not in observations.text,
		"2. Shop hides the granary route until local evidence is read"
	)

	_find_action_button(action_buttons, GIVE_FOOD).pressed.emit()
	await process_frame
	_find_action_button(action_buttons, READ_NOTICE).pressed.emit()
	await process_frame
	_find_action_button(action_buttons, SHOP_TRACE).pressed.emit()
	await process_frame
	await process_frame
	outbound_button = _find_travel_button(travel_buttons, OUTBOUND_ROUTE)
	_check(
		outbound_button != null and not outbound_button.disabled,
		"3. Reading the notice and grain trace exposes a usable route"
	)
	outbound_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "废弃粮仓"
		and "14:00" in time_label.text
		and "食物　1 份" in player_summary.text,
		"4. Outbound travel switches location and refreshes time and food"
	)
	_check(
		"裂开的粮仓门" in observations.text
		and "门槛上的霉斑" in observations.text
		and "陈米" not in people.text,
		"5. Granary view contains only local people and observations"
	)
	_check(
		feedback_title.text == "镇外小路"
		and "原来的地方也发生了变化" in feedback_body.text
		and "决定再做一阵生意" in feedback_body.text,
		"6. Travel feedback includes the world change that happened en route"
	)
	_check(
		"完成过一段需要时间和食物的旅程" in knowledge.text
		and "老陈决定暂时不收铺" in knowledge.text,
		"7. Travel and source-location consequences enter player knowledge"
	)
	_check(
		_find_action_button(
			action_buttons,
			GRANARY_INSPECT_ACTION
		) != null
		and _find_travel_button(travel_buttons, RETURN_ROUTE) != null,
		"8. Arrival regenerates local investigation and return controls"
	)

	var inspect_button := _find_action_button(
		action_buttons,
		GRANARY_INSPECT_ACTION
	)
	inspect_button.pressed.emit()
	await process_frame
	_check(
		"检查" in history.text
		and "门槛上的霉斑" in knowledge.text,
		"9. Granary investigation uses the existing live action pipeline"
	)

	var return_button := _find_travel_button(travel_buttons, RETURN_ROUTE)
	return_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "18:00" in time_label.text
		and "食物　0 份" in player_summary.text,
		"10. Return trip restores the shop projection and consumes resources"
	)
	_check(
		"半掩的门板" not in observations.text
		and "刚被再次改高" not in observations.text
		and "裂开的粮仓门" not in observations.text,
		"11. The shop remains open after the helped-family round trip"
	)

	outbound_button = _find_travel_button(travel_buttons, OUTBOUND_ROUTE)
	_check(
		outbound_button != null
		and outbound_button.disabled
		and "食物不足" in outbound_button.tooltip_text,
		"12. Travel control communicates insufficient resources"
	)
	_check(
		viewer.view_model.session.travel_count == 2
		and viewer.view_model.session.world_tick_count == 2
		and viewer.view_model.session.action_count == 4,
		"13. UI keeps journeys, world ticks, and actions as separate events"
	)

	viewer.restart_session()
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "10:00" in time_label.text
		and "食物　3 份" in player_summary.text
		and "半掩的门板" not in observations.text,
		"14. Restart resets the complete travel loop"
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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIVE TRAVEL LOOP RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 LIVE TRAVEL LOOP FAIL] " + failure)
	print("[V5 LIVE TRAVEL LOOP RESULT] FAIL: %s" % JSON.stringify(failures))
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LIVE TRAVEL LOOP PASS] " + message)
	else:
		failures.append(message)
