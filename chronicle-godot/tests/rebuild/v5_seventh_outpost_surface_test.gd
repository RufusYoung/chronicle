extends SceneTree

const VIEWER_SCENE := (
	"res://scenes/rebuild/v5_seventh_outpost_viewer.tscn"
)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "1. Seventh Outpost service surface loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var day_label := viewer.get_node("%DayLabel") as Label
	var player_text := viewer.get_node("%PlayerText") as RichTextLabel
	var people_text := viewer.get_node("%PeopleText") as RichTextLabel
	var status_text := viewer.get_node("%StatusText") as RichTextLabel
	var feedback_title := viewer.get_node("%FeedbackTitle") as Label
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	var history_text := viewer.get_node("%HistoryText") as RichTextLabel
	var action_heading := viewer.get_node("%ActionHeading") as Label
	var action_buttons := viewer.get_node("%ActionButtons") as FlowContainer
	var intro_dialog := viewer.get_node("%IntroDialog") as AcceptDialog
	var completion_dialog := viewer.get_node("%CompletionDialog") as AcceptDialog

	_check(
		day_label.text == "第 1 / 7 天　06:00　清晨点名"
		and not intro_dialog.visible,
		"2. First duty begins without a blocking onboarding dialog"
	)
	_check(
		"力量 7　敏捷 8　智慧 9" in player_text.text
		and "魅力 6　体质 8　感知 10" in player_text.text
		and "疲劳 1 / 10" in player_text.text,
		"3. Service screen exposes attributes and changing condition"
	)
	_check(
		_all_in_text(people_text.text, ["罗恩", "伊莱", "玛塔", "赛拉", "霍克"])
		and _all_in_text(status_text.text, [
			"补给", "士气", "军纪", "哨墙", "战备", "边境压力"
		]),
		"4. Fixed comrades and systemic outpost pressures are visible"
	)

	var patrol := _find_duty_button(action_buttons, "patrol_fog_line")
	_check(
		patrol != null
		and "需要感知 8" in patrol.text
		and _find_duty_button(action_buttons, "rest_in_infirmary") == null,
		"5. Duties show requirements and rest is absent before fatigue"
	)

	viewer.view_model.controller.session.stores["state_store"].set_state(
		"player", "perception", 7
	)
	viewer.refresh_view()
	await process_frame
	patrol = _find_duty_button(action_buttons, "patrol_fog_line")
	_check(
		patrol != null
		and patrol.disabled
		and "感知 7/8" in patrol.text,
		"6. Blocked duty explains the missing attribute in place"
	)
	viewer.perform_duty("patrol_fog_line")
	await process_frame
	_check(
		day_label.text.begins_with("第 1 / 7 天")
		and feedback_title.text == "今天的职责没有开始"
		and "感知不足" in feedback_body.text,
		"7. Repeating a blocked duty gives feedback without advancing"
	)

	viewer.restart_project()
	await process_frame
	for duty_index: int in range(2):
		viewer.perform_duty("patrol_fog_line")
		await process_frame
	_check(
		day_label.text.begins_with("第 3 / 7 天")
		and feedback_title.text == "雾线外没有脚印"
		and "今晚少了一块盲区" in feedback_body.text
		and "第 2 天" in history_text.text
		and "直接列出条件、消耗与影响" in (
			viewer.get_node("%ActionHint") as Label
		).text
		and _find_duty_button(action_buttons, "rest_in_infirmary") != null,
		"8. Two patrols create readable consequences and unlock recovery"
	)

	viewer.perform_duty("rest_in_infirmary")
	await process_frame
	_check(
		"军医室的窗一整天没有结霜" in feedback_title.text
		and "疲劳 0 / 10" in player_text.text
		and _find_duty_button(action_buttons, "rest_in_infirmary") == null,
		"9. Recovery changes state and disappears when no longer relevant"
	)

	for duty_index: int in range(4):
		viewer.perform_duty("patrol_fog_line")
		await process_frame
	await process_frame
	var complete_view: Dictionary = viewer.get_current_view_data()
	_check(
		bool(complete_view.get("complete", false))
		and (complete_view.get("history", []) as Array).size() == 7
		and action_buttons.get_child_count() == 0
		and completion_dialog.visible,
		"10. Seven state-driven duties reach an explicit playable endpoint"
	)
	_check(
		"雾线暂时退远" in completion_dialog.dialog_text
		and viewer.view_model.controller.session.stores[
			"chronicle_store"
		].list_entries().size() == 1,
		"11. Completion text is derived from state and stored as Chronicle"
	)

	viewer.restart_project()
	await process_frame
	viewer.view_model.controller.session.stores["state_store"].set_state(
		"seventh_outpost", "supply", 0
	)
	viewer.refresh_view()
	await process_frame
	var repair := _find_duty_button(action_buttons, "repair_east_wall")
	var archery := _find_duty_button(action_buttons, "practice_wall_archery")
	var share := _find_duty_button(action_buttons, "share_hard_bread")
	_check(
		repair != null and repair.disabled and "修墙物资 0/1" in repair.text
		and archery != null and archery.disabled and "箭材 0/1" in archery.text
		and share != null and share.disabled and "哨站补给 0/2" in share.text
		and "受限 3 项" in action_heading.text,
		"12. Resource exhaustion disables and explains affected duties"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _find_duty_button(container: Node, duty_id: String) -> Button:
	for child: Node in container.get_children():
		if child is Button and str(child.get_meta("duty_id", "")) == duty_id:
			return child as Button
	return null


func _all_in_text(text: String, fragments: Array) -> bool:
	for fragment: Variant in fragments:
		if str(fragment) not in text:
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 SEVENTH OUTPOST SURFACE PASS] " + label)
		return
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SEVENTH OUTPOST SURFACE RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 SEVENTH OUTPOST SURFACE FAIL] " + failure)
	print(
		"[V5 SEVENTH OUTPOST SURFACE RESULT] FAIL (%d)"
		% failures.size()
	)
	quit(1)
