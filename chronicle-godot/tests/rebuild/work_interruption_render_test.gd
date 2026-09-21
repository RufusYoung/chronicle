extends "res://tests/rebuild/player_local_life_render_test.gd"


func _run() -> void:
	output = "user://tests/work_interruption_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_seed = 86021
	viewer.initial_content_extension = true
	# This regression's timetable belongs to the previous bootstrap, not new-world balance.
	var legacy = preload("res://scripts/rebuild/v5_live_location_view_model.gd").new()
	var options: Dictionary = preload("res://tests/sim/world_integration_contract_test.gd").options(86021)
	options.erase("integration_rules_version")
	options.erase("community_rules_version")
	_check(legacy.start(options).success, "legacy interruption timetable starts explicitly")
	_check(legacy.save_to_path(viewer.save_path, true).success, "legacy bootstrap persists for actual UI restore")
	root.add_child(viewer)
	await process_frame
	viewer.perform_travel("generated_route.echo_landing.commons_to_fishery")
	await _settle(viewer)
	await _click_action(viewer, "gather:net_fisher")
	await _click_action(viewer, "ask_local:generated_resident.echo_landing.001")
	await _click_action(viewer, "help:generated_resident.echo_landing.001:net_fisher")
	_check(viewer.current_view_data.feedback.status == "interrupted", "formal UI callback gives interrupted status")
	_check("陶苇已离开现场" in viewer.feedback_body.text and "2/4" in viewer.feedback_body.text, "visible result names actual cause and work progress")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "interrupted work with crowded workplace fits720p")
	await _capture("interrupted_720")
	viewer.get_node("%OpenResultReceipt").pressed.emit()
	await process_frame
	_check("同一雇主在场且能付款" in viewer.surface.receipt.text, "full result retains conditions for continuation")
	await _capture("receipt_720")
	viewer.get_node("%BackToScene").pressed.emit()
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "interrupted work fits900p")
	await _capture("interrupted_900")
	viewer.queue_free()
	await process_frame
	print("WORK_INTERRUPTION_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
