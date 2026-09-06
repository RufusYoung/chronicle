extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const Haul = preload("res://scripts/sim/economy/household_food_hauling.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const PAYER := "generated_resident.echo_terrace.001"
const CARRIER := "generated_resident.echo_terrace.005"
const CHILD := "generated_resident.echo_terrace.003"
const FARM := "generated_location.echo_terrace.terraces"
const HOME := "generated_home.echo_terrace.01"
var fixture: Dictionary
var failures: Array = []
var checks := 0
var tick := {"day": 2, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test_injection.haul.60"}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "worksite_food_storage_version": 1, "household_food_hauling_version": 1}).success, "explicit integrated variant starts")
	fixture = live.session.fixture_source_data.duplicate(true)
	# Positions, needs and stock below are test injection, not natural orders or player choices.
	for person: Dictionary in fixture.entities:
		if person.type == "person":
			person.states.hunger = "low"
			person.states.fatigue = 0
			person.states.health = 100
		if person.id in [PAYER, CHILD]:
			person.states.location_id = HOME
		if person.id == CHILD:
			person.states.hunger = "high"
		if person.id == CARRIER:
			person.states.location_id = FARM
			person.states.daily_activity = "seeking_work"
	fixture.initial_items.append({"item_instance_id": "test_injection.haul.food", "item_def_id": "item.root_vegetable_portion",
		"holder": {"kind": "entity", "id": Storage.depot_id(PAYER)}, "quantity": 12, "provenance": {"source_kind": "test_injection"}})
	var s = _setup()
	var initial_cash := _cash(s, PAYER)
	var carrier_cash := _cash(s, CARRIER)
	var offered: Dictionary = _contact(s)
	_check(offered.has("transaction") and offered.events[0].fact_type == "food_hauling_accepted", "known family need and co-present owner create a paid agreement")
	_check(s.writer.apply_result(offered.transaction, s.stores), "food and fee reserved in one transaction")
	var order: Dictionary = Haul.active_order(_snapshot(s), CARRIER)
	_check(_cash(s, PAYER) == initial_cash - int(Haul.PROFILE.fee) and _cash(s, CARRIER) == carrier_cash, "payer loses real coins; carrier has no income at acceptance")
	_check(Food.food_quantity(s.stores.item_store.list_items(), CARRIER) == 0, "entrusted cargo is not the carrier's meal or resale stock")
	_check(Storage.quantity(s.stores.item_store.list_items(), Storage.depot_id(PAYER)) == 11, "one real portion leaves depot")
	_check(Haul.validate_order(order, s.stores, s.context.locations) == "", "native custody and ownership references are valid")
	var orphan: Dictionary = s.build_save_envelope()
	orphan.stores.exchanges = orphan.stores.exchanges.filter(func(row: Dictionary) -> bool: return row.get("exchange_type") != Haul.TYPE)
	_check(not Session.new().load_from_save_envelope(Saves.new().finalize_envelope(orphan)).success, "deleting the contract cannot orphan entrusted goods in a native save")
	_check(_contact(s).is_empty(), "at origin cannot deliver or accept a second contract")
	_check(s.save_to_path("user://tests/household_food_hauling/accepted.json").ok, "unpaid entrusted goods save")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/household_food_hauling/accepted.json").success, "in-transit contract restores")
	var metadata := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
	_check(s.advance_time(1, "haul_test", metadata).success and restored.advance_time(1, "haul_test", metadata).success, "native branches continue")
	_check(_signature(s) == _signature(restored), "full native continuation equal")
	_change(s, CARRIER, "daily_route_id", "")
	_change(s, CARRIER, "daily_travel_remaining", 0)
	_change(s, CARRIER, "location_id", HOME)
	var delivery: Dictionary = _contact(s)
	_check(delivery.has("transaction") and s.writer.apply_result(delivery.transaction, s.stores), "actual arrival hands food to recipient and releases fee")
	_check(Food.food_quantity(s.stores.item_store.list_items(), CHILD) == 1 and _cash(s, CARRIER) == carrier_cash + int(Haul.PROFILE.fee), "exact food and earned money reach recipients")
	_check(Haul.active_order(_snapshot(s), CARRIER).is_empty(), "settled work does not repeat")
	_check(s.validate_persistent_references().ok, "settled native references pass")
	var meals: Dictionary = Work.new().resolve_household_support(_snapshot(s), tick, fixture.resident_daily_life)
	_check(s.writer.apply_results(meals.results, s.stores), "delivered goods can actually feed recipient")
	var cited := false
	for fact: Dictionary in s.stores.fact_store.list_facts():
		if fact.get("fact_type") == "npc_self_meal" and fact.get("target_id") == CHILD:
			cited = delivery.events[0].fact_id in fact.get("source_fact_ids", [])
	_check(cited, "meal retains delivery provenance")
	for counterexample: String in ["no_memory", "no_cash", "absent_owner", "in_transit", "no_stock", "no_route", "no_need"]:
		var other = _setup(counterexample)
		var attempt: Dictionary = _contact(other, counterexample == "no_route")
		_check(not attempt.has("transaction") or attempt.events[0].fact_type != "food_hauling_accepted", counterexample + " cannot create paid shipment")
	var returning = _setup()
	var accepted: Dictionary = _contact(returning)
	_check(returning.writer.apply_result(accepted.transaction, returning.stores), "return scenario accepts")
	_change(returning, CARRIER, "location_id", HOME)
	_change(returning, CHILD, "location_id", FARM)
	_check(_contact(returning).is_empty(), "absent recipient receives neither cargo nor an invented receipt")
	var late := tick.duplicate()
	late.day = 3
	var expired: Dictionary = _contact(returning, false, late)
	_check(expired.has("transaction") and returning.writer.apply_result(expired.transaction, returning.stores), "overdue shipment enters return, without remote refund")
	_check(_cash(returning, PAYER) == initial_cash - int(Haul.PROFILE.fee) and _cash(returning, CARRIER) == carrier_cash, "cash stays sealed until physical return")
	_change(returning, CARRIER, "location_id", FARM)
	late.hour = 13
	var refund: Dictionary = _contact(returning, false, late)
	_check(refund.has("transaction") and returning.writer.apply_result(refund.transaction, returning.stores), "physical return restores goods and unearned fee")
	_check(_cash(returning, PAYER) == initial_cash and Storage.quantity(returning.stores.item_store.list_items(), Storage.depot_id(PAYER)) == 12, "failed job does not create or lose food and money")
	_check(returning.validate_persistent_references().ok, "returned order remains auditable")
	var corrupt: Dictionary = order.duplicate(true)
	corrupt.party_a = CARRIER
	_check(Haul.validate_order(corrupt, restored.stores, restored.context.locations) != "", "forged ownership rejected")
	corrupt = order.duplicate(true)
	corrupt.fee = 999
	_check(Haul.validate_order(corrupt, restored.stores, restored.context.locations) != "", "promised fee cannot exceed actual escrow")
	for entry: Dictionary in [{"recipient_ids": [42]}, {"delivered_ids": [null]}, {"source_fact_ids": null},
			{"need_fact_ids": [false]}, {"source_fact_ids": order.need_fact_ids}, {"party_a": order.party_b},
			{"status": "settled"}, {"recipient_ids": []}]:
		corrupt = order.duplicate(true)
		corrupt.merge(entry, true)
		_check(Haul.validate_order(corrupt, restored.stores, restored.context.locations) != "", "malformed or forged agreement rejected: " + JSON.stringify(entry))
	var unattended = _setup()
	_check(unattended.writer.apply_result(_contact(unattended).transaction, unattended.stores), "unattended-return scenario accepts")
	_change(unattended, PAYER, "location_id", HOME)
	_check(unattended.writer.apply_result(_contact(unattended, false, late).transaction, unattended.stores), "unattended order first becomes overdue")
	late.hour = 14
	_check(unattended.writer.apply_result(_contact(unattended, false, late).transaction, unattended.stores), "parcel returns to physical depot while owner absent")
	_check(_cash(unattended, PAYER) == initial_cash - int(Haul.PROFILE.fee) and _cash(unattended, Storage.depot_id(PAYER)) == int(Haul.PROFILE.fee), "absent owner's money stays at depot")
	_check(Storage.new().plan_withdrawal(_snapshot(unattended), _snapshot(unattended).get_entity(PAYER), late,
		Storage.PROFILE, unattended.stores, fixture.resident_daily_life).is_empty(), "owner cannot remotely reclaim refund")
	_change(unattended, PAYER, "location_id", FARM)
	var reclaimed := Storage.new().plan_withdrawal(_snapshot(unattended), _snapshot(unattended).get_entity(PAYER), late,
		Storage.PROFILE, unattended.stores, fixture.resident_daily_life)
	_check(reclaimed.has("transaction") and unattended.writer.apply_result(reclaimed.transaction, unattended.stores), "owner physically collects unearned-fee refund")
	_check(_cash(unattended, PAYER) == initial_cash and unattended.validate_persistent_references().ok, "round-trip ownership and native evidence remain valid")
	var old := Live.new()
	_check(old.start({"scenario": "echo_realm"}).success and not old.session.fixture_source_data.resident_daily_life.food_access.has("hauling"), "default and old worlds do not silently gain candidate rules")
	print("HOUSEHOLD_FOOD_HAULING_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _setup(counterexample: String = "") -> Variant:
	var s := Session.new()
	_check(s.start_from_fixture_data(fixture, []).success, "controlled fixture starts")
	if counterexample != "no_memory":
		if counterexample == "no_need":
			_change(s, CHILD, "hunger", "low")
		var observations: Dictionary = Family.new().observe(_snapshot(s), tick, Family.PROFILE)
		_check(s.writer.apply_results(observations.results, s.stores), "co-present conversation committed")
	if counterexample != "absent_owner":
		_change(s, PAYER, "location_id", FARM)
	if counterexample == "in_transit":
		_change(s, CARRIER, "daily_route_id", "test_injection.route")
	if counterexample in ["no_cash", "no_stock"]:
		var change := Result.new()
		change.add_fact({"fact_id": "test_injection.haul.remove", "fact_type": "test_injection", "actor_id": PAYER})
		var holder := PAYER if counterexample == "no_cash" else Storage.depot_id(PAYER)
		for item: Dictionary in s.stores.item_store.list_items_for_owner(holder):
			change.add_item_change({"operation": "transfer", "item_instance_id": item.item_instance_id,
				"new_holder": {"kind": "entity", "id": CHILD}, "source_fact_ids": ["test_injection.haul.remove"]})
		_check(s.writer.apply_result(change, s.stores), "test injection removes available goods without minting")
	return s


func _contact(s: Variant, no_route: bool = false, at: Dictionary = {}) -> Dictionary:
	var snapshot = _snapshot(s)
	var daily := Daily.new()
	var routes: Array = daily._routes(snapshot, s.settlement_network_runtime, s.context.locations, s.travel_routes, fixture.resident_daily_life)
	var finder := func(start: String, goal: String) -> Dictionary: return {} if no_route else daily._next_edge(routes, start, goal)
	return Haul.new().plan_contact(snapshot, snapshot.get_entity(CARRIER), tick if at.is_empty() else at,
		Haul.PROFILE, Family.PROFILE, s.stores, finder)


func _change(s: Variant, id: String, key: String, value: Variant) -> void:
	var result := Result.new()
	result.add_state_change({"entity_id": id, "key": key, "to": value})
	_check(s.writer.apply_result(result, s.stores), "test injection " + key)


func _snapshot(s: Variant) -> Variant:
	return Snapshot.new().build_snapshot(s.context, s.stores, true)


func _cash(s: Variant, id: String) -> int:
	return Food.balance(s.stores.item_store.list_items(), id)


func _signature(s: Variant) -> String:
	var e: Dictionary = s.build_save_envelope()
	return JSON.stringify(JSON.parse_string(JSON.stringify({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log}, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
