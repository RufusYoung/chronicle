extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Daily = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Livelihood = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const Social = preload("res://scripts/sim/npc/npc_social_followup_system.gd")
const BUYER := "generated_resident.echo_terrace.005"
const TARGET := "generated_resident.echo_terrace.007"
const OTHER := "generated_resident.echo_terrace.008"
const SELLER := "generated_resident.echo_terrace.001"
const HOME := "generated_home.echo_terrace.02"
const MARKET := "generated_location.echo_terrace.terraces"
var failures: Array = []
var checks := 0
var tick := {"day": 2, "hour": 12, "elapsed_hours": 1, "tick_event_id": "test_injection.family.60"}
var fixture: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "challenge_seed_override": 81001}).success, "formal canonical world starts")
	fixture = live.session.fixture_source_data.duplicate(true)
	_check(Family.enabled(fixture.resident_daily_life.food_access.get("household_provisioning", {})), "explicit new-world family contract")
	# All altered people, goods and timing below are test injection, not autonomous outcomes.
	for person: Dictionary in fixture.entities:
		if person.type == "person":
			person.states.hunger = "low"
			person.states.fatigue = 0
			person.states.health = 100
	_change(fixture, BUYER, "location_id", HOME)
	_change(fixture, TARGET, "location_id", HOME)
	_change(fixture, OTHER, "location_id", HOME)
	_change(fixture, TARGET, "hunger", "high")
	_change(fixture, OTHER, "hunger", "high")
	_change(fixture, SELLER, "location_id", MARKET)
	fixture.initial_items.append({"item_instance_id": "test_injection.family.food", "item_def_id": "item.root_vegetable_portion",
		"holder": {"kind": "entity", "id": SELLER}, "quantity": 12, "provenance": {"source_kind": "test_injection"}})
	# Reassign existing coins; the test still has a finite conserved treasury.
	for item: Dictionary in fixture.initial_items:
		if item.item_def_id == Food.CURRENCY and item.holder.id == "generated_resident.echo_terrace.006":
			item.holder.id = BUYER
	var session = _session(fixture)
	_check(_request(session).is_empty(), "no omniscient family intent before conversation")
	_observe(session)
	_check(_request(session).targets.size() == 2, "co-present conversation records two needs")
	_check(_state(session, BUYER, "hunger") == "low", "own hunger is not required to care for family")
	var observation_count: int = session.stores.memory_store.memories.size()
	_observe(session)
	_check(session.stores.memory_store.memories.size() == observation_count, "unchanged conversation is not repeated every tick")
	var path := "user://tests/household_provisioning/remembered.json"
	_check(session.save_to_path(path).ok, "remembered need saves natively")
	var restored := Session.new()
	_check(restored.load_from_path(path).success, "remembered need restores")
	_check(_native(_request(session)) == _native(_request(restored)), "same decision after memory restore at native precision")
	var memory: Dictionary = Family.latest_observations(_snapshot(session), BUYER)[TARGET].duplicate(true)
	memory.target_id = "test_injection.missing_person"
	_check(Family.validate_memory(memory, session.stores, session.context.locations) != "", "unknown remembered person rejected")
	memory = Family.latest_observations(_snapshot(session), BUYER)[TARGET].duplicate(true)
	memory.observed_hour = 6000
	_check(Family.validate_memory(memory, session.stores, session.context.locations) != "", "memory cannot claim a date different from its evidence")
	memory = Family.latest_observations(_snapshot(session), BUYER)[TARGET].duplicate(true)
	memory.source_fact_ids = []
	_check(Family.validate_memory(memory, session.stores, session.context.locations) != "", "memory must keep its auditable evidence reference")
	var later := tick.duplicate()
	later.day = 4
	_check(Family.request(_snapshot(session), _snapshot(session).get_entity(BUYER), later, Family.PROFILE).is_empty(), "48-hour-old need expires instead of remote tracking")

	var remote := fixture.duplicate(true)
	_change(remote, TARGET, "location_id", MARKET)
	_change(remote, OTHER, "location_id", MARKET)
	var absent = _session(remote)
	_observe(absent)
	_check(_request(absent).is_empty(), "remote need cannot be discovered")
	var no_remote_requests := Livelihood.new().resolve_household_support(_snapshot(_session(fixture)), tick, fixture.resident_daily_life)
	var invented_request := false
	for result: Variant in no_remote_requests.results:
		for fact: Dictionary in result.facts_added:
			invented_request = invented_request or fact.get("fact_type") == "npc_cross_household_food_request_failed"
	_check(not invented_request, "absent neighbors are not blamed for a conversation that never occurred")
	remote = fixture.duplicate(true)
	_change(remote, BUYER, "daily_route_id", "test_injection.in_transit")
	absent = _session(remote)
	_observe(absent)
	_check(_request(absent).is_empty(), "traveling past endpoint is not co-presence")
	remote = fixture.duplicate(true)
	_change(remote, TARGET, "hunger", "low")
	_change(remote, OTHER, "hunger", "low")
	var fed = _session(remote)
	_observe(fed)
	_check(_request(fed).is_empty(), "already fed family needs no trip")
	remote = fixture.duplicate(true)
	for target: String in [TARGET, OTHER]:
		remote.initial_relationships[BUYER][target] = {"trust": -30, "familiarity": 20, "resentment": 30}
	var estranged = _session(remote)
	_observe(estranged)
	_check(not Family.latest_observations(_snapshot(estranged), BUYER).is_empty() and _request(estranged).is_empty(), "known need does not guarantee help across hostile relations")

	# Carry an actual conversation forward; later remote changes must remain unknown.
	var remembered: Dictionary = fixture.duplicate(true)
	remembered.initial_memories = session.stores.memory_store.to_save_data()
	remembered.known_facts = session.stores.fact_store.to_save_data()
	_change(remembered, BUYER, "location_id", MARKET)
	_change(remembered, BUYER, "daily_activity", "seeking_food")
	remote = remembered.duplicate(true)
	_change(remote, TARGET, "hunger", "low")
	_change(remote, OTHER, "hunger", "low")
	var uninformed = _session(remote)
	_observe(uninformed)
	_check(_request(uninformed).targets.size() == 2, "distant recovery does not magically update memory")
	_change(remote, BUYER, "location_id", HOME)
	var informed = _session(remote)
	_observe(informed)
	_check(_request(informed).is_empty(), "return conversation cancels obsolete request")

	var shopper = _session(remembered)
	var money_before := Food.balance(shopper.stores.item_store.list_items(), BUYER)
	var total_before := _food_total(shopper)
	var purchase := _purchase(shopper)
	_check(purchase.has("transaction") and purchase.get("event", {}).get("quantity") == 3, "fed resident purchases for two family members plus own reserve")
	if not purchase.has("transaction"):
		_finish()
		return
	_check(shopper.writer.apply_result(purchase.transaction, shopper.stores), "family purchase uses market transaction")
	_check(Food.balance(shopper.stores.item_store.list_items(), BUYER) == money_before - int(purchase.event.total_price), "buyer pays own real coins")
	_check(_food_total(shopper) == total_before, "purchase does not create food")
	_check(_purchase(shopper).is_empty(), "carried food prevents another purchase")
	_check(Family.new().plan_delivery(_snapshot(shopper), _snapshot(shopper).get_entity(BUYER), tick, Family.PROFILE, shopper.stores).is_empty(), "cannot deliver from market to distant home")
	_check(shopper.save_to_path("user://tests/household_provisioning/carrying.json").ok, "carried paid goods save")
	var return_fixture: Dictionary = remembered.duplicate(true)
	return_fixture.initial_items = shopper.stores.item_store.to_save_data()
	return_fixture.known_facts = shopper.stores.fact_store.to_save_data()
	return_fixture.initial_exchanges = shopper.stores.exchange_store.to_save_data()
	_change(return_fixture, BUYER, "location_id", HOME)
	_change(return_fixture, BUYER, "hunger", "high")
	var arrived = _session(return_fixture)
	var trust_before: int = _snapshot(arrived).get_relation(TARGET, BUYER, "trust", 0)
	var delivery := _delivery(arrived)
	_check(delivery.has("transaction") and delivery.events.size() == 2, "arrival allows two physical handovers")
	if not delivery.has("transaction"):
		_finish()
		return
	_check(arrived.writer.apply_result(delivery.transaction, arrived.stores), "delivery commits atomically")
	_check(Food.food_quantity(arrived.stores.item_store.list_items(), TARGET) == 1 \
		and Food.food_quantity(arrived.stores.item_store.list_items(), OTHER) == 1 \
		and Food.food_quantity(arrived.stores.item_store.list_items(), BUYER) == 1, "recipients own food and hungry carrier retains one")
	_check(_delivery(arrived).is_empty(), "fulfilled request does not deliver repeatedly")
	_check(_snapshot(arrived).get_relation(TARGET, BUYER, "trust", 0) == trust_before + 1, "receiving help changes real relationship")
	var meal := Livelihood.new().resolve_household_support(_snapshot(arrived), tick, fixture.resident_daily_life)
	_check(arrived.writer.apply_results(meal.results, arrived.stores), "delivered food can be eaten")
	_check(_state(arrived, TARGET, "hunger") == "low" and _state(arrived, OTHER, "hunger") == "low", "elders actually eat rather than lose their portion to earlier actor order")
	var cited := false
	for result: Variant in meal.results:
		for fact: Dictionary in result.facts_added:
			cited = cited or (fact.get("target_id") == TARGET and delivery.events[0].fact_id in fact.get("source_fact_ids", []))
	_check(cited or _meal_cites_delivery(meal, delivery.events), "meal cites actual handover provenance")
	var references: Dictionary = arrived.validate_persistent_references()
	if not references.ok:
		print("REFERENCE_DIAGNOSTIC ", references)
	_check(references.ok, "all observation, trade, delivery and memory references valid")
	_check(arrived.save_to_path("user://tests/household_provisioning/delivered.json").ok, "full causal chain saves")
	var loaded := Session.new()
	var load_result: Dictionary = loaded.load_from_path("user://tests/household_provisioning/delivered.json")
	if not load_result.success:
		print("LOAD_DIAGNOSTIC ", load_result)
		_check(false, "full causal chain restores")
		_finish()
		return
	_check(load_result.success, "full causal chain restores")
	_check(_signature(arrived) == _signature(loaded), "native stores and memories equal after restore")
	var meta := {"scope_type": "global", "scope_id": "", "source": "test_injection"}
	_check(arrived.advance_time(1, "continuation", meta).success and loaded.advance_time(1, "continuation", meta).success, "both worlds continue one hour")
	_check(_signature(arrived) == _signature(loaded), "native precision continuation equal")

	remote = return_fixture.duplicate(true)
	_change(remote, TARGET, "location_id", MARKET)
	_change(remote, OTHER, "alive", false)
	_check(_delivery(_session(remote)).is_empty(), "absent and dead family cannot receive a remote handover")
	remote = remembered.duplicate(true)
	for item: Dictionary in remote.initial_items:
		if item.item_def_id == Food.CURRENCY and item.holder.id == BUYER:
			item.holder.id = SELLER
	var poor = _session(remote)
	_check(_purchase(poor).get("event", {}).get("reason") == "unaffordable", "family love does not mint purchasing power")
	var empty := return_fixture.duplicate(true)
	empty.initial_items = fixture.initial_items.duplicate(true)
	_check(_delivery(_session(empty)).is_empty(), "no goods means no handover")
	_test_route_choice(remembered)
	_test_social_ownership()
	var legacy := Live.new()
	_check(legacy.start({"scenario": "echo_realm", "household_provisioning_version": 0}).success, "previous food-only rule can still start")
	_check(legacy.save_to_path("user://tests/household_provisioning/legacy.json", true).success, "legacy rule saves")
	var old := Live.new()
	_check(old.load_from_path("user://tests/household_provisioning/legacy.json").success, "legacy rule restores")
	_check(not Family.enabled(old.session.fixture_source_data.resident_daily_life.food_access.get("household_provisioning", {})), "save loading does not inject the new rule")
	var bad := fixture.duplicate(true)
	bad.resident_daily_life.food_access.household_provisioning.memory_hours = 0
	_check(not Session.new().start_from_fixture_data(bad, []).success, "invalid memory duration rejected")
	bad = fixture.duplicate(true)
	bad.resident_daily_life.food_access.household_provisioning.version = 2
	_check(not Session.new().start_from_fixture_data(bad, []).success, "unknown family rule version rejected")
	_finish()


func _test_route_choice(remembered: Dictionary) -> void:
	var local := remembered.duplicate(true)
	var start := "generated_location.echo_terrace.commons"
	_change(local, BUYER, "location_id", start)
	var routes: Array = [{"route_id": "test_injection.long_road", "from_location_id": start, "to_location_id": MARKET, "hours": 3}]
	for temperament: String in ["cautious", "bold"]:
		_change(local, BUYER, "temperament", temperament)
		var s = _session(local)
		var snap = _snapshot(s)
		var intent := _request(s)
		var goal: String = Daily.new()._food_goal(snap, snap.get_entity(BUYER), routes, s.npc_livelihood_profiles,
			tick, fixture.resident_daily_life.food_access, s.world_tick_adapter.settlement_network_config,
			s.context.locations, snap.get_items(), {}, intent)
		_check(goal == (MARKET if temperament == "bold" else ""), "same need and road, temperament changes travel tolerance: " + temperament)
		goal = Daily.new()._food_goal(snap, snap.get_entity(BUYER), [], s.npc_livelihood_profiles,
			tick, fixture.resident_daily_life.food_access, s.world_tick_adapter.settlement_network_config,
			s.context.locations, snap.get_items(), {}, intent)
		_check(goal == "", "broken road cannot be overcome by willingness")


func _test_social_ownership() -> void:
	var debt := fixture.duplicate(true)
	debt.known_facts.append({"fact_id": "fact.test_injection.old_food_help", "fact_type": "npc_cross_household_shared_food",
		"actor_id": SELLER, "requester_id": BUYER, "target_id": BUYER, "day": 1})
	debt.initial_relationships[BUYER][SELLER]["debt"] = 8
	var at_six := tick.duplicate()
	at_six.hour = 6
	var remote = _session(debt)
	_check(Social.new().resolve_tick(_snapshot(remote), at_six, fixture.resident_daily_life).results.is_empty(), "remote creditor cannot receive automatic repayment")
	_check(not Social.new().resolve_tick(_snapshot(remote), at_six).results.is_empty(), "legacy social rule remains unchanged without new version")
	_change(debt, BUYER, "location_id", MARKET)
	var together = _session(debt)
	var payment := Social.new().resolve_tick(_snapshot(together), at_six, fixture.resident_daily_life)
	_check(not payment.results.is_empty(), "co-present debtor can repay with owned goods")
	_check(together.writer.apply_results(payment.results, together.stores), "physical repayment uses real transfer")
	for item: Dictionary in debt.initial_items:
		if item.holder.id == BUYER:
			item.holder.id = OTHER
	var broke = _session(debt)
	_check(Social.new().resolve_tick(_snapshot(broke), at_six, fixture.resident_daily_life).results.is_empty(), "cannot seize another household member's coins to repay")


func _meal_cites_delivery(meal: Dictionary, events: Array) -> bool:
	for result: Variant in meal.results:
		for fact: Dictionary in result.facts_added:
			for event: Dictionary in events:
				if fact.get("target_id") == event.target_id and event.fact_id in fact.get("source_fact_ids", []):
					return true
	return false


func _observe(s: Variant) -> void:
	var observation := Family.new().observe(_snapshot(s), tick, Family.PROFILE)
	_check(s.writer.apply_results(observation.results, s.stores), "test injection: local observation commits")


func _request(s: Variant) -> Dictionary:
	var snap = _snapshot(s)
	return Family.request(snap, snap.get_entity(BUYER), tick, Family.PROFILE)


func _purchase(s: Variant) -> Dictionary:
	var snap = _snapshot(s)
	return Food.new().plan_purchase(snap, snap.get_entity(BUYER), tick, fixture.resident_daily_life.food_access,
		s.context.locations, s.stores, _request(s), Family.reservations(snap, tick, Family.PROFILE))


func _delivery(s: Variant) -> Dictionary:
	var snap = _snapshot(s)
	return Family.new().plan_delivery(snap, snap.get_entity(BUYER), tick, Family.PROFILE, s.stores)


func _session(data: Dictionary) -> Variant:
	var s := Session.new()
	_check(s.start_from_fixture_data(data, []).success, "controlled test fixture starts")
	return s


func _snapshot(s: Variant) -> Variant:
	return Snapshot.new().build_snapshot(s.context, s.stores, true)


func _state(s: Variant, id: String, key: String) -> Variant:
	return s.stores.state_store.get_state(id, key)


func _change(data: Dictionary, id: String, key: String, value: Variant) -> void:
	for person: Dictionary in data.entities:
		if person.id == id:
			person.states[key] = value


func _food_total(s: Variant) -> int:
	var total := 0
	for item: Dictionary in s.stores.item_store.list_items():
		if Food.is_food(item):
			total += int(item.quantity)
	return total


func _signature(s: Variant) -> String:
	var e: Dictionary = s.build_save_envelope()
	return _native({"stores": e.stores, "session": e.session,
		"world_time": e.world_time, "rng_states": e.rng_states, "world_log": e.world_log})


func _native(data: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(data, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func _finish() -> void:
	print("HOUSEHOLD_PROVISIONING_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
