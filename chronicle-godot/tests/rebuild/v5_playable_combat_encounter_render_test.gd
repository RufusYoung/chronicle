extends SceneTree

const VIEWER_SCENE := "res://scenes/rebuild/v5_live_location_viewer.tscn"
const ENCOUNTER_OUTPUT := "user://tests/v5_playable_combat_encounter.png"
const RESULT_OUTPUT := "user://tests/v5_playable_combat_result.png"
const NEGOTIATE := "combat:mist_salt_well_claimant:negotiate"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(VIEWER_SCENE) as PackedScene
	if packed == null:
		_fail("viewer_scene_not_loaded")
		_finish()
		return
	var viewer := packed.instantiate()
	root.add_child(viewer)
	await process_frame
	await process_frame
	var start: Dictionary = viewer.view_model.start({
		"challenge_seed_override": 516,
	})
	_check(
		bool(start.get("success", false))
		and _reach_well(viewer.view_model.session),
		"1. Seed 516 render state reaches encounter"
	)
	viewer.refresh_view()
	await process_frame
	await process_frame

	var viewport_size := root.get_visible_rect().size
	var action_buttons := viewer.get_node("%ActionButtons") as Control
	var action_scroll := action_buttons.get_parent() as Control
	var risk_text := viewer.get_node("%RiskText") as RichTextLabel
	var feedback_body := viewer.get_node("%FeedbackBody") as RichTextLabel
	_check(
		viewport_size == Vector2(1280, 720),
		"2. Render viewport is exactly 1280x720"
	)
	_check(
		_inside_viewport(action_scroll.get_global_rect(), viewport_size),
		"2a. Action dock is inside the viewport (%s)" % action_scroll.get_global_rect()
	)
	_check(
		_inside_viewport(risk_text.get_global_rect(), viewport_size),
		"2b. Risk text is inside the viewport"
	)
	_check(
		_inside_viewport(feedback_body.get_global_rect(), viewport_size),
		"2c. Feedback text is inside the viewport"
	)
	_check(
		action_buttons.get_child_count() == 3
		and _children_inside(action_buttons, action_scroll.get_global_rect()),
		"2d. All three encounter buttons fit inside the action dock"
	)
	_check(
		"钩杆一直横在胸前" in risk_text.text
		and _button_text_contains(action_buttons, "[交战·需 4+]")
		and _button_text_contains(action_buttons, "[撤退·需 2+]")
		and _button_text_contains(action_buttons, "[交涉·需 4+]"),
		"2e. Encounter evidence and minimum rolls are rendered"
	)
	await _save_viewport(ENCOUNTER_OUTPUT, "3. Encounter screenshot is written")

	var result: Dictionary = viewer.perform_combat_encounter(
		NEGOTIATE,
		{"source": "test_injection", "roll_override": 4}
	)
	await process_frame
	await process_frame
	_check(
		bool(result.get("success", false))
		and action_buttons.get_child_count() > 0
		and not _has_combat_button(action_buttons)
		and "掷骰 4 + 影响 10 = 14 / 难度 14" in feedback_body.text
		and feedback_body.text.begins_with("掷骰 4 + 影响 10")
		and "原来的三个选择已从行动栏撤下" in feedback_body.text
		and _inside_viewport(feedback_body.get_global_rect(), viewport_size),
		"4. Resolved feedback is visible and encounter buttons stay consumed"
	)
	await _save_viewport(RESULT_OUTPUT, "5. Result screenshot is written")

	viewer.queue_free()
	await process_frame
	_finish()


func _reach_well(session: Variant) -> bool:
	var results: Array[Dictionary] = [
		session.travel("old_chen_shop_to_abandoned_granary"),
		session.execute_challenge_option("prepare_granary_entry"),
		session.execute_challenge_option(
			"enter_abandoned_granary",
			{"source": "test_injection", "roll_override": 3}
		),
		session.travel("abandoned_granary_to_old_chen_shop"),
		session.execute_return_echo_option(
			"show_granary_measure_token_to_chen_mi"
		),
		session.execute_investigation_option(
			"investigate_public_granary_seal_records"
		),
		session.execute_action(
			"read_visible_readable_object:old_chen_public_granary_tax_deed"
		),
		session.advance_time(6, "wait_for_north_quay_ferry"),
		session.travel("old_chen_shop_to_north_quay_record_house"),
		session.execute_challenge_option("prepare_flooded_archive_search"),
		session.execute_challenge_option(
			"search_flooded_archive_stack",
			{"source": "test_injection", "roll_override": 1}
		),
		session.execute_challenge_option(
			"prepare_mist_salt_well_expedition"
		),
		session.travel("north_quay_record_house_to_mist_salt_well"),
	]
	for result: Dictionary in results:
		if not bool(result.get("success", false)):
			return false
	return str(session.context.location_id) == "mist_salt_well"


func _save_viewport(path: String, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[V5 PLAYABLE COMBAT RENDER SKIP] Headless texture unavailable")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		"user://tests"
	))
	var texture: ViewportTexture = root.get_texture()
	var image: Image = texture.get_image()
	_check(image.save_png(path) == OK, label)
	print("[V5 PLAYABLE COMBAT RENDER PATH] %s" % (
		ProjectSettings.globalize_path(path)
	))


func _button_text_contains(container: Node, needle: String) -> bool:
	for child: Node in container.get_children():
		if child is Button and needle in (child as Button).text:
			return true
	return false


func _has_combat_button(container: Node) -> bool:
	for child: Node in container.get_children():
		if (
			child is Button
			and str(child.get_meta("combat_option_id", "")) != ""
		):
			return true
	return false


func _inside_viewport(rect: Rect2, viewport_size: Vector2) -> bool:
	return (
		rect.position.x >= 0.0
		and rect.position.y >= 0.0
		and rect.end.x <= viewport_size.x
		and rect.end.y <= viewport_size.y
	)


func _children_inside(container: Control, visible_rect: Rect2) -> bool:
	for child: Node in container.get_children():
		if child is Control and not visible_rect.encloses(
			(child as Control).get_global_rect()
		):
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[V5 PLAYABLE COMBAT RENDER PASS] " + label)
		return
	failures.append(label)


func _fail(label: String) -> void:
	failures.append(label)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 PLAYABLE COMBAT RENDER RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 PLAYABLE COMBAT RENDER FAIL] " + failure)
	print(
		"[V5 PLAYABLE COMBAT RENDER RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)
