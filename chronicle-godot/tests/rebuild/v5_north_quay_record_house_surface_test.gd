extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
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
const WAIT_FOR_FERRY := "wait_until_north_quay_ferry"
const NORTH_QUAY_OUTBOUND := "old_chen_shop_to_north_quay_record_house"
const NORTH_QUAY_RETURN := "north_quay_record_house_to_old_chen_shop"
const ARCHIVE_RULES := "read_visible_readable_object:north_quay_visiting_rules"
const ARCHIVE_TIDE := "inspect_visible_trace:north_quay_tide_marks"
const ARCHIVE_PREPARE := "prepare_flooded_archive_search"
const ARCHIVE_SEARCH := "search_flooded_archive_stack"
const ARCHIVE_ITEM := "lu_huai_last_inspection_leaf"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. North quay record house surface loads")
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
	var visible_people := viewer.get_node("%VisiblePeople") as RichTextLabel
	var observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var knowledge := viewer.get_node("%KnowledgeText") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var history := viewer.get_node("%HistoryText") as RichTextLabel
	var chronicle_heading := viewer.get_node("%ChronicleHeading") as Label
	var chronicle_text := viewer.get_node("%ChronicleText") as RichTextLabel
	var risk_heading := viewer.get_node("%RiskHeading") as Label
	var risk_text := viewer.get_node("%RiskText") as RichTextLabel
	var travel_buttons := viewer.get_node("%TravelButtons") as VBoxContainer
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	_check(
		_find_travel_button(
			travel_buttons,
			NORTH_QUAY_OUTBOUND
		) == null,
		"2. Undiscovered north quay does not leak into the initial route list"
	)

	await _complete_granary_investigation(
		action_buttons,
		travel_buttons
	)
	await process_frame
	await process_frame

	var night_ferry := _find_travel_button(
		travel_buttons,
		NORTH_QUAY_OUTBOUND
	)
	_check(
		night_ferry != null
		and night_ferry.disabled
		and "乘早船去北埠旧档房" in night_ferry.text
		and "2 小时" in night_ferry.text
		and "0 食物" not in night_ferry.text
		and "06:00" in night_ferry.tooltip_text,
		"3. Archive evidence reveals a readable but closed midnight ferry"
	)

	viewer.perform_travel(NORTH_QUAY_OUTBOUND)
	await process_frame
	_check(
		"第 2 天　00:00" in time_label.text
		and feedback_title.text == "没有动身"
		and "摆渡已经停船" in feedback_body.text,
		"4. Trying the closed route explains the time gate without advancing time"
	)

	_find_action_button(action_buttons, WAIT_FOR_FERRY).pressed.emit()
	await process_frame
	await process_frame
	var morning_ferry := _find_travel_button(
		travel_buttons,
		NORTH_QUAY_OUTBOUND
	)
	_check(
		"第 2 天　06:00" in time_label.text
		and morning_ferry != null
		and not morning_ferry.disabled,
		"5. One rest action opens the ferry at six in the morning"
	)

	morning_ferry.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "北埠旧档房"
		and "第 2 天　08:00" in time_label.text
		and "北埠水岸" in location_context.text
		and "潮水侵蚀" in location_context.text
		and "潮桩" in location_description.text,
		"6. Ferry arrives at a distinct, player-readable archive location"
	)
	_check(
		"闻简" in visible_people.text
		and "受潮的查档规条" in observations.text
		and "廊柱上的旧潮线" in observations.text
		and "通往水浸封存层的窄门" in observations.text,
		"7. North quay presents a person, rules, tide trace, and dangerous entrance"
	)
	_find_action_button(action_buttons, ARCHIVE_RULES).pressed.emit()
	await process_frame
	_find_action_button(action_buttons, ARCHIVE_TIDE).pressed.emit()
	await process_frame
	await process_frame
	_check(
		risk_heading.visible
		and "眼前的风险　中" in risk_heading.text
		and "齐腰深的湖水" in risk_text.text
		and "d20 + 力量 7 / 难度 19" in risk_text.text
		and "不会死亡" in risk_text.text
		and chronicle_text.custom_minimum_size.y == 58.0
		and risk_text.custom_minimum_size.y == 64.0
		and history.custom_minimum_size.y == 96.0,
		"8. Flooded stacks explain their formula and concrete failure cost"
	)

	var prepare_button := _find_challenge_button(
		action_buttons,
		ARCHIVE_PREPARE
	)
	var search_button := _find_challenge_button(
		action_buttons,
		ARCHIVE_SEARCH
	)
	_check(
		prepare_button != null
		and search_button != null
		and "借灯笼和油布" in prepare_button.text
		and "进入水浸封存层" in search_button.text,
		"9. Archive danger offers preparation and direct entry together"
	)

	prepare_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"第 2 天　09:00" in time_label.text
		and feedback_title.text == "等潮线退到旧刻痕下"
		and "罩灯" in feedback_body.text
		and "准备 11" in risk_text.text
		and _find_challenge_button(
			action_buttons,
			ARCHIVE_PREPARE
		) == null,
		"10. Tide preparation advances time and visibly changes the risk"
	)

	search_button = _find_challenge_button(
		action_buttons,
		ARCHIVE_SEARCH
	)
	search_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		"第 2 天　10:00" in time_label.text
		and feedback_title.text == "没有归档的最后一页"
		and "陆槐最后一页验粮簿" in feedback_body.text
		and "不是霉" in feedback_body.text
		and "雾盐旧井" in feedback_body.text,
		"11. Successful search exposes the record, its claim, and next direction"
	)
	_check(
		"拆开的蜡布夹层" in observations.text
		and "陆槐最后一页验粮簿" in player_summary.text
		and "旧粮仓验粮铜牌" in player_summary.text
		and not risk_heading.visible
		and chronicle_text.custom_minimum_size.y == 112.0
		and history.custom_minimum_size.y == 132.0,
		"12. Discovery changes the scene, inventory, and resolved danger"
	)
	_check(
		"旧记录声称" in knowledge.text
		and "雾盐旧井" in knowledge.text
		and "北埠旧档房找到了陆槐" in knowledge.text,
		"13. Confirmed knowledge preserves the difference between claim and truth"
	)
	_check(
		chronicle_heading.text
			== "个人纪事　潮水下没有归档的一页"
		and "旧文书留下的说法" in chronicle_text.text
		and "镇外" in chronicle_text.text
		and "依据 7 条事实、1 件物品" in chronicle_text.text,
		"14. Personal chronicle cites the route, preparation, facts, and record"
	)
	_check(
		"借灯笼和油布" in history.text
		and "进入水浸封存层" in history.text,
		"15. Player-facing history keeps the two archive choices distinct"
	)

	var snapshot: Variant = viewer.view_model.session.get_snapshot()
	var record: Dictionary = snapshot.get_item(ARCHIVE_ITEM)
	var entries: Array = snapshot.get_player_chronicle_entries()
	_check(
		str(record.get("owner_id", "")) == "player"
		and str(record.get("provenance", {}).get(
			"epistemic_status",
			""
		)) == "document_claim"
		and entries.size() == 3
		and viewer.view_model.session.stores[
			"fact_store"
		].find_facts_by_type(
			"lu_huai_recorded_departure_for_mist_salt_well"
		).size() == 1,
		"16. Visible outcome is backed by item, fact, and chronicle stores"
	)

	var return_button := _find_travel_button(
		travel_buttons,
		NORTH_QUAY_RETURN
	)
	return_button.pressed.emit()
	await process_frame
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "第 2 天　12:00" in time_label.text
		and "陆槐最后一页验粮簿" in player_summary.text,
		"17. The archive record returns to the continuing ordinary world"
	)

	viewer.restart_session()
	await process_frame
	_check(
		location_title.text == "老陈铺子"
		and "第 1 天　10:00" in time_label.text
		and "发现物　无" in player_summary.text
		and _find_travel_button(
			travel_buttons,
			NORTH_QUAY_OUTBOUND
		) == null
		and not chronicle_heading.visible,
		"18. Restart clears the route, record, and complete archive chronicle"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _complete_granary_investigation(
		action_buttons: Node,
		travel_buttons: Node
) -> void:
	_find_action_button(action_buttons, READ_NOTICE).pressed.emit()
	await process_frame
	_find_action_button(action_buttons, SHOP_TRACE).pressed.emit()
	await process_frame
	await process_frame
	_find_travel_button(
		travel_buttons,
		GRANARY_OUTBOUND
	).pressed.emit()
	await process_frame
	await process_frame
	_find_action_button(action_buttons, GRANARY_TRACE).pressed.emit()
	await process_frame
	await process_frame
	_find_challenge_button(
		action_buttons,
		GRANARY_PREPARE
	).pressed.emit()
	await process_frame
	await process_frame
	_find_challenge_button(
		action_buttons,
		GRANARY_ENTER
	).pressed.emit()
	await process_frame
	await process_frame
	_find_travel_button(
		travel_buttons,
		GRANARY_RETURN
	).pressed.emit()
	await process_frame
	await process_frame
	_find_return_echo_button(
		action_buttons,
		ECHO_OPTION
	).pressed.emit()
	await process_frame
	await process_frame
	_find_investigation_button(
		action_buttons,
		INVESTIGATE_OPTION
	).pressed.emit()
	await process_frame
	await process_frame
	_find_action_button(action_buttons, READ_TAX_DEED).pressed.emit()
	await process_frame
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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 NORTH QUAY RECORD HOUSE SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 NORTH QUAY RECORD HOUSE SURFACE FAIL] " + failure)
	print(
		"[V5 NORTH QUAY RECORD HOUSE SURFACE RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 NORTH QUAY RECORD HOUSE SURFACE PASS] " + message)
	else:
		failures.append(message)
