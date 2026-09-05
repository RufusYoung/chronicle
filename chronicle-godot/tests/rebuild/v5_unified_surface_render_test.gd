extends SceneTree

const Style = preload("res://scripts/rebuild/v5_shared_interface_style.gd")
const Live = preload("res://scenes/rebuild/v5_live_location_viewer.tscn")
const Outpost = preload("res://scenes/rebuild/v5_seventh_outpost_viewer.tscn")
var checks := 0
var failures: Array[String] = []
var output := "user://tests/unified_surface"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for packed: PackedScene in [Live, Outpost]:
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(1280, 720)
		var viewer = packed.instantiate()
		root.add_child(viewer)
		await _settle()
		var is_outpost: bool = packed == Outpost
		var label := "outpost" if is_outpost else "lake"
		var header := viewer.get_node("%WorldHeader") as Control
		_check(header.position.y == 0 and header.size.y <= 72, label + ": shared compact header")
		_check(viewer.restart_button.get_theme_font_size("font_size") == Style.FONT_BODY
			and viewer.restart_button.get_theme_stylebox("normal").bg_color == Style.COLOR_SURFACE,
			label + ": same command typography and states")
		await _capture(viewer, label + "_1280")
		if is_outpost:
			var before: Dictionary = viewer.current_view_data.market.duplicate(true)
			var purchase := viewer.market_buttons.get_child(0) as Button
			_check(purchase.is_visible_in_tree(), "supplies can be purchased on the scene page")
			purchase.pressed.emit()
			await _settle()
			_check(viewer.current_view_data.market.ration_count == before.ration_count + 1
				and viewer.current_view_data.market.coin_count < before.coin_count,
				"visible purchase changes actual inventory and payment")
			_check(viewer.feedback_title.text == "从玛塔手里领到一份口粮",
				"purchase feedback stays on the page where the action occurred")
			viewer.perform_duty("patrol_fog_line")
			await _settle()
		else:
			viewer.perform_action("give_food_to_hungry_person:chen_mi")
			await _settle()
		await _capture(viewer, label + "_after_action")
		var model: Variant = viewer.view_model
		var session: Variant = model.controller.session if is_outpost else model.session
		var before_read := _state(session)
		(viewer.get_node("%OpenResultReceipt") as BaseButton).pressed.emit()
		await _settle()
		var tabs := viewer.get_node("%WorldSurfacePages") as TabContainer
		_check(tabs.get_tab_title(tabs.current_tab) == "记录", label + ": direct receipt navigation")
		_check(viewer.get_node("%ResultReceipt").text.contains(viewer.feedback_title.text),
			label + ": full receipt contains the visible outcome")
		(viewer.get_node("%BackToScene") as Button).pressed.emit()
		await _settle()
		_check(tabs.current_tab == 0 and viewer.get_node("%OpenResultReceipt").has_focus(),
			label + ": return restores scene and keyboard focus")
		_check(before_read == _state(session),
			label + ": reading consumes no resources, time or RNG")
		viewer.restart_button.pressed.emit()
		await _settle()
		var dialog: ConfirmationDialog = viewer.get_node("%RestartDialog")
		_check(dialog.visible and dialog.get_cancel_button().has_focus(),
			label + ": reset requires a safe-default confirmation")
		dialog.get_cancel_button().pressed.emit()
		await _settle()
		_check(before_read == _state(session),
			label + ": cancelled restart preserves the complete live state")
		if is_outpost:
			viewer.restart_button.pressed.emit()
			dialog.confirmed.emit()
			await _settle()
			_check(viewer.current_view_data.day == 1 and viewer.current_view_data.history.is_empty(),
				"confirmed outpost restart clears this phase only")
		# Test injection exercises wrapping and records retention, not game events.
		var details: Array = []
		for index: int in 12:
			details.append("测试注入结果 %d：货物与时间变化必须保留在完整记录中。" % index)
		viewer._refresh_feedback({"title": "测试注入长结果", "body": "用于验证正文换行的结果说明。".repeat(6), "details": details})
		await _settle()
		_check("测试注入结果 11" in viewer.get_node("%ResultReceipt").text,
			label + ": long result details are not discarded")
		await _capture(viewer, label + "_long_feedback")
		viewer.refresh_view()
		tabs.current_tab = 1
		await _settle()
		await _capture(viewer, label + "_character")
		tabs.current_tab = 0
		root.content_scale_size = Vector2i(1600, 900)
		root.size = Vector2i(1600, 900)
		await _settle()
		await _capture(viewer, label + "_1600")
		viewer.queue_free()
		await _settle()
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures,
		"method": "Script-driven Godot UI; not unassisted human play"}, "  "))
	file.close()
	print("UNIFIED_SURFACE_RESULT %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _state(session: Variant) -> String:
	# Save creation timestamps change with wall time, not with simulation state.
	var envelope: Dictionary = session.build_save_envelope()
	return JSON.stringify({"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states,
		"world_log": envelope.world_log}, "", true, true)


func _capture(viewer: Control, label: String) -> void:
	var problems: Array[String] = []
	_audit(viewer, problems)
	_check(problems.is_empty(), label + ": all visible text and controls fit; " + "; ".join(problems))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(output + "/" + label + ".png") == OK,
			label + ": renderer evidence saved")


func _audit(node: Node, problems: Array[String]) -> void:
	if node is Control and not node.is_visible_in_tree():
		return
	if node is RichTextLabel:
		if node.scroll_active or node.get_content_height() > node.size.y + 2:
			problems.append("clipped_or_scroll:" + str(node.name))
	if node is Label or node is BaseButton or node is RichTextLabel:
		if not root.get_visible_rect().grow(1).encloses(node.get_global_rect()):
			problems.append("outside_viewport:" + str(node.name))
	if node is ScrollContainer and node.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		problems.append("unexpected_scroll:" + str(node.name))
	for child: Node in node.get_children():
		_audit(child, problems)


func _settle() -> void:
	for index: int in 5:
		await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)
