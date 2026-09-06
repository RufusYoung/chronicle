extends SceneTree

const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Session = preload("res://scripts/sim/core/sim_session.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Work = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const Subsistence = preload("res://scripts/sim/npc/resident_subsistence.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const DailyLife = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const ACTOR := "generated_resident.echo_terrace.007"
const FARM := "generated_location.echo_terrace.terraces"
const STOCK := "resource_stock.echo_terrace.resource_echo_terrace_soil"
var fixture: Dictionary
var failures: Array = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live := Live.new()
	_check(live.start({"scenario": "echo_realm", "resident_subsistence_version": 1}).success, "explicit adaptive subsistence world starts")
	fixture = live.session.fixture_source_data.duplicate(true)
	for actor: Dictionary in fixture.entities:
		if actor.type == "person":
			actor.states.health = 10
		if actor.id == ACTOR:
			actor.states.health = 100
			actor.states.fatigue = 0
			actor.states.location_id = FARM
			actor.states.daily_activity = "foraging"
			actor.states.hunger = "high"
	var s = _session()
	var initial_resource := float(s.stores.resource_stock_store.get_stock(STOCK).current)
	var initial_cash := _currency(s)
	for hour: int in range(12, 15):
		_work(s, hour)
	_check(Food.food_quantity(s.stores.item_store.list_items(), ACTOR) == 0, "three actual work hours produce no early food")
	_check(s.stores.state_store.get_state(ACTOR, "livelihood_elapsed_hours", 0) == 0, "subsistence does not advance occupational wages or production")
	_check(s.save_to_path("user://tests/resident_subsistence/partial.json").ok, "partial local work saves")
	var restored := Session.new()
	_check(restored.load_from_path("user://tests/resident_subsistence/partial.json").success, "partial work restores from native disk")
	_work(s, 15)
	_work(restored, 15)
	_check(_native(s.get_save_store_data()) == _native(restored.get_save_store_data()), "native partial-work continuation matches exactly")
	_check(Food.food_quantity(s.stores.item_store.list_items(), ACTOR) == 4, "four hours yield four real personally carried portions")
	_check(is_equal_approx(float(s.stores.resource_stock_store.get_stock(STOCK).current), initial_resource - 0.75), "same commons input is actually consumed, no extra resource source")
	_check(_currency(s) == initial_cash and s.stores.state_store.get_state(ACTOR, "occupation_id") == "retired", "no minted wages or automatic permanent profession change")
	var produced: Dictionary = s.stores.fact_store.find_facts_by_type("npc_livelihood_produced").back()
	_check(produced.work_kind == "subsistence" and produced.actual_location_id == FARM and produced.work_hours == 4, "production proves actual place and lower-skilled work")
	for mode: String in ["absent", "traveling", "exhausted", "injured", "child", "permission_denied", "depleted"]:
		var other = _session(mode)
		var before := float(other.stores.resource_stock_store.get_stock(STOCK).current)
		for hour: int in range(12, 16):
			_work(other, hour)
		_check(Food.food_quantity(other.stores.item_store.list_items(), ACTOR) == 0, mode + " cannot create food")
		_check(is_equal_approx(float(other.stores.resource_stock_store.get_stock(STOCK).current), before), mode + " consumes no unauthorized input")
		if mode in ["permission_denied", "depleted"]:
			var blocked: Array = other.stores.fact_store.find_facts_by_type("npc_livelihood_blocked_resource")
			_check(not blocked.is_empty() and blocked.back().work_kind == "subsistence", mode + " is an observed failure, not hidden subsidy")
			other.stores.resource_stock_store.stocks[STOCK].access.resident_production = true
			other.stores.resource_stock_store.stocks[STOCK].current = initial_resource
			for hour: int in range(12, 16):
				_work(other, hour, 3)
			_check(Food.food_quantity(other.stores.item_store.list_items(), ACTOR) == 4, "test injection: restored access or supply permits actual work again")
	var legacy := Live.new()
	_check(legacy.start({"scenario": "echo_realm"}).success, "old-rule world starts")
	var envelope: Dictionary = legacy.session.build_save_envelope()
	envelope.definition_manifest.content_pack_version = 4
	for key: String in Subsistence.STATE_KEYS:
		envelope.definition_manifest.required_definition_ids.erase("state:state.character." + key)
	var migrated := Session.new()
	var loaded := migrated.load_from_save_envelope(Saves.new().finalize_envelope(envelope))
	_check(loaded.success and Session.SUBSISTENCE_DEFINITIONS_MIGRATION in loaded.migrations, "exact historical manifest upgrades explicitly")
	_check(not migrated.fixture_source_data.resident_daily_life.food_access.has("subsistence"), "definition migration never enables new behavior in an old world")
	_affordability()
	print("RESIDENT_SUBSISTENCE_RESULT %s %d/%d" % ["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _affordability() -> void:
	var s = _session()
	var actor: Dictionary = Snapshot.new().build_snapshot(s.context, s.stores, true).get_entity(ACTOR)
	var items := [{"item_def_id": Food.CURRENCY, "quantity": 3, "holder": {"kind": "entity", "id": ACTOR}}]
	var family := {"target_portions": 8, "source_fact_ids": ["test_injection.family_need"]}
	var tick := {"day": 3, "hour": 8}
	var snapshot = Snapshot.new().build_snapshot(s.context, s.stores, true)
	_check(not Subsistence.wants_work(snapshot, actor, items, family, Subsistence.PROFILE, tick), "unknown prices do not imply family purchasing failure")
	var transaction := Result.new()
	transaction.add_fact({"fact_id": "test_injection.family_need", "fact_type": "test_injection"})
	transaction.add_fact({"fact_id": "test_injection.quoted_purchase", "fact_type": "resident_food_purchased", "actor_id": ACTOR,
		"day": 2, "hour": 15, "fields": {"unit_price": 2}, "summary": "Test injection: remembered personal quote."})
	_check(s.writer.apply_result(transaction, s.stores), "controlled personal quote evidence")
	snapshot = Snapshot.new().build_snapshot(s.context, s.stores, true)
	var decision := Subsistence.decision(snapshot, actor, items, family, Subsistence.PROFILE, tick)
	_check(not decision.is_empty() and "test_injection.quoted_purchase" in decision.source_fact_ids, "one affordable meal does not meet remembered household demand; next-morning decision cites own quote")
	_check(not Subsistence.wants_work(snapshot, actor, items, {}, Subsistence.PROFILE, tick), "the same wallet covers a lone person's immediate meal")
	items[0].quantity = 16
	_check(not Subsistence.wants_work(snapshot, actor, items, family, Subsistence.PROFILE, tick), "enough real money keeps purchasing available")
	items[0].quantity = 3
	_check(not Subsistence.wants_work(snapshot, actor, items, family, Subsistence.PROFILE, {"day": 3, "hour": 15}), "old quote expires instead of becoming permanent world price knowledge")
	var previous := Subsistence.PROFILE.duplicate(true)
	previous.erase("household_affordability_version")
	previous.erase("quote_memory_hours")
	_check(Subsistence.validate_config(previous) == "" and not Subsistence.wants_work(snapshot, actor, items, family, previous, tick), "old explicit bootstrap retains one-meal affordability behavior")
	# Read-only snapshot injection isolates shift selection, without claiming natural work or wages.
	s.stores.state_store.set_state(ACTOR, "occupation_id", "watch_hand")
	s.stores.state_store.set_state(ACTOR, "livelihood_status", "employed")
	s.stores.state_store.set_state(ACTOR, "location_id", str(actor.states.home_location_id))
	s.stores.state_store.set_state(ACTOR, "workplace_id", "generated_location.echo_terrace.watch_post")
	snapshot = Snapshot.new().build_snapshot(s.context, s.stores, true)
	snapshot.items = snapshot.items.filter(func(item: Dictionary) -> bool: return item.get("holder", {}).get("id") != ACTOR)
	var config: Dictionary = fixture.resident_daily_life.duplicate(true)
	var at_night := {"day": 3, "hour": 22, "elapsed_hours": 1, "tick_event_id": "test_injection.night_choice"}
	var plan := DailyLife.new().resolve_tick(snapshot, at_night, config, s.world_tick_adapter.settlement_network_config,
		s.context.locations, s.world_tick_adapter.daily_life_routes, s.npc_livelihood_profiles)
	_check(plan.events.any(func(row: Dictionary) -> bool: return row.actor_id == ACTOR and row.activity == "resting" and row.get("intent_id") == "subsistence"), "poor night worker can forgo the shift to prepare real daytime subsistence")
	config.food_access.subsistence = previous
	plan = DailyLife.new().resolve_tick(snapshot, at_night, config, s.world_tick_adapter.settlement_network_config,
		s.context.locations, s.world_tick_adapter.daily_life_routes, s.npc_livelihood_profiles)
	_check(not plan.events.any(func(row: Dictionary) -> bool: return row.actor_id == ACTOR and row.activity == "resting"), "old bootstrap still chooses its old night shift")


func _session(mode: String = "") -> Variant:
	var source := fixture.duplicate(true)
	for actor: Dictionary in source.entities:
		if actor.id != ACTOR:
			continue
		match mode:
			"absent": actor.states.location_id = actor.states.home_location_id
			"traveling": actor.states.daily_route_id = "test_injection.route"
			"exhausted": actor.states.fatigue = 10
			"injured": actor.states.health = 10
			"child": actor.states.age_years = 12
	var s := Session.new()
	_check(s.start_from_fixture_data(source, []).success, "controlled subsistence fixture " + mode)
	if mode == "permission_denied":
		s.stores.resource_stock_store.stocks[STOCK].access.resident_production = false
	if mode == "depleted":
		s.stores.resource_stock_store.stocks[STOCK].current = 0.0
	var arrival := Result.new()
	arrival.add_fact({"fact_id": "test_injection.subsistence.arrival", "fact_type": "test_injection", "actor_id": ACTOR, "location_id": FARM})
	arrival.add_state_change({"entity_id": ACTOR, "key": "daily_presence_fact_id", "to": "test_injection.subsistence.arrival"})
	_check(s.writer.apply_result(arrival, s.stores), "controlled arrival evidence")
	return s


func _work(s: Variant, hour: int, day: int = 2) -> void:
	var tick := {"day": day, "hour": hour, "elapsed_hours": 1, "tick_event_id": "test_injection.subsistence.%d.%d" % [day, hour]}
	var plan := Work.new().resolve_work_tick(Snapshot.new().build_snapshot(s.context, s.stores, true), s.npc_livelihood_profiles, tick, fixture.resident_daily_life)
	_check(s.writer.apply_results(plan.results, s.stores), "work transaction " + str(hour))


func _currency(s: Variant) -> int:
	var total := 0
	for item: Dictionary in s.stores.item_store.list_items():
		if item.item_def_id == Food.CURRENCY:
			total += int(item.quantity)
	return total


func _native(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)
