extends "res://tests/rebuild/work_framework_render_test.gd"

const Life = preload("res://scripts/sim/player/player_life.gd")
const Tx = preload("res://scripts/sim/transaction/transaction_result.gd")


func _run() -> void:
	output = "user://tests/player_local_life_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_player_life = true
	root.add_child(viewer)
	await process_frame
	var target := _prepare_market(viewer.view_model.session)
	viewer.refresh_view()
	await process_frame
	_check(viewer.surface.action_groups.visible, "life actions have purpose filters in the shared surface")
	_check(viewer.current_view_data.actions.all(func(row: Dictionary) -> bool: return not row.has("statement") and not row.has("offer") and not row.has("report")), "public choices do not reveal the unread statement or private trade policy")
	var ask := "ask_local:" + target
	await _click_action(viewer, ask)
	_check("我平常在" in viewer.surface.receipt.text and "一轮要" in viewer.surface.receipt.text, "complete conversation states workplace and real work time")
	_check(viewer.current_view_data.local_information.size() == 1, "speaker and dated knowledge persist after conversation")
	_check(not viewer.current_view_data.actions.any(func(row: Dictionary) -> bool: return row.action_id == ask), "same unchanged question is gone after reading")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "long first-hand information with multiple exits fits 720p")
	await _capture("local_information_720")
	var open: LinkButton = viewer.get_node("%OpenResultReceipt")
	open.pressed.emit()
	await process_frame
	_check(viewer.surface.receipt.is_visible_in_tree(), "full conversation is reachable through normal result link")
	await _capture("information_record_720")
	(viewer.get_node("%BackToScene") as Button).pressed.emit()
	await process_frame
	var sale := ""
	for row: Dictionary in viewer.current_view_data.actions:
		if str(row.action_id).begins_with("sell_food:" + target) and row.can_execute:
			sale = row.action_id
	_check(sale != "", "controlled funded buyer offers a visible sale")
	if sale != "":
		var before: int = viewer.current_view_data.player.coins
		await _click_action(viewer, sale)
		_check(viewer.current_view_data.player.coins > before, "actual sale callback credits real transferred money")
		_check("收到" in viewer.surface.receipt.text and "铜币" in viewer.surface.receipt.text, "receipt spells out goods, payment and recipient")
		_check(not viewer.current_view_data.player_life_followups.is_empty(), "actual later meal appears in player-visible knowledge")
		_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "trade and meal aftermath controls fit 720p")
		await _capture("sale_and_meal_720")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	viewer.refresh_view()
	await process_frame
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "same common layout fits 900p")
	await _capture("sale_and_meal_900")
	viewer.queue_free()
	await process_frame
	print("PLAYER_LOCAL_LIFE_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func _prepare_market(session: Variant) -> String:
	var snapshot: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var target := ""
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if "generated_resident" in person.get("tags", []) and int(person.states.get("age_years", 0)) >= 18 \
				and Life.Treasury.new(snapshot).balance(str(person.id)) >= 6:
			target = person.id
			break
	var result := Tx.new()
	result.add_fact({"fact_id": "test_injection.local_life_render", "fact_type": "test_injection",
		"summary": "测试注入：将原有有钱成人放在现场并给予饥饿处境，玩家持有测试余粮；验证真实窗口和按钮，不称为自然游玩。"})
	for pair: Array in [["location_id", session.context.location_id], ["home_location_id", session.context.location_id],
		["daily_route_id", ""], ["daily_destination_id", ""], ["daily_travel_remaining", 0], ["daily_activity", "resting"],
		["hunger", "high"], ["hunger_elapsed_hours", 0], ["fatigue", 9]]:
		Life.set_state(result, target, str(pair[0]), pair[1])
	result.add_item_change({"operation": "create", "item": {"item_instance_id": "test.player.render_food", "item_def_id": "item.fresh_fish_portion",
		"holder": {"kind": "entity", "id": "player"}, "quantity": 8}, "source_fact_ids": ["test_injection.local_life_render"]})
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "controlled UI fixture uses authoritative writer")
	return target


func _click_action(viewer: Variant, id: String) -> void:
	var before: int = viewer.view_model.session.elapsed_hours_since_start
	var target: Button
	for button: Button in viewer.action_buttons.get_children():
		if str(button.get_meta("action_id", "")) == id:
			target = button
			break
	_check(target != null, "rendered action exists: " + id)
	if target == null:
		return
	for button: Button in viewer.surface.action_groups.get_children():
		if button.get_meta("action_group", "") == target.get_meta("life_group", ""):
			button.button_pressed = true
			button.pressed.emit()
			break
	await process_frame
	for index: int in range(10):
		if target.is_visible_in_tree():
			break
		(viewer.surface.next as Button).pressed.emit()
		await process_frame
	_check(target.is_visible_in_tree() and not target.disabled, "action is reachable through filters and normal pagination")
	_check(viewer.view_model.session.elapsed_hours_since_start == before, "filtering and pagination never spend game time")
	target.pressed.emit()
	await _settle(viewer)
