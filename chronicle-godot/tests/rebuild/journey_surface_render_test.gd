extends "res://tests/rebuild/player_local_life_render_test.gd"

const JourneyContract = preload("res://tests/sim/journey_content_contract_test.gd")


func _run() -> void:
	output = "user://tests/journey_surface_render"
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var viewer = Demo.instantiate()
	viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
	viewer.initial_content_extension = true
	root.add_child(viewer)
	await process_frame
	_check(viewer.view_model.session.fixture_source_data.has("journey_rules"), "default new world opts into versioned journey content")
	_check(JourneyContract.go(viewer.view_model, "generated_location.echo_landing.landing"), "formal travel to first short adventure")
	viewer.refresh_view()
	await process_frame
	_check("水里的敲击声" in viewer.location_description.text, "event situation is visible before choosing")
	_check(viewer.current_view_data.actions.any(func(a: Dictionary) -> bool: return a.action_id == "adventure:shore_box:leave" and a.hours == 0), "decline is a real no-time choice")
	_check(viewer.action_dock.get_global_rect().end.y <= root.size.y, "adventure cards fit 720p")
	await _capture("shore_choices_720")
	await _click_action(viewer, "adventure:shore_box:hook")
	_check("收入行囊" in viewer.surface.receipt.text, "actual choice shows concrete acquired goods")
	_check(not viewer.current_view_data.actions.any(func(a: Dictionary) -> bool: return str(a.action_id).begins_with("adventure:shore_box:")), "resolved adventure choices disappear")
	await _capture("shore_result_720")
	_check(JourneyContract.go(viewer.view_model, "journey_location.lake_cave"), "formal travel to cave")
	viewer.view_model.act_player_life("adventure:cave_marks:skip")
	viewer.refresh_view()
	await process_frame
	_check("岩台上的包裹" in viewer.location_description.text, "conditional continuation is explained")
	await _capture("cave_choices_720")
	var dialog_button: Button
	for button: Button in viewer.action_buttons.get_children():
		if button.get_meta("action_id", "") == "adventure:cave_bundle:rope":
			dialog_button = button
	_check(dialog_button != null, "rope choice is reachable in shared surface")
	if dialog_button != null:
		var elapsed: int = viewer.view_model.session.elapsed_hours_since_start
		viewer._show_action_detail(viewer.current_view_data.actions.filter(func(a: Dictionary) -> bool: return a.action_id == "adventure:cave_bundle:rope")[0], [])
		await process_frame
		_check(viewer._action_detail.visible, "full cost dialog can be opened")
		_check("绳" in viewer._action_detail.dialog_text, "tool requirement and wear are readable in details")
		viewer._action_detail.get_cancel_button().pressed.emit()
		await process_frame
		_check(viewer.view_model.session.elapsed_hours_since_start == elapsed, "canceling details has no world cost")
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = size
		root.content_scale_size = size
		viewer.refresh_view()
		await process_frame
		_check(viewer.action_dock.get_global_rect().end.y <= size.y, "dock fits " + str(size))
		viewer.surface.tabs.current_tab = 1
		await process_frame
		_check(viewer._picture.texture.resource_path.ends_with("mirror_lake_cave_pixel_v1.png"), "cave uses its own original pixel illustration")
		var graph: Control = viewer._graph
		_check(graph != null, "region map exists")
		if graph != null:
			for frame: Control in graph.get_children():
				var label: Label = frame.get_child(0)
				_check(frame.get_global_rect().grow(1).encloses(label.get_global_rect()), "map label stays inside its node at " + str(size))
		await _capture("map_" + str(size.x))
		viewer.surface.tabs.current_tab = 0
	var home: String = viewer.view_model.session.fixture_source_data.journey_generated.bindings.landing_host
	_check(JourneyContract.go(viewer.view_model, home), "formal travel to household guesthouse")
	viewer.refresh_view()
	viewer.surface.tabs.current_tab = 1
	await process_frame
	_check(viewer._picture.texture.resource_path.ends_with("mirror_lake_guesthouse_pixel_v1.png"), "guesthouse has a distinct static interior illustration")
	_check("床位" in viewer._picture_caption.text, "art does not claim beds are currently available")
	await _capture("guesthouse_region")
	viewer.queue_free()
	await process_frame
	print("JOURNEY_SURFACE_RENDER_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)
