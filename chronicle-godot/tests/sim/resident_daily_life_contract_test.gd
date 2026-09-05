extends SceneTree

const Session = preload("res://scripts/sim/core/sim_session.gd")
const Live = preload("res://scripts/rebuild/v5_live_location_view_model.gd")
const Livelihood = preload("res://scripts/sim/npc/npc_livelihood_system.gd")
const DailyLife = preload("res://scripts/sim/npc/resident_daily_life_system.gd")
const Snapshot = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SnapshotData = preload("res://scripts/sim/core/sim_snapshot.gd")
const Saves = preload("res://scripts/sim/save/save_envelope_service.gd")
const FIXTURE := "res://data/sim/fixtures/generated_settlement_network_fixture.json"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var live = Live.new()
	_check(live.start({"scenario": "generated_network", "challenge_seed_override": 81001}).success, "formal world starts")
	var session = live.session
	var worker := _worker(session)
	_check(worker != "", "fixture contains a fisher")
	if worker == "":
		_finish()
		return
	_tick(session, 1)
	_check(_state(session, worker, "daily_activity") == "traveling", "worker departs autonomously")
	_check(_state(session, worker, "location_id") == _state(session, worker, "home_location_id"), "departure does not teleport")
	_check(int(_state(session, worker, "livelihood_elapsed_hours")) == 0, "commute is not work")
	_check(not bool(_state(session, worker, "visible")), "in-transit person is not present at origin")
	var save_path := "user://tests/resident_daily_life/mid_journey.json"
	_check(session.save_to_path(save_path).ok, "native mid-journey save")
	var restored = Session.new()
	_check(restored.load_from_path(save_path).success, "mid-journey load")
	_check(DailyLife.enabled(restored.world_tick_adapter.daily_life_config), "save retains explicit new rules")
	for bad_state: Dictionary in [{"daily_destination_id": "missing_location"}, {"daily_travel_remaining": 0},
			{"daily_departure_fact_id": "missing_fact"}, {"daily_route_id": "unknown_route"}]:
		var broken: Dictionary = session.build_save_envelope()
		broken.stores.states[worker].merge(bad_state, true)
		broken = Saves.new().finalize_envelope(broken)
		_check(not Session.new().load_from_save_envelope(broken).get("success", false), "invalid journey save rejected: " + str(bad_state.keys()[0]))
	_tick(session, 1)
	_tick(restored, 1)
	_check(_hash(session) == _hash(restored), "disk continuation preserves travel clock and world exactly at native precision")
	_check(_state(session, worker, "daily_activity") == "arrived", "one hour completes home path")
	_check(int(_state(session, worker, "livelihood_elapsed_hours")) == 0, "arrival hour does not count as work")
	var people: Array = live.build_view_data().visible_people
	_check(people.any(func(row: Dictionary) -> bool: return row.id == worker and "抵达" in row.state_text), "actual person visible in formal local projection")
	_tick(session, 1)
	_check(_state(session, worker, "daily_activity") == "traveling", "continues along second edge")
	_tick(session, 1)
	_check(_state(session, worker, "location_id") == _state(session, worker, "workplace_id"), "arrives at actual workplace")
	_check(int(_state(session, worker, "livelihood_elapsed_hours")) == 0, "second arrival still is not work")
	_tick(session, 1)
	_check(int(_state(session, worker, "livelihood_elapsed_hours")) == 1, "only time spent at workplace advances production")
	_tick(session, 15)
	_check(_state(session, worker, "location_id") == _state(session, worker, "home_location_id"), "worker returns home at night")
	_check(_state(session, worker, "daily_activity") == "resting", "night is rest not remote production")
	_check(int(_state(session, worker, "fatigue")) == 0, "time at home restores fatigue")
	var night_watch := false
	for actor: Dictionary in Snapshot.new().build_snapshot(session.context, session.stores, true).get_entities_by_type("person"):
		if actor.states.get("occupation_id") == "watch_hand":
			night_watch = night_watch or actor.states.get("daily_activity") == "working"
	_check(night_watch, "night watch works while daytime workers sleep")
	_tick(session, 28)
	var produced: Array = session.stores.fact_store.find_facts_by_type("npc_livelihood_produced")
	_check(not produced.is_empty(), "two days produce real goods despite travel costs")
	var sources_ok := true
	for fact: Dictionary in produced:
		var source: Dictionary = session.stores.fact_store.get_fact(str(fact.get("source_fact_ids", [""])[0]))
		sources_ok = sources_ok and fact.get("location_id") == fact.get("actual_location_id") \
			and source.get("activity") == "arrived" and source.get("location_id") == fact.get("location_id")
	_check(sources_ok, "every production has actual location and arrival fact")
	_check(session.validate_persistent_references().ok, "all persisted references valid")
	_check(session.action_count == 0 and session.travel_count == 0, "no player action or commanded NPC travel")
	_check(session.stores.state_store.validation_errors.is_empty(), "new state definitions accept all writes")
	var replay = Live.new()
	_check(replay.start({"scenario": "generated_network", "challenge_seed_override": 81001}).success, "same seed replay starts")
	for hours: int in [1, 1, 1, 1, 1, 15, 28]:
		_tick(replay.session, hours)
	_check(_hash(session) == _hash(replay.session), "same input timing gives same complete world")
	_test_counterexamples(replay.session.fixture_source_data, worker)
	_test_food_presence()
	_test_legacy()
	_finish()


func _test_counterexamples(source: Dictionary, worker: String) -> void:
	var fixture := source.duplicate(true)
	for entity: Dictionary in fixture.entities:
		if entity.id == worker:
			entity.states.health = 10
			entity.states.fatigue = 9
	var ill = Session.new()
	_check(ill.start_from_fixture_data(fixture, []).success, "test injection: unwell worker fixture")
	_tick(ill, 12)
	_check(_state(ill, worker, "daily_activity") == "resting" and int(_state(ill, worker, "livelihood_cycle_count")) == 0,
		"ill worker rests without goods or wages")
	fixture = source.duplicate(true)
	var workplace := ""
	for entity: Dictionary in fixture.entities:
		if entity.id == worker:
			workplace = str(entity.states.workplace_id)
	for route: Dictionary in fixture.travel_routes:
		if str(route.to_location_id) == workplace:
			route["enabled"] = false
	var blocked = Session.new()
	_check(blocked.start_from_fixture_data(fixture, []).success, "test injection: disconnected workplace")
	_tick(blocked, 8)
	_check(_state(blocked, worker, "daily_activity") == "blocked", "unreachable work is not replaced by a teleport")
	_check(int(_state(blocked, worker, "livelihood_cycle_count")) == 0, "no production behind blocked path")
	var blocked_route := ""
	for option: Dictionary in blocked.get_travel_options():
		if str(option.to_location_id) == workplace:
			blocked_route = str(option.route_id)
			_check(not option.can_travel and option.blocked_reason == "route_closed", "same closed public route is disabled for traveler")
	_check(blocked_route != "" and not blocked.travel(blocked_route).success, "direct travel cannot bypass closure")
	var direct = Livelihood.new().resolve_work_tick(Snapshot.new().build_snapshot(blocked.context, blocked.stores, true), blocked.npc_livelihood_profiles,
		{"elapsed_hours": 1, "day": 1, "hour": 17, "tick_event_id": "test_injection.direct_work"}, DailyLife.PROFILE)
	var wrong_actor := false
	for result: Variant in direct.results:
		for change: Dictionary in result.state_changes:
			wrong_actor = wrong_actor or str(change.get("entity_id", "")) == worker
	_check(not wrong_actor, "work resolver independently rejects off-site actor")
	var moving = Session.new()
	_check(moving.start_from_fixture_data(source, []).success, "route interruption fixture starts")
	_tick(moving, 1)
	moving.world_tick_adapter.daily_life_routes.clear()
	# The first private path still exists. Remove the public onward connection.
	_tick(moving, 2)
	_check(_state(moving, worker, "daily_activity") == "blocked", "missing onward connection halts journey")
	var states = moving.stores.state_store
	var original_work := str(_state(moving, worker, "workplace_id"))
	states.set_state(worker, "livelihood_elapsed_hours", 7)
	states.set_state(worker, "workplace_id", str(_state(moving, worker, "home_location_id")))
	_tick(moving, 1)
	_check(int(_state(moving, worker, "livelihood_elapsed_hours")) == 0 and _state(moving, worker, "daily_workplace_id") != original_work,
		"test injection: job change does not carry partial production to new workplace")
	fixture = source.duplicate(true)
	for route: Dictionary in fixture.travel_routes:
		if str(route.to_location_id) == workplace:
			route.hours = 3
	var interrupted = Session.new()
	_check(interrupted.start_from_fixture_data(fixture, []).success, "long local journey fixture")
	_tick(interrupted, 3)
	var active_route := str(_state(interrupted, worker, "daily_route_id"))
	for route: Dictionary in interrupted.world_tick_adapter.daily_life_routes:
		if str(route.route_id) == active_route:
			route.enabled = false
	_tick(interrupted, 2)
	_check(int(_state(interrupted, worker, "daily_travel_remaining")) == 3 and not bool(_state(interrupted, worker, "visible")),
		"test injection: blocked traveler stays in transit; neither arrival nor free return")
	for route: Dictionary in interrupted.world_tick_adapter.daily_life_routes:
		if str(route.route_id) == active_route:
			route.enabled = true
	_tick(interrupted, 2)
	_check(int(_state(interrupted, worker, "daily_travel_remaining")) == 1, "reopened route resumes remaining travel cost")
	_tick(interrupted, 1)
	_check(_state(interrupted, worker, "location_id") == workplace, "only completed journey reaches work")


func _test_food_presence() -> void:
	var data := {"entities": [
		{"id": "recipient", "type": "person", "states": {"household_id": "family", "daily_life_version": 1, "hunger": "high", "location_id": "home"}},
		{"id": "donor", "type": "person", "states": {"household_id": "family", "daily_life_version": 1, "hunger": "low", "location_id": "work"}}],
		"items": [{"item_instance_id": "test_food", "item_def_id": "item.fresh_fish_portion", "quantity": 2,
			"holder": {"kind": "entity", "id": "donor"}, "tags": ["food"], "capabilities": ["consume"]}]}
	var tick := {"elapsed_hours": 1, "day": 1, "hour": 12, "tick_event_id": "food_presence"}
	var system = Livelihood.new()
	var remote: Dictionary = system.resolve_household_support(SnapshotData.new(data), tick)
	_check(_consumed(remote) == 0, "test injection: household food is not teleported from workplace")
	data.entities[1].states.location_id = "home"
	var local: Dictionary = system.resolve_household_support(SnapshotData.new(data), tick)
	_check(_consumed(local) == 1, "co-located household actually consumes one portion")
	data.entities[1].states.daily_route_id = "in_transit"
	_check(_consumed(system.resolve_household_support(SnapshotData.new(data), tick)) == 0, "traveler's food is unavailable at last-known origin")


func _consumed(plan: Dictionary) -> int:
	var quantity := 0
	for result: Variant in plan.results:
		for change: Dictionary in result.item_changes:
			if change.get("operation") == "consume":
				quantity += int(change.quantity)
	return quantity


func _test_legacy() -> void:
	var old = Session.new()
	_check(old.start_from_fixture_path(FIXTURE, []).success, "legacy fixture remains explicit legacy")
	var restored = Session.new()
	_check(restored.load_from_save_envelope(old.build_save_envelope()).success, "legacy save loads without migration")
	_check(not DailyLife.enabled(restored.world_tick_adapter.daily_life_config), "legacy save is not silently opted into new rules")
	_tick(restored, 12)
	_check(restored.stores.fact_store.find_facts_by_type("resident_activity_changed").is_empty(), "legacy continuation does not invent commuting")
	_check(not restored.stores.fact_store.find_facts_by_type("npc_livelihood_produced").is_empty(), "legacy production contract unchanged")
	_check(not Session.new().start_from_fixture_path(FIXTURE, [], {"resident_daily_life_version": 99}).success,
		"unsupported rule version rejected")
	var zip = ZIPReader.new()
	var opened := zip.open("res://texts/reports/2026/2026-9/2026-9-05/h1_response_evidence/checkpoint_day7.zip")
	_check(opened == OK, "actual committed pre-activity checkpoint available")
	if opened == OK:
		var data: Dictionary = JSON.parse_string(zip.read_file(zip.get_files()[0]).get_string_from_utf8())
		zip.close()
		var actual_old = Session.new()
		var loaded: Dictionary = actual_old.load_from_save_envelope(data)
		_check(loaded.get("success", false) and "base_v3_to_v4_resident_activity_definitions" in loaded.get("migrations", []),
			"actual v3 manifest upgrades explicitly to v4")
		if loaded.get("success", false):
			_check(_native(data.stores) == _native(actual_old.get_save_store_data()), "actual old world's complete Stores are untouched")
			_check(not DailyLife.enabled(actual_old.world_tick_adapter.daily_life_config), "actual old world retains old simulation rules")


func _worker(session: Variant) -> String:
	for entity: Dictionary in Snapshot.new().build_snapshot(session.context, session.stores, true).get_entities_by_type("person"):
		if entity.states.get("occupation_id") == "net_fisher" and entity.states.get("settlement_id") == "generated_settlement.reed_bay":
			return str(entity.id)
	return ""


func _state(session: Variant, id: String, key: String) -> Variant:
	return session.stores.state_store.get_state(id, key)


func _tick(session: Variant, hours: int) -> void:
	_check(session.advance_time(hours, "daily_life_contract", {"scope_type": "global", "scope_id": ""}).success, "advance %d hours" % hours)


func _hash(session: Variant) -> String:
	var value := {"stores": session.get_save_store_data(), "time": session.get_time_summary(),
		"rng": str(session.challenge_rng.state)}
	# Use the existing native SaveEnvelope JSON contract, including int/float normalization.
	return _native(value).sha256_text()


func _native(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value, "", true, false)), "", true, false)


func _check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)


func _finish() -> void:
	print("RESIDENT_DAILY_LIFE_RESULT ", "PASS" if failures.is_empty() else "FAIL", " ", checks - failures.size(), "/", checks)
	quit(0 if failures.is_empty() else 1)
