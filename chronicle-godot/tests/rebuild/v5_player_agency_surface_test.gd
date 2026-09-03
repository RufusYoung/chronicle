extends SceneTree

const LiveModel = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const GIVE_FOOD := "give_food_to_hungry_person:chen_mi"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var viewer: Control = load("res://scenes/rebuild/v5_live_location_viewer.tscn").instantiate()
	root.add_child(viewer)
	await _settle()
	_check_layout(viewer, "old_chen_initial")
	_capture("old_chen_initial")
	var gift := _button(viewer.get_node("%ActionButtons"), "action_id", GIVE_FOOD)
	_check(gift != null and "花费 1 小时" in gift.text and "取舍" in gift.text,
		"Action card exposes cost and tradeoff without hovering")
	if gift == null:
		quit(1)
		return
	var passive = LiveModel.new()
	passive.start()
	passive.advance_time(1)
	gift.pressed.emit()
	await _settle()
	var session: Variant = viewer.view_model.session
	_check(session.current_hour == 11 and session.action_count == 1 and session.world_tick_count == 1,
		"One UI choice settles once and advances the shared world clock")
	_check(session.stores["fact_store"].find_facts_by_type("merchant_kept_shop_open").size() == 1
		and passive.session.stores["fact_store"].find_facts_by_type("merchant_closed_shop_early").size() == 1,
		"Equal-time paired runs differ because helping changes a condition the merchant reads")
	_check("门板" in (viewer.get_node("%DecisionSituation") as RichTextLabel).text
		and "你的选择" in (viewer.get_node("%FeedbackEyebrow") as Label).text,
		"Player result and the subsequent world reaction are both visible")
	var previous_time: Dictionary = session.get_time_summary()
	var previous_log_count: int = session.get_world_log_entries().size()
	var stale: Dictionary = viewer.perform_action(GIVE_FOOD)
	_check(not stale.get("success", true) and previous_time == session.get_time_summary()
		and previous_log_count == session.get_world_log_entries().size(),
		"A stale action consumes neither resources nor another hour")
	viewer.advance_time()
	await _settle()
	_check("世界自行发生" in (viewer.get_node("%FeedbackEyebrow") as Label).text
		and viewer.current_view_data.agency.has_player_impact,
		"Waiting is attributed to world evolution without erasing the earlier player impact")
	_check_layout(viewer, "old_chen_after_wait")
	var pages := viewer.get_node("%WorldSurfacePages") as TabContainer
	pages.current_tab = 1
	await _settle()
	_check((viewer.get_node("%PlayerSummary") as Control).is_visible_in_tree()
		and "体质" in (viewer.get_node("%PlayerSummary") as RichTextLabel).text,
		"Character page exposes the complete attribute sheet")
	_check_layout(viewer, "old_chen_character")
	pages.current_tab = 2
	await _settle()
	_check("感激 +15" in (viewer.get_node("%HistoryText") as RichTextLabel).text,
		"Full earlier consequences remain accessible in the record, not just the latest message")
	pages.current_tab = 0
	var many_actions: Array = []
	# Test injection stresses layout only; these rows are not world candidates.
	for index: int in 17:
		many_actions.append({"action_id": "layout_test_%d" % index, "label": "测试选择 %d" % index})
	var before_paging: Dictionary = session.get_time_summary()
	viewer._refresh_actions(many_actions)
	await _settle()
	var seen: Array[String] = []
	for page: int in 5:
		for button: Button in viewer.get_node("%ActionButtons").get_children():
			if button.is_visible_in_tree():
				seen.append(str(button.get_meta("action_id")))
		_check_layout(viewer, "many_actions_page_%d" % page)
		if page < 4:
			(viewer.get_node("%NextActions") as Button).pressed.emit()
			await _settle()
	_check(seen.size() == 17 and before_paging == session.get_time_summary()
		and (viewer.get_node("%NextActions") as Button).disabled,
		"Every injected action remains reachable across pages without consuming world time")
	viewer.queue_free()
	await _settle()

	var outpost: Control = load("res://scenes/rebuild/v5_seventh_outpost_viewer.tscn").instantiate()
	root.add_child(outpost)
	await _settle()
	_check_layout(outpost, "outpost_initial")
	_capture("outpost_initial")
	var patrol := _button(outpost.get_node("%ActionButtons"), "duty_id", "patrol_fog_line")
	_check(patrol != null and "推进 1 天" in patrol.text and "风险 6 → 4" in patrol.text,
		"Outpost uses the same visible time-cost and consequence cards")
	if patrol != null:
		patrol.pressed.emit()
	await _settle()
	var result: Dictionary = outpost.view_model.latest_result
	_check(_delta(result.get("duty_transaction", {}), "border_pressure") == -3
		and _delta(result.get("settlement_transaction", {}), "border_pressure") == 2
		and result.has("status_before") and result.has("tick_result"),
		"Duty, daily pressure and autonomous simulation have separate causal receipts")
	_check("你的直接影响" in (outpost.get_node("%FeedbackBody") as RichTextLabel).text
		and "同期世界变化" in (outpost.get_node("%ResultReceipt") as RichTextLabel).text,
		"Direct impact is prominent and the full world settlement remains in records")
	_check_layout(outpost, "outpost_after_duty")
	_capture("outpost_after_duty")
	(outpost.get_node("%WorldSurfacePages") as TabContainer).current_tab = 1
	await _settle()
	_check_layout(outpost, "outpost_character")
	_check("雾线守望 初显" in (outpost.get_node("%FeatureText") as RichTextLabel).text,
		"Character page translates mark stages instead of exposing internal enum values")
	_capture("outpost_character")
	outpost.queue_free()
	await _settle()
	for failure: String in failures:
		push_error(failure)
	print("[PLAYER AGENCY SURFACE RESULT] %s" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _delta(transaction: Dictionary, key: String) -> int:
	var total := 0
	for change: Dictionary in transaction.get("state_changes", []):
		if str(change.get("key", "")) == key:
			total += int(change.get("delta", 0))
	return total


func _button(parent: Node, key: String, value: String) -> Button:
	for child: Node in parent.get_children():
		if child is Button and str(child.get_meta(key, "")) == value:
			return child
	return null


func _check_layout(viewer: Control, state: String) -> void:
	var errors: Array[String] = []
	_audit(viewer, errors)
	_check(errors.is_empty(), "%s: visible content fits 1280x720 with no nested scroll (%s)" % [state, "; ".join(errors)])


func _audit(node: Node, errors: Array[String]) -> void:
	if node is Control and not node.is_visible_in_tree():
		return
	if node is RichTextLabel:
		if node.scroll_active:
			errors.append("nested_scroll:%s" % node.name)
		if node.get_content_height() > node.size.y + 2:
			errors.append("clipped_text:%s" % node.name)
	if node is RichTextLabel or node is Button:
		if not Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(1).encloses(node.get_global_rect()):
			errors.append("outside_viewport:%s" % node.name)
	for child: Node in node.get_children():
		_audit(child, errors)


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	root.get_texture().get_image().save_png("user://tests/agency_%s.png" % label)


func _settle() -> void:
	for index: int in range(4):
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[PLAYER AGENCY PASS] %s" % label)
	else:
		failures.append(label)
