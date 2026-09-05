extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Livelihood = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const DailyLife = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
var failures: Array = []
var checks := 0
var buyer := ""
var seller := ""
var location := ""
var tick := {"day": 1, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test_injection.food_purchase"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := Live.new()
	_check(model.start({"scenario": "generated_network", "challenge_seed_override": 81001,
		"resident_food_access_version": 0}).success, "presence-only baseline")
	var snapshot = _snapshot(model.session)
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if "generated_resident" not in person.get("tags", []):
			continue
		if buyer == "" and Food.balance(snapshot.get_items(), str(person.id)) >= 4:
			buyer = str(person.id)
		elif seller == "":
			seller = str(person.id)
	location = str(model.session.context.location_id)
	_check(buyer != "" and seller != "" and buyer != seller, "distinct funded buyer and seller")
	if buyer == "" or seller == "":
		_finish()
		return
	var fixture: Dictionary = model.session.fixture_source_data.duplicate(true)
	for entity: Dictionary in fixture.entities:
		if entity.id in [buyer, seller]:
			entity.states.location_id = location
			entity.states.hunger = "high" if entity.id == buyer else "none"
			entity.states.daily_activity = "seeking_food" if entity.id == buyer else "working"
	fixture.initial_items.append({"item_instance_id": "test_injection.food", "item_def_id": "item.root_vegetable_portion",
		"holder": {"kind": "entity", "id": seller}, "quantity": 12,
		"provenance": {"source_kind": "test_injection"}})
	var session = _session(fixture)
	var before_items: Array = session.stores.item_store.list_items()
	var old_money := Food.balance(before_items, buyer)
	var old_seller_money := Food.balance(before_items, seller)
	var plan := _plan(session)
	_check(plan.has("transaction") and plan.event.get("event_type") == "resident_food_purchased", "local real surplus yields purchase plan")
	if not plan.has("transaction"):
		_finish()
		return
	_check(Food.food_quantity(session.stores.item_store.list_items(), buyer) == 0, "planning does not mutate goods")
	_check(session.writer.apply_result(plan.transaction, session.stores), "purchase committed through existing writer")
	var quantity := int(plan.event.quantity)
	var paid := int(plan.event.total_price)
	_check(Food.food_quantity(session.stores.item_store.list_items(), buyer) == quantity, "goods reach actual buyer")
	_check(Food.food_quantity(session.stores.item_store.list_items(), seller) == 12 - quantity, "same goods leave seller")
	_check(Food.balance(session.stores.item_store.list_items(), buyer) == old_money - paid \
		and Food.balance(session.stores.item_store.list_items(), seller) == old_seller_money + paid, "actual copper payment conserves both balances")
	_check(not session.writer.apply_result(plan.transaction, session.stores), "same transaction cannot settle twice")
	_check(_plan(session).is_empty(), "owned food prevents immediate repeated purchase")
	var food_before := _total_food(session)
	var food_rules := DailyLife.PROFILE.duplicate(true)
	food_rules["food_access"] = Food.PROFILE.duplicate(true)
	var meal: Dictionary = Livelihood.new().resolve_household_support(_snapshot(session), tick, food_rules)
	_check(session.writer.apply_results(meal.results, session.stores), "purchased food enters existing meal rules")
	_check(_total_food(session) < food_before and session.stores.state_store.get_state(buyer, "hunger") not in ["high", "extreme"], "real consumption relieves hunger")
	var purchase_source := false
	for result: Variant in meal.results:
		for fact: Dictionary in result.facts_added:
			purchase_source = purchase_source or plan.event.fact_id in fact.get("source_fact_ids", [])
	_check(purchase_source, "meal directly cites acquired goods transaction")
	_check(session.validate_persistent_references().ok, "references and currency after meal")
	var path := "user://tests/resident_food_access/purchased.json"
	_check(session.save_to_path(path).ok, "native save after purchase and consumption")
	var restored := Session.new()
	_check(restored.load_from_path(path).success, "native restore purchase")
	_check(_native_stores(session) == _native_stores(restored), "native stores roundtrip exact")
	_check(not Food.enabled(restored.world_tick_adapter.daily_life_config.get("food_access", {})), "old presence-only bootstrap does not acquire shopping on load")

	var remote := fixture.duplicate(true)
	_change(remote, seller, "location_id", "generated_location.reed_bay.landing")
	_check(_plan(_session(remote)).event.get("reason") == "no_local_surplus", "test injection: remote inventory is not delivered")
	remote = fixture.duplicate(true)
	_change(remote, seller, "daily_route_id", "test_injection.in_transit")
	_check(_plan(_session(remote)).event.get("reason") == "no_local_surplus", "test injection: moving seller is absent")
	remote = fixture.duplicate(true)
	_change(remote, buyer, "daily_route_id", "test_injection.in_transit")
	_check(_plan(_session(remote)).is_empty(), "test injection: moving buyer cannot pay remotely")
	remote = fixture.duplicate(true)
	_change(remote, seller, "alive", false)
	_check(_plan(_session(remote)).event.get("reason") == "no_local_surplus", "test injection: dead seller cannot trade")
	remote = fixture.duplicate(true)
	for item: Dictionary in remote.initial_items:
		if item.item_def_id == Food.CURRENCY and item.holder.get("id") == buyer:
			item.holder.id = seller
	var poor = _session(remote)
	var denied := _plan(poor)
	_check(denied.event.get("reason") == "unaffordable", "test injection: has goods but no money is a distinct failure")
	_check(poor.writer.apply_result(denied.transaction, poor.stores), "failed attempt records no exchange or inventory mutation")
	_check(_total_food(poor) == 12 and Food.food_quantity(poor.stores.item_store.list_items(), buyer) == 0, "no free food rescue")
	_check(_plan(poor).is_empty(), "failed local offer is not spammed every hour")
	# New stock can be noticed immediately; a failed attempt is not a blind timer.
	var waiting = _session(fixture)
	var empty_inventory := fixture.duplicate(true)
	empty_inventory.initial_items.back().quantity = 2
	var empty = _session(empty_inventory)
	var no_stock := _plan(empty)
	_check(empty.writer.apply_result(no_stock.transaction, empty.stores), "waiting buyer records unavailable stock")
	_check(waiting.writer.apply_result(no_stock.transaction, waiting.stores), "test injection: carry same failed observation to stocked local state")
	_check(_plan(waiting).event.get("event_type") == "resident_food_purchased", "newly visible surplus overrides old failed attempt without extra delay")
	remote = fixture.duplicate(true)
	remote.initial_items.back().quantity = 2
	_check(_plan(_session(remote)).event.get("reason") == "no_local_surplus", "seller retains survival food")
	remote = fixture.duplicate(true)
	var home := str(_snapshot(session).get_entity_state(seller, "home_location_id", ""))
	_change(remote, buyer, "location_id", home)
	_change(remote, seller, "location_id", home)
	_check(_plan(_session(remote)).is_empty(), "private home is not a public market")
	var same = _session(fixture)
	var stale := _plan(same)
	_check(same.writer.apply_result(stale.transaction, same.stores), "first claimant receives goods")
	_check(not same.writer.apply_result(stale.transaction, same.stores), "stale second claimant cannot double spend")
	var on_road := fixture.duplicate(true)
	for item: Dictionary in on_road.initial_items:
		if item.item_instance_id == "test_injection.food":
			item.holder.id = buyer
	_change(on_road, buyer, "daily_life_version", 1)
	_change(on_road, buyer, "daily_route_id", "test_injection.in_transit")
	var traveler = _session(on_road)
	var road_meal: Dictionary = Livelihood.new().resolve_household_support(_snapshot(traveler), tick, food_rules)
	_check(traveler.writer.apply_results(road_meal.results, traveler.stores), "test injection: traveler eats from own carried inventory")
	_check(traveler.stores.state_store.get_state(buyer, "hunger") not in ["high", "extreme"], "being in transit does not make own food inaccessible")
	var fresh := Live.new()
	_check(fresh.start({"scenario": "generated_network", "challenge_seed_override": 81001}).success, "new formal world")
	_check(Food.enabled(fresh.session.world_tick_adapter.daily_life_config.get("food_access", {})), "new world explicitly enables food access")
	var count_food_profiles := 0
	for profile: Dictionary in fresh.session.npc_livelihood_profiles:
		if Food.is_food_producer(profile):
			count_food_profiles += 1
			_check(int(profile.work_interval_hours) == 4 and int(profile.products[0].quantity) == 12, "new batch has explicit real work and output units")
	_check(count_food_profiles >= 2, "fish and roots use same purchase contract")
	var mixed := {"resident_daily_life": {"food_access": Food.PROFILE.duplicate(true)}, "generated_livelihood_profiles": [
		{"occupation_id": "test_mixed", "products": [{"item_def_id": "item.root_vegetable_portion", "quantity": 3},
			{"item_def_id": Food.CURRENCY, "quantity": 1}]}]}
	Food.configure_fixture(mixed)
	_check(int(mixed.generated_livelihood_profiles[0].products[1].quantity) == 1, "batch calibration never boosts non-food outputs")
	var configured := JSON.stringify(mixed)
	Food.configure_fixture(mixed)
	_check(JSON.stringify(mixed) == configured, "persisted batch setup is idempotent")
	var bad: Dictionary = fresh.session.fixture_source_data.duplicate(true)
	bad.resident_daily_life.food_access.production_batch.work_hours = 0
	_check(not Session.new().start_from_fixture_data(bad, []).success, "zero labor batch rejected instead of silently normalized")
	_check(fresh.session.advance_time(8, "food_test", {"scope_type": "global", "scope_id": "", "source": "passive_test"}).success, "passive eight hours")
	_check(fresh.session.action_count == 0 and fresh.session.travel_count == 0, "NPC food intent does not impersonate player actions")
	_check(fresh.session.validate_persistent_references().ok, "food journeys retain valid references")
	_finish()


func _plan(session: Variant) -> Dictionary:
	var snapshot = _snapshot(session)
	return Food.new().plan_purchase(snapshot, snapshot.get_entity(buyer), tick, Food.PROFILE, session.context.locations, session.stores)


func _session(fixture: Dictionary) -> Variant:
	var session := Session.new()
	_check(session.start_from_fixture_data(fixture, []).success, "test injection fixture starts")
	return session


func _snapshot(session: Variant) -> Variant:
	return Snapshot.new().build_snapshot(session.context, session.stores, true)


func _total_food(session: Variant) -> int:
	var quantity := 0
	for item: Dictionary in session.stores.item_store.list_items():
		if Food.is_food(item):
			quantity += int(item.quantity)
	return quantity


func _change(fixture: Dictionary, id: String, key: String, value: Variant) -> void:
	for entity: Dictionary in fixture.entities:
		if entity.id == id:
			entity.states[key] = value


func _native_stores(session: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(session.build_save_envelope().stores, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func _finish() -> void:
	print("RESIDENT_FOOD_ACCESS_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
