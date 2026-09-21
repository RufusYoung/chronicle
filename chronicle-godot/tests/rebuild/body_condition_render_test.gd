extends "res://tests/rebuild/player_local_life_render_test.gd"


func _run() -> void:
	output = "user://tests/body_condition_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_content_extension = true
	root.add_child(viewer)
	await process_frame
	var session: Variant = viewer.view_model.session
	_check(session.fixture_source_data.body_rules.version == 1, "new-world UI opts into explicit body rules")
	var setup := Tx.new()
	setup.add_fact({"fact_id": "test.body.render", "fact_type": "test_injection", "summary": "测试注入：极饿伤身前一小时，检查公开预告、等待后的真实结果和进食止损。"})
	for pair: Array in [["health", 50], ["hunger", "extreme"], ["hunger_strain_hours", 5]]:
		Life.set_state(setup, "player", pair[0], pair[1])
	setup.mark_resolved("test_injection")
	_check(session.writer.apply_result(setup, session.stores), "controlled UI body setup commits")
	viewer.refresh_view()
	await process_frame
	_check("再持续1小时" in JSON.stringify(viewer.current_view_data.decision), "warning exposes imminent cost before choosing")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "extreme hunger and actual choices fit 720p")
	await _capture("hungry_720")
	viewer.wait_button.pressed.emit()
	await _settle(viewer)
	_check(viewer.current_view_data.player.health == 48, "wait callback applies real health loss")
	_check("持续极饿" in viewer.surface.receipt.text and "48" in viewer.surface.receipt.text, "wait receipt tells why health fell, not only a hidden counter")
	await _capture("cost_720")
	await _click_action(viewer, "eat")
	_check(viewer.current_view_data.player.health == 48 and viewer.current_view_data.player.hunger == "medium", "meal stops strain without fabricating healing")
	await _click_action(viewer, "rest")
	_check(viewer.current_view_data.player.health == 51, "real meal plus rest restores body")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "recovery layout fits 900p")
	await _capture("recovered_900")
	viewer.queue_free()
	await process_frame
	print("BODY_CONDITION_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
