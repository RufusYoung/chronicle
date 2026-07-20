extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const GIVE_FOOD_ACTION := "give_food_to_hungry_person:chen_mi"
const READ_NOTICE_ACTION := (
	"read_visible_readable_object:old_chen_shop_price_notice"
)
const INSPECT_TRACE_ACTION := "inspect_visible_trace:gray_grain_powder"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. 动态地点局面场景可以独立加载")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var location_title := viewer.get_node("%LocationTitle") as Label
	var location_description := viewer.get_node("%LocationDescription") as RichTextLabel
	var player_summary := viewer.get_node("%PlayerSummary") as RichTextLabel
	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var visible_people := viewer.get_node("%VisiblePeople") as RichTextLabel
	var visible_observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var knowledge_text := viewer.get_node("%KnowledgeText") as RichTextLabel
	var history_text := viewer.get_node("%HistoryText") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	_check(
		location_title.text == "老陈铺子"
		and "旧粮" in location_description.text
		and "食物　2 份" in player_summary.text,
		"2. 初始画面来自湖湾镇模拟 fixture，而不是静态演示状态"
	)
	_check(
		"陈米" in visible_people.text
		and "饥饿：严重" in visible_people.text
		and "涨价告示" in visible_observations.text
		and "灰白粮粉" in visible_observations.text,
		"3. 当前快照投影出可见人物、可读物件和可检查痕迹"
	)
	_check(
		"粮食压力" in region_status.text
		and "街面秩序" in region_status.text,
		"4. 地区和机构状态被翻译为玩家可读的局面压力"
	)
	_check(
		_find_action_button(action_buttons, GIVE_FOOD_ACTION) != null
		and _find_action_button(action_buttons, READ_NOTICE_ACTION) != null
		and _find_action_button(action_buttons, INSPECT_TRACE_ACTION) != null,
		"5. 底部按钮由 SimSession 当前候选动态生成"
	)

	var give_button := _find_action_button(action_buttons, GIVE_FOOD_ACTION)
	(give_button as Button).pressed.emit()
	await process_frame
	_check(
		"食物　1 份" in player_summary.text
		and "饥饿：缓和" in visible_people.text,
		"6. 点击给食物后，玩家和陈米的持续状态立即刷新"
	)
	_check(
		"饥饿缓和" in feedback_body.text
		and "随身食物 -1" in feedback_body.text
		and "感激 +15" in feedback_body.text,
		"7. 结算叙事与关键状态、关系变化一起反馈"
	)
	_check(
		_find_action_button(action_buttons, GIVE_FOOD_ACTION) == null,
		"8. 陈米不再严重饥饿后，过期的给食物按钮消失"
	)

	var stale_result: Dictionary = viewer.perform_action(GIVE_FOOD_ACTION)
	await process_frame
	_check(
		not bool(stale_result.get("success", true))
		and "局面已经变化" in feedback_body.text
		and viewer.view_model.session.get_world_log_entries().size() == 1,
		"9. 旧行动即使被外部重复调用也不会污染世界日志"
	)

	viewer.perform_action(READ_NOTICE_ACTION)
	viewer.perform_action(INSPECT_TRACE_ACTION)
	await process_frame
	_check(
		"你读过涨价告示" in knowledge_text.text
		and "你检查过灰白粮粉" in knowledge_text.text,
		"10. 连续调查会把已确认事实投影到认知栏"
	)
	_check(
		"给陈米食物" in history_text.text
		and "阅读涨价告示" in history_text.text
		and "查看灰白粮粉" in history_text.text,
		"11. 玩家看到的是连续行动历史，不是一次性测试输出"
	)

	var visible_ui_text := "\n".join([
		location_title.text,
		player_summary.text,
		region_status.text,
		visible_people.text,
		visible_observations.text,
		feedback_body.text,
		knowledge_text.text,
		history_text.text,
	])
	_check(
		"actor_" not in visible_ui_text
		and "effect_template" not in visible_ui_text
		and "candidate_only" not in visible_ui_text,
		"12. 模拟内部标识没有泄漏到玩家界面"
	)

	viewer.restart_session()
	await process_frame
	_check(
		"食物　2 份" in player_summary.text
		and "饥饿：严重" in visible_people.text
		and "还没有发生行动" in history_text.text
		and _find_action_button(action_buttons, GIVE_FOOD_ACTION) != null,
		"13. 独立场景可以重新载入初始局面"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _find_action_button(container: Node, action_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("action_id", "")) == action_id:
			return child as Button
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIVE LOCATION VIEWER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 LIVE LOCATION VIEWER FAIL] " + failure)
		print("[V5 LIVE LOCATION VIEWER RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LIVE LOCATION VIEWER PASS] " + message)
	else:
		failures.append(message)
