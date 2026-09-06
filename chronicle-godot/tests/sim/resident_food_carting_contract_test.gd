extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Cart = preload("res://scripts/sim/economy/resident_food_carting.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const CARTER := "generated_resident.echo_terrace.005"
const FARMER := "generated_resident.echo_terrace.001"
const BUYER := "generated_resident.echo_terrace.006"
const FARM := "generated_location.echo_terrace.terraces"
const STALL := "generated_location.echo_terrace.commons"
var checks := 0
var failures: Array = []
var fixture: Dictionary
var tick := {"day": 2, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test_injection.carting.60"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001, "food_carting_version": 1}).success, "versioned world starts")
	fixture = live.session.fixture_source_data.duplicate(true)
	_check(Cart.enabled(fixture.resident_daily_life.food_access.carting), "new bootstrap contains explicit carting config")
	# Positions, needs and food below are test injection, never autonomous or player evidence.
	for person: Dictionary in fixture.entities:
		if person.type == "person":
			person.states.hunger = "low"
			person.states.fatigue = 0
			person.states.health = 100
	_change(fixture, CARTER, "location_id", FARM)
	_change(fixture, CARTER, "daily_activity", "seeking_food")
	_change(fixture, CARTER, "daily_activity_reason", "自费收粮，带回集散点出售")
	_change(fixture, FARMER, "location_id", FARM)
	fixture.known_facts.append({"fact_id": "test_injection.carting.intent", "fact_type": "resident_activity_changed",
		"actor_id": CARTER, "intent_id": "food_carting", "day": 2, "hour": 11})
	fixture.initial_items.append({"item_instance_id": "test_injection.carting.food", "item_def_id": "item.root_vegetable_portion",
		"holder": {"kind": "entity", "id": FARMER}, "quantity": 20, "provenance": {"source_kind": "test_injection"}})
	var s = _session(fixture)
	var total := _totals(s)
	var purchase := _buy(s, CARTER)
	_check(purchase.has("transaction") and purchase.get("event", {}).get("quantity") == 3, "three existing coins buy only three bulk portions")
	if not purchase.has("transaction"):
		_finish()
		return
	_check(s.writer.apply_result(purchase.transaction, s.stores), "bulk purchase uses real market transaction")
	_check(_totals(s) == total, "food and currency conserved on pickup")
	_check(Food.balance(s.stores.item_store.list_items(), CARTER) == 0, "no outside working capital or income on pickup")
	_check(_buy(s, CARTER).is_empty(), "unsold cargo stops another purchase")
	var goods: Dictionary = purchase.transaction.facts_added[0]
	_check(goods.purpose_id == "food_carting" and goods.fields.unit_price == 1, "bulk surplus price and purpose recorded")
	var item: Dictionary = s.stores.item_store.get_item(str(goods.received_item_instance_id))
	_check(Cart.purchase_source(_snapshot(s), item, CARTER).is_empty(), "same-place resale is not a transport service")
	_check(s.save_to_path("user://tests/food_carting/pickup.json").ok, "paid cargo saves natively")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/food_carting/pickup.json").success, "paid cargo restores")
	_check(_totals(restored) == total, "restore preserves stock and coins")
	var snap = _snapshot(s)
	var routes: Array = Daily.new()._routes(snap, s.world_tick_adapter.settlement_network_config,
		s.context.locations, s.world_tick_adapter.daily_life_routes, fixture.resident_daily_life)
	_check(not Daily.new()._next_edge(routes, FARM, STALL).is_empty(), "actual route exists from pickup to stall")
	var traveling := _fixture_from(s)
	_change(traveling, CARTER, "daily_activity_reason", "")
	var moving = _session(traveling)
	var activity := _daily(moving, moving.world_tick_adapter.daily_life_routes)
	_check(moving.writer.apply_results(activity.results, moving.stores), "dispatch commits formal travel")
	_check(_snapshot(moving).get_entity_state(CARTER, "location_id", "") == FARM \
		and _snapshot(moving).get_entity_state(CARTER, "daily_route_id", "") != "", "dispatch cannot teleport cargo or person")
	_check(_buy(moving, CARTER).is_empty(), "cannot transact while traveling")
	_check(moving.save_to_path("user://tests/food_carting/transit.json").ok, "in-transit cargo saves")
	var resumed := Session.new()
	_check(resumed.load_from_path("user://tests/food_carting/transit.json").success, "in-transit cargo restores")
	var metadata := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
	_check(moving.advance_time(1, "carting_test", metadata).success and resumed.advance_time(1, "carting_test", metadata).success, "both branches advance")
	_check(_signature(moving) == _signature(resumed), "native continuation keeps whole state identical")
	var blocked = _session(traveling)
	var blocked_activity := _daily(blocked, [])
	_check(blocked.writer.apply_results(blocked_activity.results, blocked.stores), "blocked route result commits")
	_check(_snapshot(blocked).get_entity_state(CARTER, "daily_activity", "") == "blocked", "cargo cannot cross a missing route")
	var arrived := _fixture_from(s)
	_change(arrived, CARTER, "location_id", STALL)
	_change(arrived, CARTER, "daily_activity", "working")
	_change(arrived, CARTER, "daily_activity_reason", "携粮到集散点，等待真实买家")
	_change(arrived, BUYER, "location_id", STALL)
	_change(arrived, BUYER, "hunger", "high")
	var stall = _session(arrived)
	_check(not Cart.purchase_source(_snapshot(stall), item, CARTER).is_empty(), "transported lot retains paid source")
	var sale := _buy(stall, BUYER)
	_check(sale.has("transaction") and sale.event.total_price == 4 and sale.event.quantity == 2, "finite buyer pays actual cost plus one per portion")
	if not sale.has("transaction"):
		_finish()
		return
	_check(stall.writer.apply_result(sale.transaction, stall.stores), "retail exchange commits")
	_check(Food.balance(stall.stores.item_store.list_items(), CARTER) == 4, "carter receives buyer coins, not treasury wages")
	_check(Food.balance(stall.stores.item_store.list_items(), BUYER) == 0, "buyer really pays")
	_check(Food.food_quantity(stall.stores.item_store.list_items(), CARTER) == 1, "seller retains a real meal")
	_check(_totals(stall) == total, "retail conserves all food and money")
	var sale_fact: Dictionary = sale.transaction.facts_added[0]
	_check(sale_fact.transport_source_fact_id == goods.fact_id and sale_fact.transport_margin == 2, "income links back to purchased and transported goods")
	_check(_buy(stall, BUYER).is_empty(), "fed stock prevents infinite sales")
	var meal_data := Work.new().resolve_household_support(_snapshot(stall), tick, fixture.resident_daily_life)
	var eaten := false
	for result: Variant in meal_data.results:
		for fact: Dictionary in result.facts_added:
			if fact.get("target_id") == BUYER and fact.get("fact_type") == "npc_self_meal":
				eaten = sale_fact.fact_id in fact.get("source_fact_ids", [])
	_check(eaten, "meal consumes the delivered lot with retail source")
	_check(stall.writer.apply_results(meal_data.results, stall.stores), "actual meal commits")
	_check(stall.validate_persistent_references().ok, "all references audited")
	for variant: String in ["absent", "no_cash", "dead", "no_need"]:
		var bad := arrived.duplicate(true)
		if variant == "absent":
			_change(bad, BUYER, "location_id", FARM)
		elif variant == "no_cash":
			for stack: Dictionary in bad.initial_items:
				if stack.item_def_id == Food.CURRENCY and stack.holder.id == BUYER:
					stack.holder.id = FARMER
		elif variant == "dead":
			_change(bad, CARTER, "alive", false)
		else:
			_change(bad, BUYER, "hunger", "low")
		var counter = _session(bad)
		var attempt := _buy(counter, BUYER)
		_check(not attempt.has("transaction") or attempt.transaction.item_changes.is_empty() \
			or attempt.transaction.facts_added[0].get("target_id") != CARTER, "no carter sale when " + variant)
	var no_food := fixture.duplicate(true)
	no_food.initial_items.pop_back()
	var empty_attempt := _buy(_session(no_food), CARTER)
	_check(empty_attempt.get("event", {}).get("quantity", 0) == 0, "no inventory means no pickup")
	var at_work := fixture.duplicate(true)
	for person: Dictionary in at_work.entities:
		if person.id == CARTER:
			person.states.location_id = person.states.workplace_id
	_change(at_work, CARTER, "daily_activity", "working")
	_change(at_work, CARTER, "livelihood_elapsed_hours", 9)
	_check(_wages(_session(at_work)) == 0, "carting version removes timer wage even at old workplace")
	at_work.resident_daily_life.food_access.erase("carting")
	_check(_wages(_session(at_work)) == 2, "legacy bootstrap preserves old wage rule")
	var invalid := fixture.duplicate(true)
	invalid.resident_daily_life.food_access.carting.minimum_load = 1.5
	_check(not Session.new().start_from_fixture_data(invalid, []).success, "fractional business configuration rejected")
	var old := Live.new()
	_check(old.start({"scenario": "echo_realm", "food_carting_version": 0}).success \
		and not old.session.fixture_source_data.resident_daily_life.food_access.has("carting"), "explicit prior world rules remain available")
	_finish()


func _buy(s: Variant, who: String) -> Dictionary:
	var snap = _snapshot(s)
	return Food.new().plan_purchase(snap, snap.get_entity(who), tick,
		s.fixture_source_data.resident_daily_life.food_access, s.context.locations, s.stores)


func _daily(s: Variant, routes: Array) -> Dictionary:
	return Daily.new().resolve_tick(_snapshot(s), tick, fixture.resident_daily_life,
		s.world_tick_adapter.settlement_network_config, s.context.locations, routes, s.npc_livelihood_profiles)


func _wages(s: Variant) -> int:
	var amount := 0
	for result: Variant in Work.new().resolve_work_tick(_snapshot(s), s.npc_livelihood_profiles, tick, s.fixture_source_data.resident_daily_life).results:
		for fact: Dictionary in result.facts_added:
			if fact.get("fact_type") == "npc_wage_paid" and fact.get("target_id") == CARTER:
				amount += int(fact.amount)
	return amount


func _fixture_from(s: Variant) -> Dictionary:
	var data: Dictionary = s.fixture_source_data.duplicate(true)
	data.initial_items = s.stores.item_store.to_save_data()
	data.known_facts = s.stores.fact_store.to_save_data()
	data.initial_exchanges = s.stores.exchange_store.to_save_data()
	return data


func _session(data: Dictionary) -> Variant:
	var s := Session.new()
	_check(s.start_from_fixture_data(data, []).success, "test injection fixture starts")
	return s


func _snapshot(s: Variant) -> Variant:
	return Snapshot.new().build_snapshot(s.context, s.stores, true)


func _change(data: Dictionary, id: String, key: String, value: Variant) -> void:
	for person: Dictionary in data.entities:
		if person.id == id:
			person.states[key] = value


func _totals(s: Variant) -> Array:
	var food := 0
	var money := 0
	for item: Dictionary in s.stores.item_store.list_items():
		if Food.is_food(item):
			food += int(item.quantity)
		if item.item_def_id == Food.CURRENCY:
			money += int(item.quantity)
	return [food, money]


func _signature(s: Variant) -> String:
	var e: Dictionary = s.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func _finish() -> void:
	print("FOOD_CARTING_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
