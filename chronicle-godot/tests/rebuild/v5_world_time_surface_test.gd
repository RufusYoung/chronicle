extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const GIVE_FOOD_ACTION := "give_food_to_hungry_person:chen_mi"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. 世界时间地点场景可以加载")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var time_label := viewer.get_node("%TimeLabel") as Label
	var wait_button := viewer.get_node("%WaitButton") as Button
	var observations := viewer.get_node("%VisibleObservations") as RichTextLabel
	var region_status := viewer.get_node("%RegionStatus") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var knowledge_text := viewer.get_node("%KnowledgeText") as RichTextLabel
	var history_text := viewer.get_node("%HistoryText") as RichTextLabel
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer

	_check(
		"第 1 天" in time_label.text
		and "10:00" in time_label.text
		and "半掩的门板" not in observations.text,
		"2. 初始时钟来自 fixture，延迟现场细节尚未出现"
	)
	_check(
		wait_button.text == "等待一小时"
		and _find_action_button(action_buttons, GIVE_FOOD_ACTION) != null,
		"3. 时间操作与状态生成的玩家行动同时可用"
	)

	wait_button.pressed.emit()
	await process_frame
	_check(
		"11:00" in time_label.text
		and "半掩的门板" in observations.text
		and "刚被再次改高" in observations.text,
		"4. 点击等待后，时钟和现场可见状态一起刷新"
	)
	_check(
		feedback_title.text == "铺子提前收门"
		and "老陈从后屋拖出门板" in feedback_body.text
		and "粮食压力继续上升" in feedback_body.text
		and "老陈根据当前处境自行作出的决定" in feedback_body.text
		and "陈米仍在挨饿" in feedback_body.text,
		"5. 玩家在现场收到世界自主变化的叙事和原因"
	)
	_check(
		"收铺迹象" in region_status.text
		and "你亲眼看到老陈铺子提前收门" in knowledge_text.text,
		"6. 时间后果进入地区压力和玩家已确认事实"
	)
	_check(
		"等待一小时" in history_text.text
		and viewer.view_model.session.action_count == 0
		and viewer.view_model.session.world_tick_count == 1,
		"7. 行动历史记录等待，但核心仍区分玩家行动和世界 Tick"
	)
	_check(
		_find_action_button(action_buttons, GIVE_FOOD_ACTION) != null,
		"8. 时间推进后，普通行动仍由新快照重新生成"
	)

	viewer.advance_time()
	await process_frame
	_check(
		"12:00" in time_label.text
		and "这里没有立刻显现出新的变化" in feedback_body.text
		and viewer.view_model.session.stores["fact_store"]
			.find_facts_by_type("merchant_closed_shop_early")
			.size() == 1,
		"9. 再次等待继续走时钟，但不会复制一次性后果"
	)

	viewer.restart_session()
	await process_frame
	_check(
		"10:00" in time_label.text
		and "半掩的门板" not in observations.text
		and "收铺迹象" not in region_status.text
		and "还没有发生行动" in history_text.text,
		"10. 重载局面会恢复初始时间和待触发世界状态"
	)

	var give_food_button := _find_action_button(
		action_buttons,
		GIVE_FOOD_ACTION
	)
	_check(give_food_button != null, "11. 重载后仍可先改变陈米的饥饿状态")
	if give_food_button != null:
		give_food_button.pressed.emit()
		await process_frame
		wait_button.pressed.emit()
		await process_frame
		_check(
			"11:00" in time_label.text
			and feedback_title.text == "门板留在后屋"
			and "决定再做一阵生意" in feedback_body.text
			and "陈米的饥饿已经缓和" in feedback_body.text
			and "半掩的门板" not in observations.text,
			"12. 同一次等待会因共享状态不同而呈现继续营业"
		)
		_check(
			viewer.view_model.session.stores["fact_store"]
				.find_facts_by_type("merchant_kept_shop_open")
				.size() == 1
			and viewer.view_model.session.stores["fact_store"]
				.find_facts_by_type("merchant_closed_shop_early")
				.is_empty()
			and "老陈决定暂时不收铺" in knowledge_text.text,
			"13. UI 展示的是另一条世界事实，不是替换措辞后的同一结局"
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
		print("[V5 WORLD TIME SURFACE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 WORLD TIME SURFACE FAIL] " + failure)
		print("[V5 WORLD TIME SURFACE RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 WORLD TIME SURFACE PASS] " + message)
	else:
		failures.append(message)
