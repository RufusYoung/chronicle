extends SceneTree

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var failures: Array = []
var output := "user://tests/worksite_food_storage_render"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	root.add_child(viewer)
	await process_frame
	_check(viewer.view_model.start({"scenario": "echo_realm", "food_carting_version": 1, "worksite_food_storage_version": 1}).success, "opt-in rules start without NPC injection")
	viewer.refresh_view()
	for destination: String in ["generated_location.echo_terrace.commons", "generated_location.echo_terrace.terraces"]:
		var route := ""
		for option: Dictionary in viewer.view_model.session.get_travel_options():
			if option.to_location_id == destination:
				route = option.route_id
		_check(route != "", "legal travel to " + destination)
		if route == "":
			break
		viewer.perform_travel(route)
		await _settle(viewer)
	var saw_stock := false
	var saw_absence := false
	for hour: int in range(24):
		viewer.wait_button.pressed.emit()
		await _settle(viewer)
		for row: Dictionary in viewer.current_view_data.get("visible_observations", []):
			if "worksite_food_store." not in str(row.id):
				continue
			var quantity := 0
			for item: Dictionary in viewer.view_model.session.stores.item_store.list_items_for_owner(str(row.id)):
				quantity += int(item.quantity)
			_check("现场存粮 %d 份" % quantity in str(row.state_text), "visible count is current real stock")
			_check(str(row.state_text) in viewer.visible_observations.text, "actual scene text contains stock, not only view-model data")
			if quantity > 0 and not saw_stock:
				saw_stock = true
				await _capture("stock")
			if quantity > 0 and "主人不在场" in str(row.state_text):
				saw_absence = true
				await _capture("owner_away")
		if saw_stock and saw_absence:
			break
	_check(saw_stock and saw_absence, "owner leaves but food remains visible in place")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "720p action area stays on screen")
	_check(viewer.view_model.session.action_count == 0, "program-driven UI observation is not human play")
	_check(viewer.view_model.session.validate_persistent_references().ok, "rendered world passes reference audit")
	viewer.queue_free()
	await process_frame
	print("WORKSITE_FOOD_STORAGE_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func _settle(viewer: Variant) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while viewer.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	if viewer.busy:
		viewer._worker.wait_to_finish()
		viewer._worker = null
		viewer.busy = false
		_check(false, "operation timeout")
	await process_frame
	_check(viewer.last_operation.get("result", {}).get("success", false), "UI operation succeeds")


func _capture(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/" + name + ".png")


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
