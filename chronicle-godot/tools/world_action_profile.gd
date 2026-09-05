extends SceneTree
## Real rendered operations, measured from dispatch through the next drawn frame.

const Demo = preload("res://scenes/rebuild/world_demo.tscn")
var output := "user://tests/world_action_profile"
var failures: Array[String] = []
var rows: Array = []
var tag := "sample"
var long_travel := false
var checkpoint := "user://tests/world_runtime_probe/day7.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this probe with the Compatibility renderer, not --headless.")
		quit(1)
		return
	if not OS.get_cmdline_user_args().is_empty():
		tag = OS.get_cmdline_user_args()[0].validate_filename()
	long_travel = "--long-travel" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--checkpoint="):
			checkpoint = argument.trim_prefix("--checkpoint=")
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for phase: String in ["initial", "day7"]:
		var viewer = Demo.instantiate()
		viewer.initial_scenario = "generated_network"
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--scenario="):
				viewer.initial_scenario = argument.trim_prefix("--scenario=")
		viewer.save_path = output + "/absent_" + Crypto.new().generate_random_bytes(8).hex_encode() + ".json"
		root.add_child(viewer)
		if phase == "day7":
			var loaded: Dictionary = viewer.view_model.load_from_path(checkpoint)
			if not loaded.get("success", false):
				failures.append("Missing day7 checkpoint: " + str(loaded))
				viewer.queue_free()
				await process_frame
				continue
			viewer.refresh_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var visits := {}
		var chosen := {}
		for index: int in 20:
			var view: Dictionary = viewer.current_view_data
			var here: String = view.location.id
			var name: String = view.location.title
			visits[name] = int(visits.get(name, 0)) + 1
			var choice := _choose(view, visits, chosen, index)
			chosen[str(choice)] = true
			var start_time: Dictionary = viewer.view_model.session.get_time_summary()
			var began := Time.get_ticks_usec()
			var dispatched: Dictionary = viewer._begin_operation(choice.method, choice.arguments)
			var frames := 0
			while viewer.busy and Time.get_ticks_usec() - began < 120000000:
				await process_frame
				frames += 1
			if viewer.busy:
				failures.append(phase + ": operation exceeded 120 seconds")
				break
			await RenderingServer.frame_post_draw
			var total_ms := (Time.get_ticks_usec() - began) / 1000.0
			var operation: Dictionary = viewer.last_operation
			if not dispatched.get("success", false) or not operation.result.get("success", false):
				failures.append(phase + ": illegal/failed operation " + str(choice))
			var end_time: Dictionary = viewer.view_model.session.get_time_summary()
			rows.append({"world": phase, "index": index, "choice": choice,
				"daily_life_version": viewer.view_model.session.world_tick_adapter.daily_life_config.get("version", 0),
				"from": here, "to": viewer.current_view_data.location.id,
				"start_time": start_time, "end_time": end_time,
				"elapsed_hours": int(end_time.elapsed_hours) - int(start_time.elapsed_hours),
				"total_ms": total_ms, "operation_ms": operation.operation_ms,
				"projection_ms": operation.projection_ms, "frames": frames,
				"state_sha256": _state(viewer.view_model).sha256_text(),
				"view_sha256": JSON.stringify(viewer.current_view_data, "", true, true).sha256_text()})
			if viewer.action_dock.get_global_rect().end.y > root.size.y + 1:
				failures.append(phase + ": action dock overflow at " + str(index))
			_flush()
			print("ACTION_PROFILE %s %d %s %.2f ms" % [phase, index, choice.method, total_ms])
		root.get_texture().get_image().save_png(output + "/" + tag + "_" + phase + ".png")
		viewer.queue_free()
		await process_frame
	_flush()
	print("ACTION_PROFILE_RESULT " + ("PASS" if failures.is_empty() else str(failures)))
	quit(0 if failures.is_empty() else 1)


func _choose(view: Dictionary, visits: Dictionary, chosen: Dictionary, index: int) -> Dictionary:
	if index % 3 == 0:
		for action: Dictionary in view.actions:
			var kind := str(action.get("event_type", "player_action"))
			if kind != "player_action" or not action.get("can_execute", true):
				continue
			var choice := {"method": "perform_action", "arguments": [action.action_id]}
			if not chosen.has(str(choice)):
				return choice
	if index % 3 == 1:
		if long_travel:
			for route: Dictionary in view.travel_options:
				if route.get("can_travel", false) and int(route.get("hours", 0)) > 1:
					return {"method": "perform_travel", "arguments": [route.route_id]}
		var best: Dictionary = {}
		var count := 2147483647
		for route: Dictionary in view.travel_options:
			if not route.get("can_travel", false):
				continue
			var visits_count := int(visits.get(str(route.get("destination_name", "")), 0))
			if visits_count < count:
				count = visits_count
				best = {"method": "perform_travel", "arguments": [route.route_id]}
		if not best.is_empty():
			return best
	return {"method": "advance_time", "arguments": [1]}


func _flush() -> void:
	var summaries := {}
	for phase: String in ["initial", "day7"]:
		var durations: Array[float] = []
		for row: Dictionary in rows:
			if row.world == phase:
				durations.append(row.total_ms)
		if not durations.is_empty():
			durations.sort()
			summaries[phase] = {"count": durations.size(),
				"p50_ms": durations[ceili(durations.size() * 0.5) - 1],
				"p95_ms": durations[ceili(durations.size() * 0.95) - 1], "max_ms": durations[-1]}
	var file := FileAccess.open(output + "/" + tag + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(), "processor": OS.get_processor_name(),
		"checkpoint": checkpoint,
		"renderer": RenderingServer.get_current_rendering_method(), "rows": rows, "summaries": summaries,
		"failures": failures, "scope": "Program-driven legal rendered UI operations; no human gameplay acceptance. Multi-hour travel reported without dividing by hours."}, "  "))
	file.close()


func _state(model: Variant) -> String:
	var envelope: Dictionary = model.session.build_save_envelope()
	return JSON.stringify({"stores": envelope.stores, "session": envelope.session,
		"world_time": envelope.world_time, "rng_states": envelope.rng_states,
		"world_log": envelope.world_log}, "", true, true)
