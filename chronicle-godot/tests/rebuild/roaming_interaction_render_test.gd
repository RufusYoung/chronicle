extends "res://tests/rebuild/roaming_player_render_test.gd"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = "user://tests/roaming_interaction_render"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var viewer = Scene.instantiate()
	viewer.economy_variant = "world_roaming_v1"
	viewer.auto_load = false
	viewer.slot = "roaming_interaction_test"
	root.add_child(viewer)
	await settled(viewer)
	await act(viewer, "adventure:arrival_signs:own")
	await act(viewer, "journey_route.generated_location.echo_landing.commons.journey_location.forest_edge")
	await act(viewer, "adventure:forest_sound:tracks")
	await act(viewer, "adventure:forest_satchel:take")
	var equips: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("equip:") and "短鞭" in str(c.label))
	check(not equips.is_empty(), "explored weapon offers equipment action")
	if not equips.is_empty():
		await act(viewer, str(equips[0].id))
	viewer._navigate("inventory")
	for offset: int in range(0, viewer.response.observation.equipment_journal.items.size(), 2):
		viewer.offset = offset
		viewer._render()
		await layout_check(viewer, "inventory_" + str(offset))
	await act(viewer, "journey_route.journey_location.forest_edge.journey_location.broken_bridge")
	viewer.pending_result = false
	viewer._navigate("scene")
	await layout_check(viewer, "bridge_four_choices")
	check(viewer.Presentation.build(viewer.response, "scene").choices.size() == 4, "four real alternatives, including refusal, remain available")
	await act(viewer, "adventure:bridge_crossing:round")
	await layout_check(viewer, "bridge_result")
	viewer._begin("save", {"slot": viewer.slot, "overwrite": true})
	await settled(viewer)
	var saved_time: Dictionary = viewer.response.observation.time.duplicate(true)
	await act(viewer, "adventure:bridge_equipment:shoes")
	viewer._begin("load", {"slot": viewer.slot})
	await settled(viewer)
	check(viewer.response.observation.time == saved_time, "UI restores native time")
	check(viewer.response.observation.journey_event.id == "bridge_equipment", "UI restores unresolved alternative")
	await act(viewer, "adventure:bridge_equipment:shoes")
	await act(viewer, "journey_route.journey_location.broken_bridge.journey_location.forest_edge")
	await act(viewer, "adventure:forest_return:mark")
	await act(viewer, "journey_route.journey_location.forest_edge.generated_location.echo_landing.commons")
	await act(viewer, "generated_route.echo_landing.commons_to_fishery")
	for category: String in ["talk", "trade", "rest", "work"]:
		viewer._navigate(category)
		await layout_check(viewer, "at_fishery_" + category)
		var rows: Array = viewer.Presentation.build(viewer.response, category).choices
		var groups := {}
		for row: Dictionary in rows:
			var family: String = viewer.Presentation.family(row)
			if family != "":
				groups[family] = true
		for family: String in groups:
			viewer.family = family
			viewer.offset = 0
			viewer._render()
			await layout_check(viewer, "expanded_" + category + str(groups.keys().find(family)))
	var sales: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("sell_food:") and c.enabled)
	check(not sales.is_empty(), "present funded food buyer reachable in normal UI play")
	if not sales.is_empty():
		var coins: int = viewer.response.observation.player.coins
		await act(viewer, sales[0].id)
		check(viewer.response.observation.player.coins > coins, "real sale increases player coins")
		await layout_check(viewer, "food_sale_result")
	var questions: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("ask_local:") and c.enabled)
	if not questions.is_empty():
		await act(viewer, questions[0].id)
		check("答复" in viewer.response.observation.feedback.title, "named concrete conversation feedback")
		var inline_text: String = viewer._story.find_child("InlineOutcome", true, false).text
		check("废灯台" in inline_text and "材料：" not in inline_text, "useful directions visible without duplicated full work description")
		check(viewer.response.choices.all(func(c: Dictionary) -> bool: return not str(c.id).begins_with("ask_local:")), "same local question does not return")
		await layout_check(viewer, "local_answer")
	viewer._begin("start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_roaming_v1"})
	await settled(viewer)
	var roads: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel" and ".network." in str(c.id))
	check(not roads.is_empty(), "other settlement reachable")
	if not roads.is_empty():
		await act(viewer, str(roads[0].id))
		while viewer.response.observation.player.travel_remaining > 0:
			await act(viewer, "continue")
		var fields: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel" and "坡田" in str(c.destination_name))
		check(not fields.is_empty(), "real field route")
		if not fields.is_empty():
			await act(viewer, str(fields[0].id))
			viewer.pending_result = false
			viewer._navigate("scene")
			check(viewer.response.observation.risk.get("encounter", false), "natural threat encountered without state injection")
			await layout_check(viewer, "combat_start")
			var initial_time: Dictionary = viewer.response.observation.time.duplicate(true)
			(viewer._choices.get_child(0) as Button).pressed.emit()
			await process_frame
			await process_frame
			check(viewer._dialog.visible and "健康" in viewer._dialog.dialog_text, "actual combat button discloses failure damage before execution")
			check(viewer._dialog.size.y < root.size.y, "combat confirmation fits 720p")
			viewer._dialog.hide()
			check(viewer.response.observation.time == initial_time, "reading and cancelling combat cost does not spend a round")
			var rounds := 0
			for index: int in range(12):
				var combat: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.kind == "combat_encounter")
				if combat.is_empty():
					break
				var approach := ":strike" if index % 3 == 2 else ":guard"
				var match_rows: Array = combat.filter(func(c: Dictionary) -> bool: return str(c.id).ends_with(approach))
				await act(viewer, str(match_rows[0].id if not match_rows.is_empty() else combat[0].id))
				rounds += 1
				await layout_check(viewer, "combat_result_" + str(rounds))
			check(rounds > 0, "multiple real combat callbacks tested")
			check(viewer.response.choices.all(func(c: Dictionary) -> bool: return c.kind != "combat_encounter"), "threat eventually ends")
			check("结束" in viewer.response.observation.feedback.title or "脱离" in viewer.response.observation.feedback.title, "ending is named in feedback")
			var ending: String = viewer._story.find_child("InlineOutcome", true, false).text if not viewer.pending_result else viewer._paragraph.text
			check("退" in ending or "离开" in ending or "吃饱" in ending, "actual end cause visible without opening log")
	viewer.queue_free()
	await process_frame
	print("ROAMING_INTERACTION_RENDER " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func act(viewer: Variant, id: String) -> void:
	var rows: Array = viewer.response.choices.filter(func(c: Dictionary) -> bool: return c.id == id and c.enabled)
	check(not rows.is_empty(), "legal action available " + id)
	if rows.is_empty():
		return
	viewer._begin("act", {"choice_id": rows[0].choice_id, "confirm": true})
	await settled(viewer)
	check(viewer.response.ok, "action settled " + id)


func layout_check(viewer: Variant, name: String) -> void:
	await process_frame
	await process_frame
	check(viewer._root.get_global_rect().end.y <= root.size.y, "entire interface fits " + name)
	check(viewer._story.get_global_rect().end.y <= root.size.y - 50, "story fits " + name)
	await capture(name)
