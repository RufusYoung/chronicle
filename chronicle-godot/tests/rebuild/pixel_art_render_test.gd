extends "res://tests/rebuild/world_demo_surface_test.gd"

const Portraits = preload("res://scripts/rebuild/pixel_portraits.gd")
const Options = preload("res://tests/sim/world_integration_contract_test.gd")


func _run() -> void:
	output = "user://tests/pixel_art_evidence"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var prepared := Live.new()
	var settings := Options.options()
	settings.integration_rules_version = 2
	_check(prepared.start(settings).success, "new world starts")
	_check(prepared.perform_travel(_route_to(prepared, "generated_location.echo_landing.landing")).success, "legally visit the landing")
	for hour: int in 12:
		if not prepared.build_view_data().visible_people.is_empty():
			break
		prepared.advance_time()
	_check(not prepared.build_view_data().visible_people.is_empty(), "a resident actually arrives without injection")
	_check(prepared.save_to_path(path, true).success, "native checkpoint")
	var viewer = Demo.instantiate()
	viewer.save_path = path
	root.add_child(viewer)
	await process_frame
	await process_frame
	var before := _signature(viewer.view_model)
	for height: int in [720, 900]:
		root.size = Vector2i(1280 if height == 720 else 1600, height)
		root.content_scale_size = root.size
		viewer.surface.tabs.current_tab = 0
		await process_frame
		await process_frame
		_check(viewer.action_dock.get_global_rect().end.y <= height, "portrait scene dock fits %dp" % height)
		_check(viewer.visible_people.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "portraits use nearest-neighbor")
		_check(not viewer.current_view_data.visible_people.filter(func(row: Dictionary) -> bool: return row.get("portrait_age", -1) >= 0).is_empty(), "present generated residents have age-aware portraits")
		await _screenshot("people_%d.png" % height)
		var records := viewer.surface.tabs.get_node("记录") as ScrollContainer
		viewer.surface.tabs.current_tab = records.get_index()
		await process_frame
		_check(viewer.surface.portraits.get_child_count() > 0, "record details show larger present-person portraits")
		records.ensure_control_visible(viewer.surface.portraits)
		await process_frame
		_check(viewer.surface.portraits.is_visible_in_tree(), "portrait details tab is actually selected")
		_check(viewer.surface.portraits.get_global_rect().intersects(records.get_global_rect()), "larger portraits are inside the visible records viewport")
		await _screenshot("portrait_details_%d.png" % height)
		viewer.surface.tabs.current_tab = viewer._graph.get_parent().get_parent().get_index()
		await process_frame
		_check(viewer._picture.texture.resource_path.ends_with("echo_port_landing_pixel_v1.png"), "canon location uses pixel version")
		_check(viewer._picture.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "scene uses nearest-neighbor")
		await _screenshot("region_%d.png" % height)
		viewer._picture.texture = viewer.REED_ART
		await process_frame
		await _screenshot("legacy_art_review_%d.png" % height)
		viewer._picture.texture = viewer.ECHO_ART
	_check(_signature(viewer.view_model) == before, "art and viewport navigation do not change native world or RNG")
	for age: int in [8, 30, 75]:
		for number: int in range(1, 5):
			var id := "generated_resident.echo_landing.%03d" % number
			var cell := Portraits.cell(id, age)
			_check(cell / 4 == (0 if age < 18 else (2 if age >= 65 else 1)), "age band matches actual age")
			_check(cell == Portraits.cell(id, age), "portrait identity is stable")
	_check(Portraits.portrait("chen_mi", 30) == null, "no guessed portrait for authored legacy character")
	_check(Portraits.portrait("generated_resident.unknown", -1) == null, "unknown age has no invented portrait")
	viewer.queue_free()
	await process_frame
	print("PIXEL_ART_RENDER %d/%d" % [checks - failures.size(), checks])
	print("PIXEL_RENDER_PATH " + ProjectSettings.globalize_path(output))
	quit(0 if failures.is_empty() else 1)
