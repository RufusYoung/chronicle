extends "res://tests/sim/interest_pursuit_test.gd"

const Utility = preload("res://scripts/sim/player/journey_utility.gd")
const ROAD := "generated_route.network.echo_shore_road.a_to_b"


func _run() -> void:
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v3"})
	_check(response.ok, "explicit utility world starts: " + str(response.get("error", "")))
	if not response.ok:
		_finish()
		return
	_check(response.observation.journey_utility_version == 1, "public rules version matches bootstrap")
	_check(response.observation.goal_pressure.candidates.any(func(c: Dictionary) -> bool: return c.id == "prepare_main_hand"), "own empty hand offers a purpose without depleting starting equipment")
	response = _call(game, "set_goal", {"goal_id": "prepare_main_hand"})
	_check(response.observation.goal_pressure.breakpoint == "NO_LOCAL_OFFER", "empty market is disclosed, not replaced by an imaginary seller")
	_check(response.observation.goal_pressure.interests.all(func(i: Dictionary) -> bool: return not i.promoted), "preparing own equipment does not promote unrelated NPC troubles")
	var base: Dictionary = game.model.session.fixture_source_data.duplicate(true)
	var host: Dictionary = base.entities.filter(func(e: Dictionary) -> bool: return e.has("guesthouse_rules") and e.states.get("settlement_id") == "generated_settlement.echo_landing")[0]
	var own_before := _signature(game.model.session)
	_call(game, "observe")
	_check(_signature(game.model.session) == own_before, "utility observation never writes world truth")
	_check(response.choices.any(func(c: Dictionary) -> bool: return c.id == "rush:" + ROAD), "public control exposes actual alternative pace")
	_check(Presentation.build(response, "map").choices.any(func(c: Dictionary) -> bool: return c.id == "rush:" + ROAD), "map exposes hurry without a hidden API advantage")
	response = _call(game, "set_goal", {"goal_id": "visit:generated_location.echo_terrace.commons"})
	_check(response.observation.goal_pressure.alternatives.any(func(a: Dictionary) -> bool: return a.id == "rush:" + ROAD), "selected route compares fatigue and time")
	_check(_call(game, "save", {"slot": "utility_departure", "overwrite": true}).ok, "native predeparture checkpoint")
	var walking := _act_offered(game, response, ROAD)
	_check(walking.ok and walking.observation.time.hour == 13, "ordinary road still takes three hours")
	response = _call(game, "load", {"slot": "utility_departure"})
	_check(response.ok, "predeparture restore: " + str(response.get("error", "")))
	if not response.ok:
		_finish()
		return
	var rushed := _act_offered(game, response, "rush:" + ROAD)
	_check(rushed.ok and rushed.observation.time.hour == 12, "same-state rush takes two hours with actual world ticks")
	_check(int(rushed.observation.player.fatigue) == int(walking.observation.player.fatigue) + 2, "hurrying pays two extra real fatigue, not prose")
	_check(rushed.observation.location == walking.observation.location, "same destination, not a synthetic shortcut")
	_check(rushed.observation.feedback.body.contains("额外增加2疲劳"), "actual price remains in outcome")
	_check(game.model.session.stores.fact_store.list_facts().any(func(f: Dictionary) -> bool: return f.get("pace") == "rush" and f.get("extra_fatigue") == 2), "native departure retains real pace cost")
	_check(_call(game, "save", {"slot": "utility_arrival", "overwrite": true}).ok, "new-world native save")
	var restored := _call(game, "load", {"slot": "utility_arrival"})
	_check(restored.ok and restored.observation == rushed.observation, "native restore keeps utility rules and public result")
	for hours: int in [1, 2, 4]:
		_bed_case(base, host, hours)
	_hand_case(base, host)
	_rejections(base, host)
	var old := NewAgent.new()
	var old_response := _call(old, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81001, "economy_variant": "world_situation_v2"})
	_check(old_response.ok and old_response.choices.all(func(c: Dictionary) -> bool: return not str(c.id).begins_with("rush:")), "old profile does not silently get a new pace")
	var old_base: Dictionary = old.model.session.fixture_source_data.duplicate(true)
	var legacy: Variant = _session(_fixture(old_base, host, 9, 18))
	var old_beds: Array = LocalServices.options(legacy).filter(func(row: Dictionary) -> bool: return row.action_id == "service:bed")
	_check(old_beds.size() == 1 and old_beds[0].hours == 4, "old profile retains fixed four-hour contract")
	_check(legacy.save_to_path("user://tests/utility/legacy.json").ok, "legacy save")
	var loaded := Session.new()
	_check(loaded.load_from_path("user://tests/utility/legacy.json").success and not Utility.enabled(loaded.fixture_source_data), "old save stays old, regardless of executable default")
	var invalid: Dictionary = base.duplicate(true)
	invalid.journey_utility_rules.bed_hourly_price = 0
	_check(Utility.validate(invalid) == "journey_utility_bootstrap_mismatch", "unknown rule mutation rejected instead of silently repriced")
	_finish()


func _hand_case(base: Dictionary, host: Dictionary) -> void:
	var fixture := _fixture(base, host, 9, 18)
	fixture.initial_items.append({"item_instance_id": "test.utility.whip", "item_def_id": "item.knotted_fiber_whip",
		"quantity": 1, "holder": {"kind": "entity", "id": host.id}})
	var session: Variant = _session(fixture)
	var view := View.new()
	view.session = session
	_check(view.set_current_goal("prepare_main_hand").success, "player may select an actual empty equipment-slot use")
	var data := view.build_view_data()
	_check(data.actions.any(func(row: Dictionary) -> bool: return row.action_id == "buy:test.utility.whip" and row.get("goal_priority") == 3), "test injection: real seller stock promoted for chosen use")
	_check(session.PlayerLife.execute(session, "buy:test.utility.whip").success, "actual purchase for selected use")
	_check(view.build_view_data().goal_pressure.goal_status == "active", "buying alone does not complete equipment use")
	_check(session.PlayerLife.execute(session, "equip:test.utility.whip:main_hand").success, "actual equipping")
	_check(view.build_view_data().goal_pressure.goal_status == "satisfied", "only formal effective equipment satisfies use")
	_check(session.PlayerLife.Utility.enabled(session.fixture_source_data), "item use does not change world profile")


func _bed_case(base: Dictionary, host: Dictionary, hours: int) -> void:
	var fixture := _fixture(base, host, 9, 18)
	fixture.player.fatigue = 10
	fixture.player.hunger = "none"
	var session: Variant = _session(fixture)
	var view := View.new()
	view.session = session
	_check(view.set_current_goal("recover_energy").success, "test injection: actual tired body admits voluntary recovery purpose")
	var projected := view.build_view_data()
	_check(projected.goal_pressure.alternatives.any(func(row: Dictionary) -> bool: return row.id == "rest"), "free recovery remains a real alternative")
	var before := Treasury.new(_snapshot(session)).balance("player")
	var result: Dictionary = session.PlayerLife.execute(session, "service:bed:%d" % hours)
	_check(result.success and result.hours == hours, "hourly bed completes selected %d-hour use" % hours)
	_check(int(session.get_snapshot().player.fatigue) == 10 - 2 * hours, "bed fatigue consumer: %d hours" % hours)
	_check(Treasury.new(_snapshot(session)).balance("player") == before - hours, "bed pays actual coins: %d hours" % hours)
	var payments: Array = session.stores.fact_store.list_facts().filter(func(f: Dictionary) -> bool: return f.get("fact_type") == "guesthouse_paid")
	_check(payments.size() == hours and payments.all(func(f: Dictionary) -> bool: return f.target_id == host.id and f.amount == 1), "every occupied hour has a real recipient, no synthetic money")
	var free: Variant = _session(fixture.duplicate(true))
	for index: int in range(hours):
		_check(free.PlayerLife.execute(free, "rest").success, "free rest is not weakened")
	_check(int(free.get_snapshot().player.fatigue) == 10 - hours, "same elapsed time yields different reserves")
	_check(Treasury.new(_snapshot(free)).balance("player") == before, "free rest retains cash")
	var road: Dictionary = session.travel_routes.filter(func(r: Dictionary) -> bool: return r.route_id == ROAD)[0]
	if hours == 2:
		_check(Utility.rush_denial(session, road) == "" and Utility.rush_denial(free, road) != "", "same start and elapsed time: two-hour bed restores rush reserve, free rest does not")
	if hours == 4:
		_check(view.build_view_data().goal_pressure.goal_status == "satisfied", "recovery purpose ends without imposing another chore")
	_check(session.save_to_path("user://tests/utility/bed%d.json" % hours).ok, "bed state saves")
	var loaded := Session.new()
	_check(loaded.load_from_path("user://tests/utility/bed%d.json" % hours).success, "bed state loads")
	_check(_signature(session) == _signature(loaded), "bed truth persists")


func _rejections(base: Dictionary, host: Dictionary) -> void:
	for case: String in ["absent", "daytime", "closing", "poor", "hungry"]:
		var fixture := _fixture(base, host, 1 if case == "poor" else 9, 8 if case == "closing" else (12 if case == "daytime" else 18))
		fixture.player.fatigue = 8
		if case == "absent":
			_entity(fixture, str(host.id)).states.location_id = HUB
		if case == "hungry":
			fixture.player.hunger = "high"
		var session: Variant = _session(fixture)
		var before := _signature(session)
		var result: Dictionary = session.PlayerLife.execute(session, "service:bed:4")
		if case == "hungry":
			_check(result.success and result.hours == 1, "hunger interrupts a long booking")
			_check(Treasury.new(_snapshot(session)).balance("player") == 8, "unused hours are never charged")
		else:
			_check(not result.success and before == _signature(session), "%s cannot consume money or time" % case)
		if case == "closing":
			_check(session.PlayerLife.execute(session, "service:bed:1").success, "shorter actual slot remains usable before close")
	var game := NewAgent.new()
	var response := _call(game, "start", {"mode": "play", "scenario": "echo_realm", "seed": 81002, "economy_variant": "world_situation_v3"})
	var session: Variant = game.model.session
	var injection := Result.new()
	injection.add_state_change({"entity_id": "player", "key": "fatigue", "to": 8})
	injection.mark_resolved("test_injection")
	_check(session.writer.apply_result(injection, session.stores), "test injection: tired traveler")
	var before := _signature(session)
	_check(not session.travel(ROAD, {"pace": "rush"}).success and before == _signature(session), "direct entry cannot bypass fatigue cost or silently clamp it")
	_check(session.get_travel_options().any(func(r: Dictionary) -> bool: return r.route_id == ROAD and r.can_travel), "tired traveler still has ordinary road")
	_check(not Utility.walkable(base, {"hours": 1}) and not Utility.walkable(base, {"hours": 4, "network_link_id": "unknown"}), "no imaginary short-road or ferry acceleration")
