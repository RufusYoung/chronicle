extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Contract = preload("res://tests/sim/world_content_contract_test.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var hours := int(args[0]) if args.size() > 0 else 168
	if hours < 1 or hours > 168:
		push_error("Probe horizon must be 1..168 hours per invocation")
		quit(1)
		return
	var options := Contract.OPTIONS.duplicate(true)
	if args.size() > 1:
		options.challenge_seed_override = int(args[1])
	if args.size() > 3:
		options.content_extension_version = int(args[3])
	var live := Contract.Live.new()
	var started: Dictionary = live.start(options)
	if not started.get("success", false):
		push_error(str(started))
		quit(1)
		return
	var session: Variant = live.session
	if args.size() > 2 and args[2] != "new":
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[2]))
		var loaded: Dictionary = session.load_from_save_envelope(previous.get("envelope", {}))
		if not loaded.get("success", false):
			push_error(str(loaded))
			quit(1)
			return
	var start_hour: int = session.elapsed_hours_since_start
	var began := Time.get_ticks_msec()
	var days: Array = []
	for day: int in range(int(ceil(hours / 24.0))):
		var outcome: Dictionary = session.advance_time(mini(24, hours - day * 24), "passive_content_probe")
		if not outcome.get("success", false):
			push_error(str(outcome))
			quit(1)
			return
		var counts := {}
		for fact: Dictionary in session.stores.fact_store.list_facts():
			if fact.has("recipe_id"):
				counts[fact.recipe_id] = int(counts.get(fact.recipe_id, 0)) + 1
		var row := {"elapsed_hours": session.elapsed_hours_since_start, "recipes": counts}
		days.append(row)
		print("CONTENT_PROBE " + JSON.stringify(row))
	var seconds := (Time.get_ticks_msec() - began) / 1000.0
	var directory := "world_provisions" if options.content_extension_version == 2 else "world_content"
	var path := "user://tests/%s/probe_%d_%d.json" % [directory, options.challenge_seed_override, start_hour + hours]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var native_path := path.trim_suffix(".json") + ".save.json"
	var saved: Dictionary = session.save_to_path(native_path)
	if not saved.get("ok", false):
		push_error("Native probe save failed: " + str(saved))
		quit(1)
		return
	# Use the native serializer's representation, including its fact-number precision.
	var evidence := {"seed": options.challenge_seed_override, "passive_hours": hours, "start_hours": start_hour, "seconds": seconds,
		"test_injection": false, "days": days, "envelope": JSON.parse_string(FileAccess.get_file_as_string(native_path))}
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "", true, true))
	file.close()
	print("CONTENT_PROBE_SAVED " + ProjectSettings.globalize_path(path))
	quit(0)
