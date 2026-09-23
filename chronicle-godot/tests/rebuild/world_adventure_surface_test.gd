extends "res://tests/rebuild/world_demo_surface_test.gd"

const IntegrationOptions = preload("res://tests/sim/world_integration_contract_test.gd")


func _run() -> void:
	output = "user://tests/world_adventure_evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var prepared := Live.new()
	var settings := IntegrationOptions.options()
	settings.integration_rules_version = 2
	_check(prepared.start(settings).success, "isolated adventure world starts")
	_check(prepared.perform_travel("generated_route.echo_landing.commons_to_reed_craft").success, "prepare with legal travel")
	_check(prepared.act_player_life("work:recipe.hand_twist_cord").get("work_completed", false), "prepare with legal first tool")
	_check(prepared.act_player_life("work:recipe.woven_sap").get("work_completed", false), "prepare with legal crafted weapon")
	var actions: Array = prepared.session.PlayerLife.Equipment.options(prepared.session).filter(func(o: Dictionary) -> bool: return str(o.action_id).begins_with("equip:"))
	if actions.is_empty():
		_check(false, "legal equipment command required")
		quit(1)
		return
	_check(prepared.act_player_life(actions[0].action_id).success, "prepare with legal equip")
	_check(prepared.save_to_path(path, true).success, "isolated native crafted checkpoint")
	var viewer = Demo.instantiate()
	viewer.save_path = path
	viewer.initial_content_extension = true
	root.add_child(viewer)
	await process_frame
	await process_frame
	_check(viewer.current_view_data.get("equipment_journal", {}).get("items", []).size() >= 3, "UI loads legally crafted native inventory")
	var journal: VBoxContainer = viewer._equipment_journal
	viewer.surface.tabs.current_tab = journal.get_index()
	var before := _signature(viewer.view_model)
	for category: String in ["items", "features", "catalog"]:
		journal.category = category
		for page: int in range(ceili(float(journal.data.get(category, []).size()) / 3.0)):
			journal.page = page
			journal._render()
			await process_frame
			await process_frame
			_check(journal.next.get_global_rect().end.y <= root.size.y, "%s page %d fits 720p without nested scrolling" % [category, page])
			await _screenshot("%s_%d_720.png" % [category, page])
	_check(_signature(viewer.view_model) == before, "reading every item and growth page does not mutate the world")
	journal.category = "items"
	journal.page = 0
	journal._render()
	await process_frame
	var commands: Array = journal.entries.find_children("*", "Button", true, false)
	_check(not commands.is_empty(), "equipped item offers real take-off command")
	if not commands.is_empty():
		(commands[0] as Button).pressed.emit()
		await _settle(viewer)
		_check(viewer.view_model.session.stores.equipment_store.get_equipped_item_id("player", "main_hand") == "", "journal UI button really clears equipped weapon")
		await _screenshot("after_unequip_720.png")
	viewer.surface.tabs.current_tab = 0
	await process_frame
	await _screenshot("adventure_scene_720.png")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "expanded crafting choices keep scene dock on screen")
	viewer.queue_free()
	await process_frame
	print("WORLD_ADVENTURE_SURFACE %d/%d" % [checks - failures.size(), checks])
	print("ADVENTURE_RENDER_PATH " + ProjectSettings.globalize_path(output))
	quit(0 if failures.is_empty() else 1)
