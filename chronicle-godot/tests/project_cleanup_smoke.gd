extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[SMOKE PASS] ", message)
	else:
		failures.append(message)
		push_error("[SMOKE FAIL] " + message)


func _find_action_button(node: Node) -> Button:
	if node.is_queued_for_deletion() or (node is Control and not node.is_visible_in_tree()):
		return null
	for child in node.get_children():
		if child.is_queued_for_deletion() or (child is Control and not child.is_visible_in_tree()):
			continue
		if child is Button:
			var button := child as Button
			if not button.disabled and button.custom_minimum_size.y >= 70:
				return button
		var nested := _find_action_button(child)
		if nested != null:
			return nested
	return null


func _wait_for_action_guard(story_player: Node) -> void:
	# The UI guard uses wall time, not the simulated frame delta of SceneTreeTimer.
	while Time.get_ticks_msec() - int(story_player.get("_last_action_ms")) < 90:
		await process_frame


func _story_has_content(story_box: RichTextLabel) -> bool:
	return story_box != null and story_box.get_parsed_text().strip_edges() != ""


func _run() -> void:
	var packed := load("res://scenes/ui/mainui.tscn") as PackedScene
	_check(packed != null, "mainui.tscn can be loaded")
	if packed == null:
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var story_player := scene.get_node_or_null("StoryPlayer")
	_check(story_player != null, "StoryPlayer is present")
	if story_player == null:
		quit(1)
		return

	var story_box := story_player.get_node_or_null("StoryBox") as RichTextLabel
	var choices_box := story_player.get_node_or_null("ChoicesBox") as VBoxContainer
	var restart_button := story_player.get_node_or_null("Btns/RestartBtn") as Button
	var new_run_button := story_player.get_node_or_null("Btns/NewRunBtn") as Button
	var continue_button := story_player.get_node_or_null("Btns/ContinueBtn") as Button

	_check(_story_has_content(story_box), "initial story text is rendered")
	_check(choices_box != null, "choice panel is present")
	_check(continue_button != null and not continue_button.disabled, "continue button is available")
	_check(restart_button != null and not restart_button.disabled, "restart button is available")
	_check(new_run_button != null and not new_run_button.disabled, "new journey button is available")

	var initial_world: Node = story_player.get("world") as Node
	_check(initial_world != null, "world runtime is created")

	await _wait_for_action_guard(story_player)
	continue_button.pressed.emit()
	await process_frame
	_check(_story_has_content(story_box), "continue action runs without clearing the story")

	var action_button := _find_action_button(choices_box)
	_check(action_button != null, "at least one selectable action is rendered")
	if action_button != null:
		await _wait_for_action_guard(story_player)
		var text_before_choice := story_box.get_parsed_text()
		action_button.pressed.emit()
		await process_frame
		var world_after_choice: Node = story_player.get("world") as Node
		_check(
			world_after_choice != null and (
				world_after_choice.has_pending_choice()
				or story_box.get_parsed_text() != text_before_choice
			),
			"selecting an action enters a choice or renders its resolved result"
		)

	await _wait_for_action_guard(story_player)
	restart_button.pressed.emit()
	await process_frame
	var world_after_restart: Node = story_player.get("world") as Node
	_check(
		world_after_restart != null and world_after_restart != initial_world,
		"restart creates a fresh world runtime"
	)

	await _wait_for_action_guard(story_player)
	new_run_button.pressed.emit()
	await process_frame
	var world_after_new_run: Node = story_player.get("world") as Node
	_check(
		world_after_new_run != null and world_after_new_run != world_after_restart,
		"new journey creates another fresh world runtime"
	)

	scene.queue_free()
	await process_frame

	if failures.is_empty():
		print("[SMOKE RESULT] PASS")
		quit(0)
	else:
		print("[SMOKE RESULT] FAIL: ", failures)
		quit(1)
