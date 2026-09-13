extends "res://tests/sim/work_recipe_contract_test.gd"

const Life = preload("res://scripts/sim/player/player_life.gd")
const Local = preload("res://scripts/sim/player/player_local_life.gd")
const Tx = preload("res://scripts/sim/transaction/transaction_result.gd")


func _run() -> void:
	var live := Live.new()
	var started: Dictionary = live.start({"scenario": "echo_realm", "challenge_seed_override": 81001,
		"work_rules_version": 1, "world_danger_version": 1, "player_life_version": 2,
		"household_food_hauling_version": 1, "household_food_budget_version": 1,
		"resident_subsistence_version": 1, "worksite_food_storage_version": 1})
	_check(started.get("success", false), "v2 bootstrap starts: " + str(started.get("error", "")))
	if not live.is_ready():
		_finish()
		return
	var base: Dictionary = live.session.fixture_source_data
	var first_view: Dictionary = live.build_view_data()
	_check(first_view.travel_options.any(func(row: Dictionary) -> bool: return "采口粮" in row.get("purpose", "")), "public routes explain actual site uses")
	_check(first_view.local_information.is_empty(), "new player has not heard private quotes")
	var session: Variant = _session(base)
	var target := _setup_local(session)
	var ask := "ask_local:" + target
	_check(Life.execute(session, ask).success, "present speaker gives a first-hand local account")
	var info := Local.known_information(session)
	_check(info.size() == 1 and info[0].statement.has("workplaces") and info[0].age_hours == 1, "specific information and observed age are retained")
	_check(not Life.options(session).any(func(row: Dictionary) -> bool: return row.action_id == ask), "unchanged local question disappears")
	_check(session.save_to_path("user://tests/player_local_life/known.json").ok, "local information saves natively")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/player_local_life/known.json").success, "v2 native restores")
	_check(Local.same_information(Local.known_information(session), Local.known_information(restored)), "restored knowledge has same content and time")
	_check(not Life.options(restored).any(func(row: Dictionary) -> bool: return row.action_id == ask), "native numeric restoration does not refresh an unchanged question")
	session.advance_time(12, "legal_wait_for_stale_information")
	_check(Local.known_information(session)[0].expired, "old quotes explicitly expire instead of live remote refresh")
	_sale_case(base)
	_gift_case(base)
	_denial_cases(base)
	_block_case(base)
	_danger_attribution_case(base)
	_legacy_case(base)
	_finish()


func _setup_local(session: Variant) -> String:
	var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var target := ""
	for person: Dictionary in view.get_entities_by_type("person"):
		if "generated_resident" in person.get("tags", []) and int(person.states.get("age_years", 0)) >= 18 \
				and Life.Treasury.new(view).balance(str(person.id)) >= 6:
			target = str(person.id)
			break
	_check(target != "", "controlled case selects an existing funded adult")
	var result := Tx.new()
	result.add_fact({"fact_id": "test_injection.local_life", "fact_type": "test_injection",
		"summary": "测试注入：在场成人缺粮、疲劳而休息，玩家持有测试食物；钱仍来自世界原有资金。"})
	for pair: Array in [["location_id", session.context.location_id], ["home_location_id", session.context.location_id],
		["daily_route_id", ""], ["daily_destination_id", ""], ["daily_travel_remaining", 0], ["daily_activity", "resting"],
		["hunger", "high"], ["hunger_elapsed_hours", 0], ["fatigue", 9]]:
		Life.set_state(result, target, str(pair[0]), pair[1])
	for item: Dictionary in view.get_items_for_holder(target):
		if Life.Food.is_food(item):
			result.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
				"new_holder": {"kind": "entity", "id": "player"}, "source_fact_ids": ["test_injection.local_life"]})
	result.add_item_change({"operation": "create", "item": {"item_instance_id": "test.player.surplus", "item_def_id": "item.fresh_fish_portion",
		"holder": {"kind": "entity", "id": "player"}, "quantity": 8}, "source_fact_ids": ["test_injection.local_life"]})
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "explicit counterexample setup commits through writer")
	return target


func _sale_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var target := _setup_local(session)
	var before: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var coins := Life.Treasury.new(before).balance("player")
	var buyer_coins := Life.Treasury.new(before).balance(target)
	var sales: Array = Life.options(session).filter(func(row: Dictionary) -> bool: return row.action_id.begins_with("sell_food:" + target) and row.can_execute)
	_check(not sales.is_empty(), "hungry present adult offers a funded purchase")
	if sales.is_empty():
		return
	var sale: Dictionary = sales[0]
	var price: int = sale.quantity * sale.offer.unit_price
	_check(Life.execute(session, sale.action_id).success, "player consents to real local sale")
	var after: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	_check(Life.Treasury.new(after).balance("player") == coins + price, "player receives actual price")
	_check(Life.Treasury.new(after).balance(target) == buyer_coins - price, "buyer really pays, no unlimited merchant money")
	_check(after.player.food_count == before.player.food_count - sale.quantity, "goods leave player inventory")
	var sold: Array = after.get_facts_by_type("player_food_sold")
	_check(sold.size() == 1 and sold[0].contributor_id == "player", "sale provenance names voluntary provider")
	_check(not Life.observed_followups(session).is_empty(), "recipient's actual later meal is visibly linked")
	_check(not Life.options(session).any(func(row: Dictionary) -> bool: return row.action_id == sale.action_id), "satisfied buyer stops asking for the same sale")
	_check(session.save_to_path("user://tests/player_local_life/sale.json").ok, "sale native checkpoint")
	var loaded := Session.new()
	_check(loaded.load_from_path("user://tests/player_local_life/sale.json").success, "sale restores using original item/exchange stores")
	session.advance_time(3, "legal_continue")
	loaded.advance_time(3, "legal_continue")
	_check(_signature(session) == _signature(loaded), "trade, later meals and world continue identically")
	session.save_to_path("user://tests/player_local_life/sale_a.json")
	loaded.save_to_path("user://tests/player_local_life/sale_b.json")


func _gift_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var target := _setup_local(session)
	var before: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var gift: Dictionary = Life.options(session).filter(func(row: Dictionary) -> bool: return row.action_id.begins_with("give_food:" + target))[0]
	_check(Life.execute(session, gift.action_id).success, "voluntary one-portion gift commits")
	var after: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	_check(after.player.food_count == before.player.food_count - 1, "gift costs real owned food")
	_check(Life.Treasury.new(after).balance("player") == Life.Treasury.new(before).balance("player"), "gift grants no invented money")
	_check(not Life.observed_followups(session).is_empty(), "gift reaches an actual meal, not just an acknowledgment")


func _denial_cases(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var target := _setup_local(session)
	var offered: Array = Life.options(session).filter(func(row: Dictionary) -> bool: return row.action_id.begins_with("sell_food:" + target) and row.can_execute)
	var id: String = offered[0].action_id
	var result := Tx.new()
	Life.set_state(result, target, "daily_route_id", "test.in_transit")
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "test injection marks seller counterpart in transit")
	var before := _signature(session)
	_check(not Life.execute(session, id).success, "stale offer cannot sell to someone who left")
	_check(_signature(session) == before, "rejected stale action changes neither goods nor time")
	result = Tx.new()
	Life.set_state(result, target, "daily_route_id", "")
	for item: Dictionary in session.stores.item_store.list_items_for_owner(target):
		if item.item_def_id == Life.Food.CURRENCY:
			result.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
				"new_holder": {"kind": "entity", "id": "player"}, "source_fact_ids": ["test_injection.local_life"]})
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "test injection removes buyer funds by transfer")
	_check(not Life.options(session).any(func(row: Dictionary) -> bool: return row.action_id.begins_with("sell_food:" + target) and row.can_execute), "poor buyer cannot create cash")
	_check(Life.options(session).any(func(row: Dictionary) -> bool: return row.action_id.begins_with("give_food:" + target) and row.can_execute), "giving remains a distinct voluntary alternative")
	_check(not Life.execute(session, id).success, "old funded quote cannot bypass current affordability")


func _block_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	session.advance_time(18 - session.current_hour, "legal_until_evening")
	Life.execute(session, "eat")
	_check(session.save_to_path("user://tests/player_local_life/before_rest.json").ok, "rest comparison same native checkpoint")
	var individual := Session.new()
	_check(individual.load_from_path("user://tests/player_local_life/before_rest.json").success, "individual-hour comparison loads")
	var result := Life.execute(session, "rest_block")
	_check(result.success and result.hours > 1 and result.hours <= 6, "bounded rest replaces repeated clicks")
	for index: int in range(int(result.hours)):
		Life.execute(individual, "rest")
	_check(_signature(session) == _signature(individual), "batch rest executes every same hourly world/body change")
	session.save_to_path("user://tests/player_local_life/rest_a.json")
	individual.save_to_path("user://tests/player_local_life/rest_b.json")
	for route: Dictionary in session.get_travel_options():
		if int(route.hours) > 2 and route.can_travel:
			_check(session.travel(str(route.route_id)).success, "long journey starts physically")
			var journey := Life.execute(session, "journey_block")
			_check(journey.success and session.context.location_id == route.to_location_id, "bounded journey reaches real destination")
			_check(session.get_snapshot().player.daily_travel_remaining == 0, "no outstanding trip after continuous travel")
			break


func _legacy_case(base: Dictionary) -> void:
	var fixture := base.duplicate(true)
	fixture.player_life = Life.PROFILE.duplicate(true)
	fixture.resident_daily_life.player_life = Life.PROFILE.duplicate(true)
	fixture.player_life_generated.version = 1
	var session: Variant = _session(fixture)
	_setup_local(session)
	_check(not Life.options(session).any(func(row: Dictionary) -> bool: return Local.handles(row.action_id)), "v1 never silently acquires v2 sale or knowledge rules")
	fixture.player_life_generated.version = 2
	var invalid := Session.new()
	_check(not invalid.start_from_fixture_data(fixture, []).success, "mismatched compiled behavior version is rejected")


func _danger_attribution_case(base: Dictionary) -> void:
	var session: Variant = _session(base)
	var target := _setup_local(session)
	var view: Variant = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var threat: Dictionary = view.get_entities_by_type("creature").filter(func(row: Dictionary) -> bool: return "world_threat" in row.get("tags", []))[0]
	var now := Life.Danger.hour(session.get_time_summary())
	var result := Tx.new()
	Life.set_state(result, target, "location_id", threat.states.location_id)
	Life.set_state(result, str(threat.id), "health", 3)
	Life.set_state(result, str(threat.id), "danger_retreat_until", now + 12)
	for row: Dictionary in [
		{"fact_id": "test.contact", "fact_type": "world_danger_contact", "actor_id": target, "hour": session.current_hour - 2},
		{"fact_id": "test.player_damage", "fact_type": "world_danger_round", "actor_id": "player", "hour": session.current_hour - 1,
			"enemy_health_before": 20, "enemy_health_after": 12, "threat_dispersed": false},
		{"fact_id": "test.npc_clearance", "fact_type": "world_danger_round", "actor_id": target, "hour": session.current_hour,
			"enemy_health_before": 12, "enemy_health_after": 3, "threat_dispersed": true}]:
		row.merge({"target_id": threat.id, "location_id": threat.states.location_id, "day": session.current_day,
			"source_fact_ids": ["test_injection.local_life"], "summary": "测试注入：构造协同击退的归因反例，不代表合法游玩。"})
		result.add_fact(row)
	result.mark_resolved("test_injection")
	_check(session.writer.apply_result(result, session.stores), "controlled danger provenance fixture commits")
	view = Life.snapshot(session.context, session.stores, session.get_time_summary())
	var config: Dictionary = session.fixture_source_data.world_danger
	var tick: Dictionary = session.get_time_summary()
	var clearance := Life.Danger.work_clearance(view, target, str(threat.states.location_id), tick, config)
	_check(clearance.get("source_fact_ids", []).has("test.player_damage") and clearance.get("fact_id") == "test.npc_clearance", "NPC finishing blow retains actual player contribution without sole-credit fiction")
	_check(Life.available_reports(session, view).is_empty(), "offsite production knowledge does not teleport to player")
	var late := {"day": session.current_day + 2, "hour": session.current_hour}
	_check(Life.Danger.work_clearance(view, target, str(threat.states.location_id), late, config).is_empty(), "expired retreat cannot explain unrelated later work")
	_check(Life.Danger.work_clearance(view, target, str(session.context.location_id), tick, config).is_empty(), "work attribution requires actual presence at the affected site")
	view.facts = view.facts.map(func(fact: Dictionary) -> Dictionary:
		if fact.get("fact_id") != "test.player_damage":
			return fact
		var guarded := fact.duplicate(true)
		guarded.enemy_health_after = guarded.enemy_health_before
		return guarded)
	_check(Life.Danger.work_clearance(view, target, str(threat.states.location_id), tick, config).is_empty(), "merely being in combat without damage is not credited for clearing the threat")
