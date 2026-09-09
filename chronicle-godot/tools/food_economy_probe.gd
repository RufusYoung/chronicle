extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
var failures: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if not args.is_empty() else "batch12"
	var seed := int(args[1]) if args.size() > 1 else 81001
	var days := int(args[2]) if args.size() > 2 else 7
	if mode.begins_with("-") or seed <= 0 or days not in range(1, 31):
		push_error("Usage: food_economy_probe.gd -- MODE SEED DAYS (1..30)")
		quit(1)
		return
	var model := Live.new()
	var scenario := "echo_realm" if mode.begins_with("canon") else "generated_network"
	var options := {"scenario": scenario, "challenge_seed_override": seed}
	if mode.begins_with("canon_carting") or mode.begins_with("canon_depot"):
		options["food_carting_version"] = 1
	if mode.begins_with("canon_depot"):
		options["worksite_food_storage_version"] = 1
	if mode.begins_with("canon_haul"):
		options.merge({"household_food_hauling_version": 1, "worksite_food_storage_version": 1})
	if mode.begins_with("canon_budget"):
		options.merge({"household_food_hauling_version": 1, "worksite_food_storage_version": 1, "household_food_budget_version": 1})
	if mode.begins_with("canon_cooperation"):
		push_error("Retired unfunded cooperation experiment. Historical evidence is not a supported world preset.")
		quit(1)
		return
	if mode.begins_with("canon_livelihood"):
		options.merge({"household_food_hauling_version": 1, "worksite_food_storage_version": 1, "household_food_budget_version": 1, "resident_subsistence_version": 1})
	if mode.begins_with("canon_work") or mode.begins_with("canon_community"):
		options.merge({"household_food_hauling_version": 1, "worksite_food_storage_version": 1,
			"household_food_budget_version": 1, "resident_subsistence_version": 1, "work_rules_version": 1})
	if mode.begins_with("canon_community"):
		options["community_rules_version"] = 1
	if mode == "canon_livelihood_without_subsistence":
		options["resident_subsistence_version"] = 0
	if mode in ["canon_without_family", "canon_without_carting"]:
		options["food_carting_version"] = 0
	if mode == "canon_without_family":
		options["household_provisioning_version"] = 0
	_check(model.start(options).success, "start")
	if not model.is_ready():
		quit(1)
		return
	var fixture: Dictionary = model.session.fixture_source_data.duplicate(true)
	if mode.begins_with("canon_community_without_"):
		var disabled := ""
		for mechanism: String in ["messages", "policy", "social"]:
			if mode.begins_with("canon_community_without_" + mechanism + "_"):
				disabled = mechanism + "_enabled"
		if disabled == "":
			push_error("Unknown community ablation")
			quit(1)
			return
		for config: Dictionary in [fixture.community_rules, fixture.resident_daily_life.community_rules, fixture.resident_daily_life.food_access.community_rules]:
			config[disabled] = false
		fixture.known_facts.append({"fact_id": "test_injection." + mode, "fact_type": "test_injection",
			"summary": "测试注入：关闭一种交往机制，保持初始人物、钱物与地点不变。", "disabled_mechanism": disabled})
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "explicit same-source community ablation")
	if mode.begins_with("canon_work_without"):
		if mode.begins_with("canon_work_without_repair"):
			fixture.resident_daily_life.maintenance_profiles = []
		elif mode.begins_with("canon_work_without_supply"):
			fixture.resident_daily_life.activity_choice.supply_enabled = false
		elif mode.begins_with("canon_work_without_wear"):
			for profile: Dictionary in fixture.generated_livelihood_profiles:
				if profile.has("work_recipe"):
					profile.work_recipe.tools = []
		else:
			push_error("Unknown work ablation")
			quit(1)
			return
		fixture.known_facts.append({"fact_id": "test_injection." + mode, "fact_type": "test_injection",
			"summary": "测试注入：在初始配置关闭一个机制，不更改初始钱物。", "disabled_mechanism": mode})
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "explicit same-source mechanism ablation")
	if mode.begins_with("canon_livelihood"):
		fixture.resident_daily_life.food_access.hauling.fee = 4
		if mode == "canon_livelihood_without_affordability":
			fixture.resident_daily_life.food_access.subsistence.erase("household_affordability_version")
			fixture.resident_daily_life.food_access.subsistence.erase("quote_memory_hours")
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "configuration experiment: household livelihood with finite quoted fee")
	if mode.begins_with("canon_budget_fee"):
		var fee := int(mode.trim_prefix("canon_budget_fee"))
		fixture.resident_daily_life.food_access.hauling.fee = fee
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "configuration experiment: finite quoted haul fee")
	if mode == "canon_budget_without_hauling":
		fixture.resident_daily_life.food_access.hauling.fee = 4
		fixture.resident_daily_life.food_access.hauling["allow_new_contracts"] = false
		_check(model.session.start_from_fixture_data(fixture, model.session.rule_source_paths.duplicate()).success, "test injection: no new paid hauling agreements, no timer wages restored")
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
	var activity_hours := {}
	if mode == "canon_livelihood_withdraw_reopen":
		_set_terrace_access(model, false)
	for day: int in range(1, days + 1):
		if mode == "canon_livelihood_withdraw_reopen" and day == 8:
			_set_terrace_access(model, true)
		var began := Time.get_ticks_usec()
		var ok := true
		for hour: int in range(24):
			var advanced: Dictionary = model.session.advance_time(1, "food_economy_probe", {"scope_type": "global", "scope_id": "", "source": "passive_food_probe"})
			if not advanced.get("success", false):
				print("FOOD_ECONOMY_ADVANCE_FAILURE " + JSON.stringify(advanced))
				model.save_to_path(output + "/failed.json", true)
				quit(1)
				return
			for id: String in model.session.stores.state_store.states:
				var state: Dictionary = model.session.stores.state_store.states[id]
				if state.has("occupation_id"):
					if not activity_hours.has(id):
						activity_hours[id] = {}
					var activity := str(state.get("daily_activity", "legacy"))
					activity_hours[id][activity] = int(activity_hours[id].get(activity, 0)) + 1
				if state.get("hunger") == "extreme" and state.has("occupation_id") and bool(state.get("alive", true)):
					extreme_person_hours += 1
		_check(ok, "day_%d" % day)
		rows.append({"elapsed_days": day, "simulation_ms": (Time.get_ticks_usec() - began) / 1000.0})
		print("FOOD_ECONOMY_DAY %s %d" % [mode, day])
		if mode.begins_with("canon_community") and day < days and day % 7 == 0:
			_check(model.save_to_path(output + "/day%d.json" % day, true).success, "weekly diagnostic checkpoint")
	var checkpoint := output + "/day%d.json" % days
	_check(model.save_to_path(checkpoint, true).success, "native save")
	_check(model.session.validate_persistent_references().ok, "references")
	var restored := Live.new()
	var loaded := restored.load_from_path(checkpoint)
	_check(loaded.success, "native load")
	if not loaded.success:
		print("FOOD_ECONOMY_LOAD_FAILURE " + JSON.stringify(loaded))
		quit(1)
		return
	var metadata := {"scope_type": "global", "scope_id": "", "source": "passive_food_probe"}
	var continued: Dictionary = model.session.advance_time(1, "continuation", metadata)
	var restored_continued: Dictionary = restored.session.advance_time(1, "continuation", metadata)
	_check(continued.success, "continuation")
	_check(restored_continued.success, "restored continuation")
	if not continued.success or not restored_continued.success:
		print("FOOD_ECONOMY_CONTINUATION_FAILURE " + JSON.stringify({"source": continued, "restored": restored_continued}))
	_check(_signature(model) == _signature(restored), "native precision continuation equal")
	if _signature(model) != _signature(restored):
		for pair: Array in [["source", model], ["restored", restored]]:
			var diagnostic := FileAccess.open(output + "/continuation_" + str(pair[0]) + ".json", FileAccess.WRITE)
			diagnostic.store_string(_signature(pair[1]))
			diagnostic.close()
	_check(model.session.action_count == 0 and model.session.travel_count == 0, "no actor actions")
	var file := FileAccess.open(output + "/result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode": mode, "scenario": scenario, "seed": seed, "elapsed_days": days, "rows": rows,
		"work_rules": fixture.get("work_rules", {}), "activity_choice": fixture.resident_daily_life.get("activity_choice", {}),
		"food_access_config": fixture.resident_daily_life.get("food_access", {}),
		"extreme_person_hours": extreme_person_hours, "failures": failures,
		"activity_hours": activity_hours,
		"scope": _scope(mode),
		"boundary": "Not human play or sustainable economy acceptance."}, "  "))
	file.close()
	print("FOOD_ECONOMY_RESULT " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _scope(mode: String) -> String:
	if mode.begins_with("canon_work_without") or mode.begins_with("canon_community_without"):
		return "Passive counterexample with explicit initial mechanism ablation; no actor actions"
	if mode in ["canon_without_family", "canon_without_carting", "canon_budget_without_hauling", "canon_livelihood_withdraw_reopen", "canon_livelihood_without_subsistence", "canon_livelihood_without_affordability", "local_only"]:
		return "Passive counterexample with explicitly disabled rule; no actor actions"
	for prefix: String in ["canon_depot", "canon_carting", "canon_haul", "canon_budget", "canon_cooperation", "canon_livelihood", "canon_work", "canon_community", "batch"]:
		if mode.begins_with(prefix):
			return "Passive opt-in configuration experiment; no actor actions"
	return "Passive default world; no actor actions"


func _set_terrace_access(model: Variant, allowed: bool) -> void:
	# Deliberate world-counterexample injection, not an implemented political decision or player action.
	var stocks: Array = []
	for stock: Dictionary in model.session.stores.resource_stock_store.list_stocks():
		if stock.get("settlement_id") == "generated_settlement.echo_terrace" and "food" in stock.get("tags", []) \
				and stock.get("source_kind") == "natural_resource":
			stocks.append(str(stock.stock_id))
	var fact := {"fact_id": "test_injection.terrace_access." + str(allowed), "fact_type": "test_injection",
		"actor_id": "generated_settlement.echo_terrace", "stock_ids": stocks, "resident_production": allowed,
		"day": model.session.current_day, "hour": model.session.current_hour,
		"summary": "测试注入：恢复坡田采收权限。" if allowed else "测试注入：暂时撤去坡田采收权限。未增删钱粮。"}
	var transaction := Result.new()
	transaction.add_fact(fact)
	_check(model.session.writer.apply_result(transaction, model.session.stores), "test injection is explicitly recorded")
	for id: String in stocks:
		model.session.stores.resource_stock_store.stocks[id].access.resident_production = allowed
	_check(stocks.size() == 1, "one existing commons permission changed without creating resources")


func _signature(model: Variant) -> String:
	var e: Dictionary = model.session.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
