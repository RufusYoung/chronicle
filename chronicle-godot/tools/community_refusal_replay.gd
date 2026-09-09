extends "res://tests/sim/community_assistance_contract_test.gd"


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Usage: community_refusal_replay.gd -- CHECKPOINT ABSOLUTE_HOUR DONOR")
		quit(1)
		return
	var session := Session.new()
	if not session.load_from_path(args[0]).get("success", false):
		push_error("Cannot load the natural checkpoint")
		quit(1)
		return
	var target := int(args[1])
	var donor := str(args[2])
	var now := session.current_day * 24 + session.current_hour
	_check(target >= now and target - now <= 168, "bounded native replay, at most seven days")
	if not failures.is_empty():
		_finish()
		return
	while now < target:
		var advanced: Dictionary = session.advance_time(1, "community_refusal_replay", {"scope_type": "global", "scope_id": "", "source": "passive_replay"})
		if not advanced.get("success", false):
			_check(false, "natural replay advances")
			_finish()
			return
		now += 1
		if now % 24 == 0:
			print("COMMUNITY_REFUSAL_REPLAY_HOUR " + str(now))
	var refused: Dictionary = session.stores.fact_store.get_fact("fact.community_aid_withheld.%s.%d" % [donor, target])
	_check(not refused.is_empty(), "original refusal reproduces without actor action or intervention")
	if refused.is_empty():
		_finish()
		return
	var output := "user://tests/community_refusal_replay/" + str(target)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	_check(session.save_to_path(output + "/before.json").ok, "persist exact natural refusal state")
	var alternate := Session.new()
	_check(alternate.load_from_path(output + "/before.json").get("success", false), "counterfactual begins from identical native world")
	var fixture: Dictionary = session.fixture_source_data
	var config: Dictionary = fixture.community_rules
	var food_config: Dictionary = fixture.resident_daily_life.food_access
	var snapshot: Variant = _snapshot(alternate)
	var actor: Dictionary = snapshot.get_entity(donor)
	var request: Dictionary = alternate.stores.fact_store.get_fact(str(refused.source_fact_ids[0]))
	var origin: Dictionary = alternate.stores.fact_store.get_fact(str(request.root_fact_id))
	var terms: Dictionary = origin.payload.delivery_request
	var own := Budget.request(snapshot, actor, {"day": session.current_day, "hour": session.current_hour}, food_config.household_budget)
	var injection := Result.new()
	var injection_id := "test_injection.disregard_known_policy." + str(target)
	injection.add_fact({"fact_id": injection_id, "fact_type": "test_injection", "actor_id": donor,
		"day": session.current_day, "hour": session.current_hour, "source_fact_ids": [refused.fact_id],
		"summary": "测试注入：仅在本次受理中忽略已经听到的留粮约定，保留人物、身体、货物、钱、道路和请求；不是自然决定。"})
	_check(alternate.writer.apply_result(injection, alternate.stores), "counterfactual intervention explicitly recorded")
	var need := {"home_location_id": terms.home_location_id, "pantry_id": terms.pantry_id,
		"targets": terms.recipient_ids.map(func(id: String) -> Dictionary: return {"target_id": id}),
		"pantry_portions": mini(int(terms.quantity), int(config.aid_portions)),
		"retained_portions": maxi(int(config.aid_retained_portions), int(own.get("pantry_portions", 0)) + int(food_config.household_budget.personal_reserve)),
		"maximum_hours": config.aid_travel_hours, "community_request_id": request.fact_id,
		"request_root_fact_id": origin.fact_id, "requester_id": origin.subject_id,
		"community_policy_id": "", "community_withheld": false, "self_delivery": true,
		"source_fact_ids": [request.fact_id, injection_id]}
	var router := Daily.new()
	var routes: Array = router._routes(snapshot, alternate.settlement_network_runtime, alternate.context.locations,
		alternate.world_tick_adapter.daily_life_routes, fixture.resident_daily_life)
	var find_route := func(a: String, b: String) -> Dictionary: return router._next_edge(routes, a, b)
	var hauling: Dictionary = food_config.hauling.duplicate(true)
	hauling.fee = 0
	var planned := Hauling.new()._try_order(_snapshot(alternate), actor, actor, snapshot.get_entity(Storage.depot_id(donor)),
		need, {"day": session.current_day, "hour": session.current_hour}, hauling, alternate.stores, find_route)
	_check(planned.has("transaction"), "same physical state can accept dispatch when only rule adherence is bypassed")
	if not planned.has("transaction"):
		_finish()
		return
	_check(alternate.writer.apply_result(planned.transaction, alternate.stores), "alternative reserves the same real goods with no fee")
	_check(alternate.validate_persistent_references().ok, "counterfactual still obeys native custody and evidence")
	var order := Hauling.active_order(_snapshot(alternate), donor)
	var metadata := {"scope_type": "global", "scope_id": "", "source": "refusal_paired_continuation"}
	for branch: Variant in [session, alternate]:
		_check(branch.advance_time(24, "refusal_paired_continuation", metadata).get("success", false), "paired worlds continue autonomously for one day")
	var delivered := false
	for fact: Dictionary in _snapshot(alternate).get_facts_by_actor(donor):
		if fact.get("fact_type") == "food_hauling_stocked" and fact.get("exchange_id") == order.get("exchange_id"):
			delivered = true
	_check(delivered, "ignoring the rule results in actual delivery rather than a nominal promise")
	_check(session.action_count == 0 and alternate.action_count == 0, "no legal player action was mislabeled as this test intervention")
	_check(session.save_to_path(output + "/baseline.json").ok and alternate.save_to_path(output + "/disregard_policy.json").ok, "paired full native outcomes saved")
	print("COMMUNITY_REFUSAL_REPLAY_RESULT " + ("PASS" if failures.is_empty() else "FAIL") + " " + ProjectSettings.globalize_path(output))
	quit(0 if failures.is_empty() else 1)
