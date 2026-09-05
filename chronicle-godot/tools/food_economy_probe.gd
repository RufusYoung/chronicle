extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "batch12"
	var seed := int(args[1]) if args.size() > 1 else 81001
	var days := int(args[2]) if args.size() > 2 else 7
	var model := Live.new()
	var scenario := "echo_realm" if mode.begins_with("canon") else "generated_network"
	var options := {"scenario": scenario, "challenge_seed_override": seed}
	if mode == "canon_without_family":
		options["household_provisioning_version"] = 0
	_check(model.start(options).success, "start")
	if not model.is_ready():
		quit(1)
		return
	var fixture: Dictionary = model.session.fixture_source_data.duplicate(true)
	if mode == "local_only":
		fixture.resident_daily_life.food_access.adjacent_supply_known = false
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "test injection: local information only")
	if mode.begins_with("batch"):
		var quantity := int(mode.trim_prefix("batch"))
		for profile: Dictionary in fixture.generated_livelihood_profiles:
			if profile.occupation_id in ["net_fisher", "terrace_farmer"]:
				profile.work_interval_hours = 4
				profile.products[0].quantity = quantity
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "configuration experiment")
	var output := "user://tests/food_economy_probe/%s_%d" % [mode.validate_filename(), seed]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var rows: Array = []
	var extreme_person_hours := 0
	for day: int in range(1, days + 1):
		var began := Time.get_ticks_usec()
		var ok := true
		for hour: int in range(24):
			ok = model.session.advance_time(1, "food_economy_probe", {"scope_type": "global", "scope_id": "", "source": "passive_food_probe"}).success and ok
			for state: Dictionary in model.session.stores.state_store.states.values():
				if state.get("hunger") == "extreme" and state.has("occupation_id") and bool(state.get("alive", true)):
					extreme_person_hours += 1
		_check(ok, "day_%d" % day)
		rows.append({"elapsed_days": day, "simulation_ms": (Time.get_ticks_usec() - began) / 1000.0})
		print("FOOD_ECONOMY_DAY %s %d" % [mode, day])
	var checkpoint := output + "/day%d.json" % days
	_check(model.save_to_path(checkpoint, true).success, "native save")
	_check(model.session.validate_persistent_references().ok, "references")
	var restored := Live.new()
	_check(restored.load_from_path(checkpoint).success, "native load")
	var metadata := {"scope_type": "global", "scope_id": "", "source": "passive_food_probe"}
	_check(model.session.advance_time(1, "continuation", metadata).success, "continuation")
	_check(restored.session.advance_time(1, "continuation", metadata).success, "restored continuation")
	_check(_signature(model) == _signature(restored), "native precision continuation equal")
	_check(model.session.action_count == 0 and model.session.travel_count == 0, "no actor actions")
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode": mode, "scenario": scenario, "seed": seed, "elapsed_days": days, "rows": rows,
		"extreme_person_hours": extreme_person_hours, "failures": failures,
		"scope": "Configuration experiment" if mode.begins_with("batch") else ("Test injection: household provisioning disabled" if mode == "canon_without_family" else ("Test injection: only local supply knowledge" if mode == "local_only" else "Passive formal new world")),
		"boundary": "Not human play or sustainable economy acceptance."}, "  "))
	file.close()
	print("FOOD_ECONOMY_RESULT " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _signature(model: Variant) -> String:
	var e: Dictionary = model.session.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
