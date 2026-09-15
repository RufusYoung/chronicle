extends "res://tests/rebuild/player_local_life_render_test.gd"


func _run() -> void:
	output = "user://tests/world_provisions_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_content_extension = true
	root.add_child(viewer)
	await process_frame
	var session: Variant = viewer.view_model.session
	_check(session.fixture_source_data.content_extension.version == 2, "new world selects explicit provisions v2")
	var injection := Tx.new()
	injection.add_fact({"fact_id": "test.provisions.render", "fact_type": "test_injection", "summary": "测试注入：给旅人两类食品，检查选择、实际进食和信息布局。"})
	for id: String in ["item.fresh_fish_portion", "item.smoked_lake_fish"]:
		injection.add_item_change({"operation": "create", "item": {"item_instance_id": "test.render." + id, "item_def_id": id,
			"holder": {"kind": "entity", "id": "player"}, "quantity": 1}, "source_fact_ids": ["test.provisions.render"]})
	Life.set_state(injection, "player", "hunger", "high")
	injection.mark_resolved("test_injection")
	_check(session.writer.apply_result(injection, session.stores), "controlled rendering setup commits")
	viewer.refresh_view()
	await process_frame
	var meals: Array = viewer.current_view_data.actions.filter(func(r: Dictionary) -> bool: return r.has("meal_item_id"))
	_check(meals.any(func(r: Dictionary) -> bool: return "鲜鱼" in r.label) and meals.any(func(r: Dictionary) -> bool: return "熏湖鱼" in r.label), "raw and prepared food are separate explicit choices without hiding initial rations")
	var cooked: Dictionary = meals.filter(func(r: Dictionary) -> bool: return r.satiation_hours == 6)[0]
	_check("6小时" in cooked.hint and "1份" in cooked.hint, "choice exposes actual duration and cost")
	await _capture("meal_choices_720")
	await _click_action(viewer, cooked.action_id)
	_check("6小时" in viewer.surface.receipt.text and "熏湖鱼" in viewer.surface.receipt.text, "actual meal receipt states what was eaten and the benefit")
	_check(viewer.current_view_data.player.satiation_remaining_hours == 5, "UI subtracts the hour actually spent eating")
	_check("还能维持5小时" in JSON.stringify(viewer.current_view_data.decision), "decision panel names remaining satiety")
	_check(not viewer.current_view_data.actions.any(func(r: Dictionary) -> bool: return r.get("meal_item_id") == cooked.meal_item_id), "consumed last prepared portion disappears")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "actual decision dock fits 720p")
	await _capture("meal_result_720")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "same decision layout fits 900p")
	await _capture("meal_result_900")
	viewer.queue_free()
	await process_frame
	print("WORLD_PROVISIONS_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
