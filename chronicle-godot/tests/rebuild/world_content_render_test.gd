extends "res://tests/rebuild/player_local_life_render_test.gd"


func _run() -> void:
	output = "user://tests/world_content_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_content_extension = true
	root.add_child(viewer)
	await process_frame
	_check(viewer.view_model.session.fixture_source_data.has("content_extension"), "new world UI explicitly selects the content bundle")
	_check(viewer._player_life.button_pressed and viewer._content_extension.button_pressed, "new world form reflects effective life rules")
	var details: Array = viewer.view_model._result_detail_lines({"state_changes": [
		{"entity_id": "player", "key": "danger_advantage", "to": 2},
		{"entity_id": "player", "key": "danger_round_hour", "to": 10},
		{"entity_id": "player", "key": "danger_opponent_id", "to": "threat"},
		{"entity_id": "player", "key": "health", "delta": -3}]}, {}, false)
	_check(details.size() == 1 and "健康" in str(details[0]), "combat bookkeeping is hidden while real damage remains visible")
	var previous: Dictionary = viewer.view_model.latest_result.duplicate(true)
	viewer.view_model.latest_result = {"success": true, "transaction_result": {
		"state_changes": [{"entity_id": "player", "key": "danger_advantage", "to": 2},
			{"entity_id": "player", "key": "danger_opponent_id", "to": "threat"},
			{"entity_id": "player", "key": "danger_round_hour", "to": 10}],
		"narrative_result": {"world_danger": true, "summary": "稳住了距离，积累 2 点优势。"}}}
	var feedback: Dictionary = viewer.view_model._combat_encounter_feedback_view()
	_check(not "danger_" in JSON.stringify(feedback) and "积累 2 点优势" in feedback.body, "actual combat receipt preserves tactical information without internal fields")
	viewer.view_model.latest_result = previous
	viewer.restart_dialog.popup_centered()
	await process_frame
	_check(viewer.restart_dialog.get_ok_button().get_global_rect().end.y <= root.size.y, "new world confirmation is reachable at 720p")
	await _capture("new_world_720")
	viewer.restart_dialog.hide()
	viewer.surface.tabs.current_tab = 1
	await process_frame
	_check(viewer._picture.visible and viewer._picture.texture == viewer.ECHO_ART, "canon world shows its own illustration, not prototype art")
	_check(viewer._picture_caption.get_global_rect().end.y <= root.size.y, "illustration and static-world disclaimer fit 720p")
	await _capture("region_art_720")
	viewer._canon_details_button.pressed.emit()
	await process_frame
	_check(viewer._canon_details.visible and viewer._canon_details.size.y <= root.size.y, "complete original-world background remains accessible")
	await _capture("canon_background_720")
	viewer._canon_details.hide()
	viewer.surface.tabs.current_tab = 0
	# The legacy incident wrapper remains a saved-world contract, not the v2 adventure UI.
	var legacy_options: Dictionary = viewer._world_options(81001, true, true, true, true, true, true)
	legacy_options.erase("journey_rules_version")
	_check(viewer.view_model.start(legacy_options).success, "legacy content profile still starts without journey rules")
	var target := _prepare_market(viewer.view_model.session)
	var visible := Tx.new()
	Life.set_state(visible, target, "visible", true)
	visible.mark_resolved("test_injection")
	_check(viewer.view_model.session.writer.apply_result(visible, viewer.view_model.session.stores), "controlled person is visibly present at the public site")
	viewer.refresh_view()
	await process_frame
	var choices: Array = viewer.current_view_data.actions.filter(func(row: Dictionary) -> bool: return row.get("incident_id") == "food_at_hand")
	_check(viewer.current_view_data.visible_people.any(func(person: Dictionary) -> bool: return person.id == target), "the incident's counterpart is shown in the scene")
	_check(choices.size() == 2 and choices.all(func(row: Dictionary) -> bool: return row.life_group == "incident"), "both incident alternatives stay in the same purpose group")
	for button: Button in viewer.surface.action_groups.get_children():
		if button.get_meta("action_group", "") == "incident":
			button.button_pressed = true
			button.pressed.emit()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "conditional context and both choices fit 720p")
	await _capture("incident_choices_720")
	var coins: int = viewer.current_view_data.player.coins
	if not choices.is_empty():
		var sale: Dictionary = choices.filter(func(row: Dictionary) -> bool: return str(row.action_id).ends_with(":offer"))[0]
		await _click_action(viewer, sale.action_id)
		_check(viewer.current_view_data.player.coins > coins, "rendered incident callback performs a real paid sale")
		_check(not viewer.current_view_data.actions.any(func(row: Dictionary) -> bool: return row.get("incident_id") == "food_at_hand"), "resolved contextual choices disappear from actual UI")
		_check("铜币" in viewer.surface.receipt.text, "actual outcome names payment, not a generic remembered-information line")
		await _capture("incident_result_720")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "content layout also fits 900p")
	await _capture("incident_result_900")
	viewer.queue_free()
	await process_frame
	print("WORLD_CONTENT_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
