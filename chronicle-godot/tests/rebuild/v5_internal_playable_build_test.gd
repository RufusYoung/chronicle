extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const GRANARY_OUTBOUND := "old_chen_shop_to_abandoned_granary"
const GRANARY_RETURN := "abandoned_granary_to_old_chen_shop"
const GRANARY_PREPARE := "prepare_granary_entry"
const GRANARY_ENTER := "enter_abandoned_granary"
const ECHO_OPTION := "show_granary_measure_token_to_chen_mi"
const INVESTIGATE_OPTION := "investigate_public_granary_seal_records"
const NORTH_QUAY_OUTBOUND := "old_chen_shop_to_north_quay_record_house"
const ARCHIVE_PREPARE := "prepare_flooded_archive_search"
const ARCHIVE_SEARCH := "search_flooded_archive_stack"
const EXPEDITION_PREPARE := "prepare_mist_salt_well_expedition"
const WELL_OUTBOUND := "north_quay_record_house_to_mist_salt_well"
const WELL_RETURN := "mist_salt_well_to_north_quay_record_house"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(
		str(ProjectSettings.get_setting("application/run/main_scene"))
			== VIEWER_SCENE,
		"1. Normal project launch enters the V5 playable slice"
	)

	var packed := load(VIEWER_SCENE) as PackedScene
	_check(packed != null, "2. Internal playable scene loads")
	if packed == null:
		_finish()
		return

	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame

	var goal_progress := viewer.get_node("%GoalProgress") as Label
	var goal_title := viewer.get_node("%GoalTitle") as Label
	var goal_summary := viewer.get_node("%GoalSummary") as RichTextLabel
	var session_label := viewer.get_node("%SessionLabel") as Label
	var restart_button := viewer.get_node("%RestartButton") as Button
	var intro_dialog := viewer.get_node("%IntroDialog") as AcceptDialog
	var completion_dialog := viewer.get_node("%CompletionDialog") as AcceptDialog
	var failure_dialog := viewer.get_node("%FailureDialog") as AcceptDialog
	var restart_dialog := (
		viewer.get_node("%RestartDialog") as ConfirmationDialog
	)

	_check(
		goal_progress.text == "内部试玩　目标 1 / 5"
		and goal_title.text == "调查废弃粮仓的异常"
		and "涨价告示" in goal_summary.text
		and "灰白粮粉" in goal_summary.text
		and session_label.text == "● 试玩进行中",
		"3. The first screen gives a specific objective and progress"
	)
	_check(
		"尚未接入正式存档" in intro_dialog.dialog_text
		and intro_dialog.get_ok_button().text == "开始试玩"
		and restart_button.text == "重新开始试玩",
		"4. Onboarding states the slice boundary and reset action clearly"
	)

	restart_button.pressed.emit()
	await process_frame
	_check(
		restart_dialog.visible
		and "都会被清空" in restart_dialog.dialog_text
		and restart_dialog.get_cancel_button().has_focus(),
		"5. Restart requires confirmation and defaults to the safe action"
	)
	restart_dialog.get_cancel_button().pressed.emit()
	await process_frame

	var session: Variant = viewer.view_model.session
	session.travel(GRANARY_OUTBOUND)
	session.execute_challenge_option(
		GRANARY_ENTER,
		{"source": "test_injection", "roll_override": 1}
	)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		goal_progress.text == "内部试玩　本次受挫"
		and goal_title.text == "粮仓里的线索断了"
		and session_label.text == "● 试玩受挫"
		and failure_dialog.visible
		and "先完成准备" in failure_dialog.dialog_text,
		"6. A closed failure path becomes an honest playable endpoint"
	)
	failure_dialog.hide()
	viewer.restart_session()
	await process_frame
	session = viewer.view_model.session

	session.travel(GRANARY_OUTBOUND)
	session.execute_challenge_option(GRANARY_PREPARE)
	session.execute_challenge_option(
		GRANARY_ENTER,
		{"source": "test_injection", "roll_override": 3}
	)
	viewer.refresh_view()
	await process_frame
	_check(
		goal_progress.text == "内部试玩　目标 2 / 5"
		and goal_title.text == "让旧铜牌开口"
		and "老陈铺子" in goal_summary.text,
		"7. Discovering the granary token advances the objective"
	)

	_complete_archive_record(session)
	viewer.refresh_view()
	await process_frame
	_check(
		goal_progress.text == "内部试玩　目标 4 / 5"
		and goal_title.text == "准备前往雾盐旧井"
		and "帮闻简晒卷" in goal_summary.text,
		"8. Finding Lu Huai's record points to expedition preparation"
	)

	session.execute_challenge_option(EXPEDITION_PREPARE)
	session.travel(WELL_OUTBOUND)
	session.execute_action(
		"inspect_visible_trace:mist_salt_well_mouth_crust"
	)
	viewer.refresh_view()
	await process_frame
	_check(
		goal_progress.text == "内部试玩　目标 5 / 5"
		and goal_title.text == "从旧井带回一次亲历"
		and "返程已经开放" in goal_summary.text,
		"9. Reaching the well explains the final choice and return"
	)

	session.travel(WELL_RETURN)
	viewer.refresh_view()
	await process_frame
	await process_frame
	_check(
		goal_progress.text == "内部试玩　已完成"
		and goal_title.text == "试玩目标完成"
		and session_label.text == "● 试玩完成"
		and completion_dialog.visible,
		"10. Returning from the well creates an explicit playable endpoint"
	)

	completion_dialog.hide()
	restart_button.pressed.emit()
	await process_frame
	restart_dialog.confirmed.emit()
	await process_frame
	_check(
		goal_progress.text == "内部试玩　目标 1 / 5"
		and goal_title.text == "调查废弃粮仓的异常"
		and not completion_dialog.visible
		and not failure_dialog.visible,
		"11. Confirmed restart clears end states and starts a fresh run"
	)

	viewer.queue_free()
	await process_frame
	_finish()


func _complete_archive_record(session: Variant) -> void:
	session.travel(GRANARY_RETURN)
	session.execute_return_echo_option(ECHO_OPTION)
	session.execute_investigation_option(INVESTIGATE_OPTION)
	session.advance_time(6, "wait_for_north_quay_ferry")
	session.travel(NORTH_QUAY_OUTBOUND)
	session.execute_challenge_option(ARCHIVE_PREPARE)
	session.execute_challenge_option(
		ARCHIVE_SEARCH,
		{"source": "test_injection", "roll_override": 1}
	)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 INTERNAL PLAYABLE BUILD RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 INTERNAL PLAYABLE BUILD FAIL] " + failure)
	print(
		"[V5 INTERNAL PLAYABLE BUILD RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 INTERNAL PLAYABLE BUILD PASS] " + message)
	else:
		failures.append(message)
