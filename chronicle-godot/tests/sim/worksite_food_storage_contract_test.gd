extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const FARMER := "generated_resident.echo_terrace.001"
const BUYER := "generated_resident.echo_terrace.005"
const FARM := "generated_location.echo_terrace.terraces"
const HOME := "generated_home.echo_terrace.01"
var failures: Array = []
var checks := 0
var tick := {"day": 2, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test_injection.storage.60"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "worksite_food_storage_version": 1, "food_carting_version": 1}).success, "explicit warehouse world starts")
	var fixture: Dictionary = live.session.fixture_source_data.duplicate(true)
	var depot := Storage.depot_id(FARMER)
	_check(live.session.stores.entity_store.has_entity(depot), "food producer has stable worksite storage, no second inventory")
	# The controlled stock, presence and timing below are test injection.
	for person: Dictionary in fixture.entities:
		if person.type == "person":
			person.states.hunger = "low"
			person.states.health = 100
			person.states.fatigue = 0
		if person.id == FARMER:
			person.states.location_id = FARM
			person.states.daily_activity = "working"
			person.states.livelihood_elapsed_hours = 3
		if person.id == BUYER:
			person.states.location_id = FARM
			person.states.hunger = "high"
	fixture.known_facts.append({"fact_id": "test_injection.storage.harvest", "fact_type": "test_injection", "actor_id": FARMER})
	fixture.initial_items.append({"item_instance_id": "test_injection.storage.food", "item_def_id": "item.root_vegetable_portion",
		"holder": {"kind": "entity", "id": depot}, "quantity": 24,
		"provenance": {"source_kind": "test_injection", "created_by_fact_id": "test_injection.storage.harvest"}})
	var s = _session(fixture)
	var profile: Dictionary = {}
	for candidate: Dictionary in s.npc_livelihood_profiles:
		if candidate.get("workplace_id") == FARM and candidate.get("occupation_id") == "terrace_farmer":
			profile = candidate
	_check(not profile.is_empty(), "real food production profile located")
	_check(not Storage.has_capacity(_snapshot(s), FARMER, profile, Storage.PROFILE), "full inventory blocks further production")
	var blocked := Work.new().resolve_work_tick(_snapshot(s), s.npc_livelihood_profiles, tick, fixture.resident_daily_life)
	var spent := false
	for result: Variant in blocked.results:
		for fact: Dictionary in result.facts_added:
			spent = spent or (fact.get("actor_id") == FARMER and fact.get("fact_type") == "npc_livelihood_produced")
	_check(not spent, "full store does not harvest, consume inputs or advance a production cycle")
	_check(Storage.new().plan_withdrawal(_snapshot(s), _snapshot(s).get_entity(FARMER), tick, Storage.PROFILE, s.stores).is_empty(), "fed on-shift producer does not keep filling a bottomless backpack")
	var leaving := tick.duplicate()
	leaving.hour = 19
	var pickup := Storage.new().plan_withdrawal(_snapshot(s), _snapshot(s).get_entity(FARMER), leaving, Storage.PROFILE, s.stores)
	_check(pickup.get("event", {}).get("quantity") == 4, "before leaving, loads a finite household bundle")
	_check(s.writer.apply_result(pickup.transaction, s.stores), "withdrawal uses atomic item transfer")
	_check(Storage.quantity(s.stores.item_store.list_items(), depot) == 20 and Food.food_quantity(s.stores.item_store.list_items(), FARMER) == 4, "warehouse and carried portions are distinct real stacks")
	_check(Storage.new().plan_withdrawal(_snapshot(s), _snapshot(s).get_entity(FARMER), leaving, Storage.PROFILE, s.stores).is_empty(), "cannot repeat withdrawal beyond carry target")
	var absent := fixture.duplicate(true)
	_change(absent, FARMER, "location_id", HOME)
	var remote = _session(absent)
	_check(Storage.new().plan_withdrawal(_snapshot(remote), _snapshot(remote).get_entity(FARMER), leaving, Storage.PROFILE, remote.stores).is_empty(), "owner cannot take warehouse goods from home")
	var wrong_person := Storage.new().plan_withdrawal(_snapshot(s), _snapshot(s).get_entity(BUYER), leaving, Storage.PROFILE, s.stores)
	_check(wrong_person.is_empty(), "being at the field does not authorize taking another person's stock")
	var policy := {"market_policy_id": "test_injection.storage.market", "seller_entity_id": FARMER, "stock_entity_id": depot,
		"location_id": FARM, "sellable_item_tags_any": ["food"], "accepted_currency_item_def_ids": [Food.CURRENCY]}
	_check(Market.new().build_stock_view(policy, remote.stores, BUYER).get("error") == "market_stock_access_denied", "absent owner cannot sell storage remotely")
	var unauthorized := policy.duplicate()
	unauthorized.seller_entity_id = BUYER
	_check(Market.new().build_stock_view(unauthorized, s.stores, FARMER).get("error") == "market_stock_access_denied", "market rejects a forged warehouse seller")
	var offer: Dictionary = Market.new().build_stock_view(policy, s.stores, BUYER).offers[0]
	var sale := Market.new().plan_trade(policy, {"buyer_entity_id": BUYER, "item_instance_id": offer.item_instance_id,
		"quantity": 1, "quoted_unit_price": offer.unit_price, "exchange_id": "test_injection.storage.sale"}, s.stores, {"day": 2, "elapsed_hours": 60})
	_check(sale.success and s.writer.apply_result(sale.transaction, s.stores), "owner can sell a real stored portion at the worksite")
	_check(Storage.quantity(s.stores.item_store.list_items(), depot) == 19, "warehouse sale removes exact stock")
	_check(Food.balance(s.stores.item_store.list_items(), FARMER) == 8, "payment goes to the producer, not an invented shop budget")
	var reduced := fixture.duplicate(true)
	reduced.initial_items.back().quantity = 12
	var moved_work := reduced.duplicate(true)
	_change(moved_work, FARMER, "workplace_id", HOME)
	_change(moved_work, FARMER, "location_id", HOME)
	var moved = _session(moved_work)
	_check(not Storage.has_capacity(_snapshot(moved), FARMER, profile, Storage.PROFILE), "changed workplace cannot create food in a remote old warehouse")
	var room = _session(reduced)
	_check(Storage.has_capacity(_snapshot(room), FARMER, profile, Storage.PROFILE), "consumption or sale reopens production capacity")
	var harvest := Work.new().resolve_work_tick(_snapshot(room), room.npc_livelihood_profiles, tick, reduced.resident_daily_life)
	_check(room.writer.apply_results(harvest.results, room.stores), "resumed production commits")
	_check(Storage.quantity(room.stores.item_store.list_items(), depot) == 24 \
		and Food.food_quantity(room.stores.item_store.list_items(), FARMER) == 0, "new batch lands at worksite, not on producer")
	_check(room.save_to_path("user://tests/worksite_food_storage/full.json").ok, "full store saves")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/worksite_food_storage/full.json").success, "full store restores")
	var metadata := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
	_check(room.advance_time(1, "storage_test", metadata).success and restored.advance_time(1, "storage_test", metadata).success, "both native branches continue")
	_check(_signature(room) == _signature(restored), "full world continuation is identical")
	var bad_depot: Dictionary = s.stores.entity_store.get_entity(depot)
	bad_depot.stock_custodian_id = BUYER
	_check(Storage.validate_depot(bad_depot, s.stores, s.context.locations) != "", "custodian substitution rejected")
	bad_depot = s.stores.entity_store.get_entity(depot)
	bad_depot.stock_location_id = "missing.place"
	_check(Storage.validate_depot(bad_depot, s.stores, s.context.locations) != "", "unknown storage location rejected")
	var legacy := Live.new()
	_check(legacy.start({"scenario": "echo_realm"}).success and not legacy.session.fixture_source_data.has("worksite_food_storage_generated"), "failed balance experiment is not silently enabled in default world")
	print("WORKSITE_FOOD_STORAGE_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _change(fixture: Dictionary, id: String, key: String, value: Variant) -> void:
	for actor: Dictionary in fixture.entities:
		if actor.id == id:
			actor.states[key] = value


func _session(fixture: Dictionary) -> Variant:
	var s := Session.new()
	_check(s.start_from_fixture_data(fixture, []).success, "controlled fixture starts")
	return s


func _snapshot(s: Variant) -> Variant:
	return Snapshot.new().build_snapshot(s.context, s.stores, true)


func _signature(s: Variant) -> String:
	var e: Dictionary = s.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
