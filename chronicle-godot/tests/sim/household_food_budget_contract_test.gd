extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Budget = preload("res://scripts/sim/economy/household_food_budget.gd")
const Haul = preload("res://scripts/sim/economy/household_food_hauling.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const PAYER := "generated_resident.echo_terrace.001"
const CARRIER := "generated_resident.echo_terrace.005"
const CHILD := "generated_resident.echo_terrace.003"
const FARM := "generated_location.echo_terrace.terraces"
const HOME := "generated_home.echo_terrace.01"
const PANTRY := "household_food_store.generated_household.echo_terrace.01"
var tick := {"day": 2, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test_injection.budget.60"}
var failures: Array = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "household_food_budget_version": 1, "household_food_hauling_version": 1, "worksite_food_storage_version": 1}).success, "integrated explicit household variant starts")
	var fixture: Dictionary = live.session.fixture_source_data.duplicate(true)
	_check(fixture.household_food_storage_generated.pantry_ids.size() == 4, "four authored-anchor families get local empty pantries, no initial food")
	var missing: Dictionary = live.session.build_save_envelope()
	missing.stores.entities.erase(PANTRY)
	missing.stores.states.erase(PANTRY)
	_check(not Session.new().load_from_save_envelope(Saves.new().finalize_envelope(missing)).success, "missing declared empty pantry cannot silently disappear from a save")
	# Controlled stock and positions are test injection.
	for person: Dictionary in fixture.entities:
		if person.type == "person":
			person.states.hunger = "low"
			person.states.fatigue = 0
			person.states.health = 100
		if person.id in [PAYER, CHILD]:
			person.states.location_id = HOME
		if person.id == CARRIER:
			person.states.location_id = FARM
			person.states.daily_activity = "seeking_work"
	fixture.initial_items.append({"item_instance_id": "test_injection.budget.food", "item_def_id": "item.root_vegetable_portion",
		"holder": {"kind": "entity", "id": Storage.depot_id(PAYER)}, "quantity": 24, "provenance": {"source_kind": "test_injection"}})
	var s := Session.new()
	_check(s.start_from_fixture_data(fixture, []).success, "controlled household starts")
	_check(Budget.request(_snapshot(s), _snapshot(s).get_entity(PAYER), tick, Budget.PROFILE).is_empty(), "no remote pantry knowledge before observation")
	var observation := Budget.new().observe(_snapshot(s), tick, Budget.PROFILE)
	_check(s.writer.apply_results(observation.results, s.stores), "at-home inspection records supply horizon")
	var need := Budget.request(_snapshot(s), _snapshot(s).get_entity(PAYER), tick, Budget.PROFILE)
	_check(not need.is_empty() and int(need.pantry_portions) > 1, "forecasts multiple meals before anyone is starving")
	var cautious: Dictionary = _snapshot(s).get_entity(PAYER).duplicate(true)
	cautious.states.temperament = "cautious"
	_check(Budget.request(_snapshot(s), cautious, tick, Budget.PROFILE).travel_hours == 2, "forecast preserves limited cautious travel tolerance")
	var old_budget := Budget.PROFILE.duplicate(true)
	old_budget.erase("travel_hours")
	_check(Budget.request(_snapshot(s), cautious, tick, old_budget).travel_hours == 6, "old experimental bootstrap keeps its previous travel budget")
	var expired := tick.duplicate()
	expired.day = 3
	_check(Budget.request(_snapshot(s), _snapshot(s).get_entity(PAYER), expired, Budget.PROFILE).is_empty(), "old forecast expires without remote refresh")
	_change(s, PAYER, "location_id", FARM)
	var owner_cash := Food.balance(s.stores.item_store.list_items(), PAYER)
	var carrier_cash := Food.balance(s.stores.item_store.list_items(), CARRIER)
	var routing := Daily.new()
	var routes: Array = routing._routes(_snapshot(s), s.settlement_network_runtime, s.context.locations, s.travel_routes, fixture.resident_daily_life)
	var finder := func(start: String, goal: String) -> Dictionary: return routing._next_edge(routes, start, goal)
	var accepted := Haul.new().plan_contact(_snapshot(s), _snapshot(s).get_entity(CARRIER), tick, Haul.PROFILE, Family.PROFILE, s.stores, finder, Budget.PROFILE)
	_check(accepted.has("transaction") and s.writer.apply_result(accepted.transaction, s.stores), "existing forecast funds a real pantry shipment")
	var order := Haul.active_order(_snapshot(s), CARRIER)
	_check(order.get("pantry_id") == PANTRY and int(order.quantity) == int(need.pantry_portions), "shipment quantity follows household budget, not recipient count")
	_check(Food.balance(s.stores.item_store.list_items(), PAYER) == owner_cash - int(Haul.PROFILE.fee), "payer's private coins really reserved")
	_check(Budget.request(_snapshot(s), _snapshot(s).get_entity(PAYER), tick, Budget.PROFILE).is_empty(), "known promise prevents a duplicate household trip")
	_change(s, CARRIER, "location_id", HOME)
	var at := tick.duplicate()
	at.hour = 16
	var delivery := Haul.new().plan_contact(_snapshot(s), _snapshot(s).get_entity(CARRIER), at, Haul.PROFILE, Family.PROFILE, s.stores, finder, Budget.PROFILE)
	_check(delivery.has("transaction") and s.writer.apply_result(delivery.transaction, s.stores), "physical deposit is a receipt for pantry storage, not fictitious individual meals")
	_check(Food.food_quantity(s.stores.item_store.list_items(), PANTRY) == int(order.quantity) and Food.food_quantity(s.stores.item_store.list_items(), CHILD) == 0, "delivered food remains in actual cabinet until taken")
	_check(Food.balance(s.stores.item_store.list_items(), CARRIER) == carrier_cash + int(Haul.PROFILE.fee), "service payment becomes income only after deposit")
	_check(Budget.new().plan_home_transfer(_snapshot(s), _snapshot(s).get_entity(CARRIER), at, Budget.PROFILE, s.stores).is_empty(), "foreign courier has deposit permission only, not household withdrawal")
	_change(s, CHILD, "hunger", "high")
	var taking := Budget.new().plan_home_transfer(_snapshot(s), _snapshot(s).get_entity(CHILD), at, Budget.PROFILE, s.stores)
	_check(taking.has("transaction") and s.writer.apply_result(taking.transaction, s.stores), "hungry member takes one real portion at home")
	_check(Food.food_quantity(s.stores.item_store.list_items(), CHILD) == 1 and Food.food_quantity(s.stores.item_store.list_items(), PANTRY) == int(order.quantity) - 1, "cabinet and personal stock conserve goods")
	_check(delivery.events[0].fact_id in taking.events[0].source_fact_ids, "withdrawal traces delivered lot")
	_change(s, CHILD, "location_id", FARM)
	_check(Budget.new().plan_home_transfer(_snapshot(s), _snapshot(s).get_entity(CHILD), at, Budget.PROFILE, s.stores).is_empty(), "membership does not enable remote food access")
	_check(s.save_to_path("user://tests/household_food_budget/integrated.json").ok and s.validate_persistent_references().ok, "pantry, memory, ownership and receipt save together")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/household_food_budget/integrated.json").success, "native integrated save restores")
	var metadata := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
	_check(s.advance_time(1, "budget_test", metadata).success and restored.advance_time(1, "budget_test", metadata).success, "both integrated branches continue")
	_check(_signature(s) == _signature(restored), "whole native world continuation identical")
	var no_cash_fixture := fixture.duplicate(true)
	for person: Dictionary in no_cash_fixture.entities:
		if person.id == CARRIER:
			person.states.location_id = person.states.home_location_id
	for item: Dictionary in no_cash_fixture.initial_items:
		if item.get("holder", {}).get("id") == CARRIER and item.item_def_id == Food.CURRENCY:
			item.holder.id = PAYER
	var poor := Session.new()
	_check(poor.start_from_fixture_data(no_cash_fixture, []).success, "test injection: carrier has no cash but real household need")
	var forecast := Budget.new().observe(_snapshot(poor), tick, Budget.PROFILE)
	_check(poor.writer.apply_results(forecast.results, poor.stores), "poor household need is observed locally")
	var choices := Daily.new().resolve_tick(_snapshot(poor), tick, no_cash_fixture.resident_daily_life,
		poor.settlement_network_runtime, poor.context.locations, poor.travel_routes, poor.npc_livelihood_profiles)
	var seeking := false
	for result: Variant in choices.results:
		for fact: Dictionary in result.facts_added:
			if fact.get("actor_id") == CARRIER and str(fact.get("reason", "")).contains("送粮差事"):
				seeking = true
	_check(seeking, "unaffordable family shopping leads to real work search, not obsolete unpaid workplace")
	var plain := Live.new()
	_check(plain.start({"scenario": "echo_realm"}).success and not plain.session.fixture_source_data.has("household_food_storage_generated"), "default remains unchanged until autonomous evaluation passes")
	print("HOUSEHOLD_FOOD_BUDGET_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _change(s: Variant, id: String, key: String, value: Variant) -> void:
	var result := Result.new()
	result.add_state_change({"entity_id": id, "key": key, "to": value})
	_check(s.writer.apply_result(result, s.stores), "test injection " + key)


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
