extends "res://tests/sim/world_content_contract_test.gd"

const Meal = preload("res://scripts/sim/economy/meal_satiation.gd")
const Access = preload("res://scripts/sim/resource/resource_access.gd")
const Needs = preload("res://scripts/sim/npc/npc_need_system.gd")


func _run() -> void:
	var options := OPTIONS.duplicate(true)
	options.content_extension_version = 2
	var live := Live.new()
	var started: Dictionary = live.start(options)
	_check(started.get("success", false), "content v2 starts: " + str(started.get("error", "")))
	if not live.is_ready():
		_finish()
		return
	var base: Dictionary = live.session.fixture_source_data.duplicate(true)
	_meal_cases(base)
	_meal_clock_case(base)
	_visitor_case(base)
	for recipe: String in ["recipe.smoke_lake_fish", "recipe.roast_roots"]:
		_processing_case(base, recipe)
	_check(live.session.advance_time(48, "natural_provisions").success, "new provision rules run autonomously for two days")
	_check(live.session.save_to_path("user://tests/world_provisions/natural.json").ok, "natural world saved")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_provisions/natural.json").success, "natural world restored")
	_check(live.session.advance_time(3, "continuation").success and restored.advance_time(3, "continuation").success, "native branches continue")
	_check(_signature(live.session) == _signature(restored), "full provision world has identical native continuation")
	var old := Live.new()
	_check(old.start(OPTIONS).success and not old.session.fixture_source_data.content_extension.has("meal_rules"), "old content world does not acquire nutrition or visitor rules")
	_check(old.session.fixture_source_data.initial_resource_stocks.all(func(s: Dictionary) -> bool: return s.get("access", {}).get("version", 1) == 1), "old commons remain resident only")
	_finish()


func _meal_cases(base: Dictionary) -> void:
	var raw: Variant = _session(base)
	var cooked: Variant = _session(base)
	for session: Variant in [raw, cooked]:
		var result := Tx.new()
		result.add_fact({"fact_id": "test.meal", "fact_type": "test_injection", "summary": "测试注入：同一身体和一份食物，仅比较是否加工。"})
		var definition := "item.fresh_fish_portion" if session == raw else "item.smoked_lake_fish"
		result.add_item_change({"operation": "create", "item": {"item_instance_id": "test.meal.food", "item_def_id": definition,
			"holder": {"kind": "entity", "id": "player"}, "quantity": 2}, "source_fact_ids": ["test.meal"]})
		Life.set_state(result, "player", "hunger", "high")
		Life.set_state(result, "player", "hunger_elapsed_hours", 0)
		result.mark_resolved("test_injection")
		_check(session.writer.apply_result(result, session.stores), "controlled meal input applied")
		var food: Dictionary = session.stores.item_store.get_item("test.meal.food")
		var rows: Array = Life.options(session, false).filter(func(r: Dictionary) -> bool: return r.get("meal_item_id") == "test.meal.food")
		_check(rows.size() == 1, "public choice names the food actually consumed")
		if rows.is_empty():
			return
		_check(rows[0].satiation_hours == (0 if session == raw else 6), "meal choice exposes actual satiety, not a generic benefit")
		_check(Life.execute(session, rows[0].action_id).success, "formal meal consumes food")
		_check(session.stores.item_store.get_item("test.meal.food").quantity == 1, "exactly one real portion consumed")
		_check(session.advance_time(5, "meal_counterfactual").success, "same six hours elapse after the meal")
	_check(raw.stores.state_store.get_state("player", "hunger", "") == "medium", "raw meal hunger resumes normally")
	_check(cooked.stores.state_store.get_state("player", "hunger", "") == "low", "cooked meal delays actual hunger through the journey interval")
	_check(cooked.save_to_path("user://tests/world_provisions/meal.json").ok, "meal timer saves")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_provisions/meal.json").success, "meal timer restores")
	_check(cooked.advance_time(6, "satiety_expiry").success and restored.advance_time(6, "satiety_expiry").success, "time resumes beyond satiety expiry")
	_check(cooked.stores.state_store.get_state("player", "hunger", "") == "medium" and _signature(cooked) == _signature(restored), "meal does not stop future hunger and native continuation matches")
	var rule: Dictionary = base.content_extension.meal_rules
	var third := rule.duplicate(true)
	third.foods["item.heldout_meal"] = {"satiation_hours": 3}
	_check(Meal.validate(third, base.content_extension.item_defs + [{"item_def_id": "item.heldout_meal", "tags": ["food"], "capabilities": ["consume"]}]) == "", "a third food benefit is data-only")
	for value: Variant in [-1, 0, 1.5, 13, INF, "6"]:
		var invalid := rule.duplicate(true)
		invalid.foods["item.smoked_lake_fish"].satiation_hours = value
		_check(Meal.validate(invalid, base.content_extension.item_defs) != "", "invalid meal duration rejected: " + str(value))
	var v1: Dictionary = base.content_extension.duplicate(true)
	v1.version = 1
	_check(Content.validate(v1) == "new_life_rules_require_content_v2", "new meal semantics cannot be mislabeled v1")
	for invalid: Variant in ["bad", null, ["bad"]]:
		var malformed: Dictionary = base.content_extension.duplicate(true)
		malformed.item_defs = invalid
		_check(Content.validate(malformed) != "", "invalid item collections reject before typed meal lookup")


func _visitor_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var home: String = session.get_snapshot().player.settlement_id
	_check(session.advance_time(12, "travel_after_threat").success, "wait through daytime threat without teleportation")
	for fragment: String in [".network.", "commons_to_terrace_farming"]:
		var routes: Array = session.get_travel_options().filter(func(r: Dictionary) -> bool: return fragment in str(r.route_id))
		_check(not routes.is_empty() and session.travel(routes[0].route_id).success, "travel legally: " + fragment)
		while session.get_snapshot().player.get("daily_route_id", "") != "":
			_check(Life.execute(session, "continue").success, "physical visitor journey")
	while session.current_hour != 7:
		_check(session.advance_time(1, "wait_for_work").success, "wait until morning")
	var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var actor: Dictionary = view.get_entity("player")
	var profile: Dictionary = Life.gather_profiles(session, view, actor)[0]
	var stock_id := str(profile.resource_inputs[0].stock_id)
	print("VISITOR_PROFILE " + JSON.stringify(profile.resource_inputs))
	var initial: Dictionary = view.get_resource_stock(stock_id)
	_check(initial.access.version == 2 and Access.visitor_remaining(initial, "player", session.current_day) == 1, "published local visitor allowance exists")
	var rows: Array = Life.options(session, false).filter(func(r: Dictionary) -> bool: return r.action_id == "gather:terrace_farmer")
	_check(rows.size() == 1 and rows[0].can_execute and "访客公地额度" in rows[0].hint, "visitor sees a lawful, costed alternative")
	var output := str(profile.products[0].item_def_id)
	var before := _quantity(session, "player", output)
	var rounds := 0
	for attempt: int in range(36):
		var combat: Array = session.get_combat_encounter_options()
		if not combat.is_empty():
			var approach := "guard" if rounds % 3 < 2 else "attack"
			var choice: Dictionary = combat.filter(func(c: Dictionary) -> bool: return c.approach_id == approach)[0]
			_check(session.execute_combat_encounter_option(choice.option_id).success, "visitor responds to the actual interruption: " + approach)
			rounds += 1
			continue
		var choices: Array = Life.options(session, false).filter(func(r: Dictionary) -> bool: return r.action_id == "gather:terrace_farmer" and r.can_execute)
		if choices.is_empty():
			_check(Life.execute(session, "rest").success, "recover before resuming interrupted harvest")
		else:
			_check(Life.execute(session, "gather:terrace_farmer").success, "formal visitor gathering advances actual labor")
		if _quantity(session, "player", output) > before:
			break
	_check(session.get_snapshot().player.settlement_id == home, "visitor is not silently naturalized")
	var stock: Dictionary = session.stores.resource_stock_store.get_stock(stock_id)
	_check(is_equal_approx(Access.visitor_remaining(stock, "player", session.current_day), 1.0 - float(profile.resource_inputs[0].amount_per_cycle)), "actual harvest spends finite daily rights")
	_check(_quantity(session, "player", output) > before, "real harvested food reaches visitor inventory")
	rows = Life.options(session, false).filter(func(r: Dictionary) -> bool: return r.action_id == "gather:terrace_farmer")
	if rows.is_empty():
		_check(false, "visitor returns to decision view after encounter")
		return
	_check(not rows[0].can_execute and "额度不足" in rows[0].blocked_reason, "exhausted daily allowance blocks repetition with an alternative")
	_check(not Life.execute(session, "gather:terrace_farmer").success, "stale option cannot bypass quota")
	_check(session.save_to_path("user://tests/world_provisions/visitor.json").ok, "spent visitor rights save")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/world_provisions/visitor.json").success, "spent visitor rights restore")
	_check(not Life.execute(restored, "gather:terrace_farmer").success, "reloading does not reset quota")
	_check(Access.visitor_remaining(stock, "player", session.current_day + 1) == 1, "quota resets by day, not menu refresh")
	view = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var remote := actor.duplicate(true)
	remote.states.location_id = "elsewhere"
	_check(Access._permission_error(initial, "player", remote, home, "alive", "livelihood_production", 1, session.current_day) == "visitor_not_at_worksite", "visitor cannot remotely use another town's commons")
	var npc := actor.duplicate(true)
	npc.id = "test.other_visitor"
	npc.tags = ["generated_resident"]
	_check(Access._permission_error(initial, str(npc.id), npc, home, "alive", "livelihood_production", 0.75, session.current_day) == "", "the same visitor policy accepts a resident actor from another town")
	var forged := {"stock_id": stock_id, "actor_id": "player", "operation": "consume", "reason": "livelihood_production", "amount": 1, "day": session.current_day + 1,
		"source_fact_ids": [str(initial.access.source_fact_id)]}
	_check(Access.validate_change(forged, session.stores) == "visitor_usage_must_be_recorded", "writer refuses an unmetered visitor debit")
	forged.visitor_use = true
	_check(Access.validate_change(forged, session.stores) == "visitor_production_fact_mismatch", "writer refuses invented production provenance")
	var before_signature := _signature(session)
	var duplicate := Tx.new()
	duplicate.add_fact({"fact_id": "test.visitor.double", "fact_type": "npc_livelihood_produced", "actor_id": "player", "day": session.current_day + 1,
		"location_id": session.context.location_id, "summary": "测试注入：同一事务请求重复扣取，用来验证预检回滚。"})
	forged.source_fact_ids = ["test.visitor.double"]
	forged.amount = 0.75
	duplicate.add_resource_change(forged.duplicate(true))
	duplicate.add_resource_change(forged.duplicate(true))
	duplicate.mark_resolved("test_injection")
	_check(not session.writer.apply_result(duplicate, session.stores), "combined debits cannot exceed one visitor allowance")
	_check(_signature(session) == before_signature, "failed visitor debit rolls back both resources and facts")


func _meal_clock_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var tx := Tx.new()
	var now := Meal.now(session.get_time_summary())
	Life.set_state(tx, "player", "hunger", "low")
	Life.set_state(tx, "player", "hunger_elapsed_hours", 2)
	Life.set_state(tx, "player", "hunger_sated_until", now + 2)
	tx.mark_resolved("test_injection")
	_check(session.writer.apply_result(tx, session.stores), "controlled timer overlap setup")
	var tick: Dictionary = session.get_time_summary()
	tick.hour += 4
	tick.elapsed_hours = 4
	tick.tick_event_id = "test.satiation_overlap"
	var view: Variant = Life.snapshot(session.context, session.stores, tick)
	var result: Dictionary = Needs.new().resolve_tick(view, session.npc_need_profiles, tick, [view.get_entity("player")])
	_check(session.writer.apply_results(result.results, session.stores), "partial multi-hour satiation overlap resolves")
	_check(session.stores.state_store.get_state("player", "hunger_elapsed_hours", 0) == 4, "only two unprotected hours advance the existing need clock")
	var first := Tx.new()
	Meal.append(first, "player", {"item_def_id": "item.smoked_lake_fish"}, base.content_extension.meal_rules, tick)
	_check(session.writer.apply_result(first, session.stores), "first processed meal timer applies")
	var second := Tx.new()
	Meal.append(second, "player", {"item_def_id": "item.smoked_lake_fish"}, base.content_extension.meal_rules, tick)
	_check(session.writer.apply_result(second, session.stores), "second same-hour meal applies")
	_check(session.stores.state_store.get_state("player", "hunger_sated_until", 0) == Meal.now(tick) + 6, "repeated eating does not stack future hunger immunity")


func _finish() -> void:
	print("WORLD_PROVISIONS_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
