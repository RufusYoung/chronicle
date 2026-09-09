extends "res://tests/sim/community_life_contract_test.gd"

const Assistance = preload("res://scripts/sim/npc/community_assistance.gd")
const Budget = preload("res://scripts/sim/economy/household_food_budget.gd")
const Hauling = preload("res://scripts/sim/economy/household_food_hauling.gd")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001, "work_rules_version": 1,
		"community_rules_version": 1, "household_food_hauling_version": 1, "household_food_budget_version": 1,
		"resident_subsistence_version": 1, "worksite_food_storage_version": 1}).success, "start shared-world assistance fixture")
	if not live.is_ready():
		_finish()
		return
	for reserve: bool in [false, true]:
		_aid_case(live.session.fixture_source_data, reserve)
	_aid_case(live.session.fixture_source_data, false, true)
	_finish()


func _aid_case(base: Dictionary, reserve: bool, self_delivery: bool = false) -> void:
	var fixture := base.duplicate(true)
	fixture.world_time = {"day": 3, "hour": 12}
	var donor := "generated_resident.echo_landing.001"
	var receiver := "generated_resident.echo_terrace.001"
	var carrier := "generated_resident.echo_landing.004"
	if self_delivery:
		carrier = donor
	var site := str(_entity(fixture, donor).states.workplace_id)
	_entity(fixture, donor).states.merge({"location_id": site, "daily_activity": "socializing", "daily_route_id": "", "hunger": "high" if reserve else "low"}, true)
	_entity(fixture, receiver).states.hunger = "high"
	if not self_delivery:
		_entity(fixture, carrier).states.daily_activity = "working"
	fixture.initial_items.append({"item_instance_id": "test.aid.food", "item_def_id": "item.fresh_fish_portion", "quantity": 20, "holder": {"kind": "entity", "id": Storage.depot_id(donor)}})
	fixture.known_facts.append({"fact_id": "test_injection.aid", "fact_type": "test_injection", "summary": "测试注入：控制到場、钱粮与饥饿，测试请求、拒绝和实物交付；不是自然世界证据。"})
	var session: Variant = _session(fixture)
	if not session.initialized:
		return
	var tick := {"day": 3, "hour": 12}
	var budget_config: Dictionary = fixture.resident_daily_life.food_access.household_budget
	var config: Dictionary = fixture.community_rules
	var observed := Budget.new().observe(_snapshot(session), tick, budget_config)
	_check(session.writer.apply_results(observed.results, session.stores), "requester actually observes household pantry")
	observed = CommunityLife.new().observe(_snapshot(session), tick, config, budget_config)
	_check(session.writer.apply_results(observed.results, session.stores), "request originates from firsthand pantry and hunger")
	_check(Assistance.requests(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget_config).is_empty(), "unheard remote request cannot spend donor goods")
	_place(session, receiver, site, "home")
	var conversations := CommunityLife.new().converse(_snapshot(session), tick, config)
	_check(session.writer.apply_results(conversations.results, session.stores), "request conveyed in a real colocated conversation")
	_check(Assistance.requests(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget_config).size() == 1, "unknown rule does not forbid voluntary use of one's own surplus")
	var policies := Community.new().resolve_tick(_snapshot(session), tick, config)
	_check(session.writer.apply_results(policies.results, session.stores), "donor representative adopts rule from known needs")
	var requests := Assistance.requests(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget_config)
	_check(requests.size() == 1, "explicit household address opens one bounded assistance request")
	if requests.is_empty():
		return
	if self_delivery:
		_check(not Assistance.proposals(_snapshot(session), _snapshot(session).get_entity(donor), tick, config, budget_config).is_empty(), "heard need creates an actor choice using personally observed surplus")
		requests[0]["self_delivery"] = true
	_place(session, carrier, site, "seeking_work")
	var snapshot: Variant = _snapshot(session)
	var hauler := Hauling.new()
	var hauling: Dictionary = fixture.resident_daily_life.food_access.hauling
	if self_delivery:
		hauling = hauling.duplicate(true)
		hauling.fee = 0
	var router := Daily.new()
	var routes: Array = router._routes(snapshot, session.settlement_network_runtime, session.context.locations, session.world_tick_adapter.daily_life_routes, fixture.resident_daily_life)
	var route_finder := func(a: String, b: String) -> Dictionary: return router._next_edge(routes, a, b)
	var payer: Dictionary = snapshot.get_entity(donor)
	var worker: Dictionary = snapshot.get_entity(carrier)
	var depot: Dictionary = snapshot.get_entity(Storage.depot_id(donor))
	var no_route := func(_a: String, _b: String) -> Dictionary: return {}
	_check(hauler._try_order(snapshot, worker, payer, depot, requests[0], tick, hauling, session.stores, no_route).is_empty(), "closed route cannot receive a delivery promise")
	var expensive := hauling.duplicate(true)
	expensive.fee = 100000
	_check(hauler._try_order(snapshot, worker, payer, depot, requests[0], tick, expensive, session.stores, route_finder).is_empty(), "real donor money limits accepted assistance")
	var planned := hauler._try_order(snapshot, worker, payer, depot, requests[0], tick, hauling, session.stores, route_finder)
	if self_delivery:
		var intent := Result.new()
		intent.add_state_change({"entity_id": donor, "key": "daily_intent_id", "to": "community_delivery:" + str(requests[0].request_root_fact_id)})
		_check(session.writer.apply_result(intent, session.stores), "test injection: select the self-delivery candidate")
		planned = hauler.plan_contact(_snapshot(session), _snapshot(session).get_entity(donor), tick,
			fixture.resident_daily_life.food_access.hauling, {}, session.stores, route_finder, budget_config, config)
	_check(planned.has("transaction"), "eligible contact yields a formal decision")
	if not planned.has("transaction"):
		return
	var money_before := Food.balance(session.stores.item_store.list_items_for_owner(donor), donor)
	_check(session.writer.apply_result(planned.transaction, session.stores), "assistance decision commits atomically")
	if reserve:
		_check(planned.events[0].fact_type == "community_aid_withheld" and Hauling.active_order(_snapshot(session), carrier).is_empty(), "heard reserve rule prevents dispatch despite affordable surplus")
		_check(Food.balance(session.stores.item_store.list_items_for_owner(donor), donor) == money_before, "withholding spends no cash")
		return
	var order := Hauling.active_order(_snapshot(session), carrier)
	_check(not order.is_empty() and order.has("community_request_id"), "reuse physical food-hauling exchange rather than a new inventory")
	_check(Food.balance(session.stores.item_store.list_items_for_owner(donor), donor) == money_before - int(hauling.fee), "donor's actual fee is escrowed")
	_check(Hauling.validate_order(order, session.stores, session.context.locations) == "", "native order validates receiver consent and message source")
	var invalid := order.duplicate(true)
	invalid.requester_id = donor
	_check(Hauling.validate_order(invalid, session.stores, session.context.locations) != "", "forged receiver is rejected")
	invalid = order.duplicate(true)
	if self_delivery:
		invalid.fee = 1
		_check(Hauling.validate_order(invalid, session.stores, session.context.locations) != "", "self delivery cannot invent paid income")
		invalid = order.duplicate(true)
		invalid.party_b = "generated_resident.echo_landing.004"
		_check(Hauling.validate_order(invalid, session.stores, session.context.locations) != "", "self delivery cannot silently assign another worker")
		invalid = order.duplicate(true)
		invalid.erase("self_delivery")
		_check(Hauling.validate_order(invalid, session.stores, session.context.locations) != "", "zero fee same-party order requires explicit self delivery")
	else:
		invalid.fee = 0
		_check(Hauling.validate_order(invalid, session.stores, session.context.locations) != "", "ordinary paid hauling still requires a real fee")
	_check(session.save_to_path("user://tests/community_life/aid.json").ok, "native save while goods and cash are in transit")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/community_life/aid.json").get("success", false), "native load preserves active assistance contract")
	var continuation := Session.new()
	_check(continuation.load_from_path("user://tests/community_life/aid.json").get("success", false), "second native branch loads")
	var metadata := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
	_check(restored.advance_time(1, "community_aid_test", metadata).success and continuation.advance_time(1, "community_aid_test", metadata).success, "aid continues through the world clock")
	_check(_signature(restored) == _signature(continuation), "full native aid continuation agrees")
	if self_delivery:
		_check(restored.stores.state_store.get_state(donor, "daily_goal_id", "") == order.destination_location_id, "non-carter donor autonomously follows the accepted delivery")
	var before := Food.balance(session.stores.item_store.list_items_for_owner(carrier), carrier)
	_check(hauler._progress(_snapshot(session), worker, order, tick, session.stores, budget_config).is_empty(), "no remote delivery or early fee")
	_place(session, carrier, str(order.destination_location_id), "working")
	var delivered := hauler._progress(_snapshot(session), _snapshot(session).get_entity(carrier), order, tick, session.stores, budget_config)
	_check(session.writer.apply_result(delivered.transaction, session.stores), "delivery enters the actual recipient pantry")
	_check(Food.balance(session.stores.item_store.list_items_for_owner(carrier), carrier) == before + int(order.fee), "carrier paid only on delivery")
	_place(session, receiver, str(order.destination_location_id), "home")
	var received := Budget.new().plan_home_transfer(_snapshot(session), _snapshot(session).get_entity(receiver), tick, budget_config, session.stores)
	_check(received.has("transaction") and session.writer.apply_result(received.transaction, session.stores), "requester must physically take delivered food")
	_check(_snapshot(session).get_relation(receiver, donor, "trust", 0) >= 4, "actual receipt changes future cooperation trust")
	_check(session.validate_persistent_references().ok, "completed assistance preserves all native references")


func _place(session: Variant, id: String, location: String, activity: String) -> void:
	var result := Result.new()
	for pair: Array in [["location_id", location], ["daily_activity", activity], ["daily_route_id", ""]]:
		result.add_state_change({"entity_id": id, "key": pair[0], "to": pair[1]})
	_check(session.writer.apply_result(result, session.stores), "test injection: controlled physical presence")
