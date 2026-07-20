extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")

const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SCENARIO_PATH := (
	"res://data/sim/fixtures/scenarios/lake_town_food_crisis_sequence.json"
)
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const OUTBOUND_ROUTE := "old_chen_shop_to_abandoned_granary"
const RETURN_ROUTE := "abandoned_granary_to_old_chen_shop"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var session = SimSessionModel.new()
	var start_result: Dictionary = session.start_from_fixture_path(
		FIXTURE_PATH,
		RULE_PATHS
	)
	_check(
		bool(start_result.get("success", false))
		and session.context.get_locations().size() == 3
		and session.get_travel_options().size() == 1,
		"1. Session loads three locations but exposes only discovered routes"
	)

	var initial_snapshot: Variant = session.get_snapshot()
	_check(
		not initial_snapshot.get_entity("chen_mi").is_empty()
		and initial_snapshot.get_entity(
			"abandoned_granary_broken_door"
		).is_empty(),
		"2. Snapshot projects only entities at the current location"
	)
	_check(
		str(session.get_travel_options()[0].get("route_id", ""))
			== OUTBOUND_ROUTE
		and bool(session.get_travel_options()[0].get("can_travel", false)),
		"3. Outbound route is generated from current world state"
	)

	var outbound: Dictionary = session.travel(OUTBOUND_ROUTE)
	_check(
		bool(outbound.get("success", false))
		and str(session.context.location_id) == "abandoned_granary"
		and int(session.get_time_summary().get("hour", -1)) == 14
		and int(session.get_snapshot().get_player_value("food_count", -1)) == 1,
		"4. Travel consumes four hours and one food before switching location"
	)
	_check(
		int(outbound.get("tick_result", {}).get("triggered_count", 0)) == 1
		and session.stores["fact_store"].find_facts_by_type(
			"old_chen_shop_closed_early"
		).size() == 1,
		"5. Travel triggers due source-location world changes"
	)
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"actor_traveled_route"
		).size() == 1
		and session.get_world_log_entries().size() == 2,
		"6. Journey becomes a fact and a durable world-log entry"
	)

	var granary_snapshot: Variant = session.get_snapshot()
	_check(
		not granary_snapshot.get_entity(
			"abandoned_granary_broken_door"
		).is_empty()
		and not granary_snapshot.get_entity(
			"abandoned_granary_mold_trace"
		).is_empty()
		and granary_snapshot.get_entity("chen_mi").is_empty(),
		"7. Arrival projects granary entities and hides shop entities"
	)
	_check(
		_has_action(
			session.get_action_options(),
			"inspect_visible_trace:abandoned_granary_mold_trace"
		)
		and not _has_action(
			session.get_action_options(),
			"give_food_to_hungry_person:chen_mi"
		),
		"8. Arrival regenerates affordances from granary state"
	)
	_check(
		session.get_travel_options().size() == 1
		and str(session.get_travel_options()[0].get("route_id", ""))
			== RETURN_ROUTE,
		"9. Only the return route is available at the granary"
	)

	var inspect_result: Dictionary = session.execute_action(
		"inspect_visible_trace:abandoned_granary_mold_trace"
	)
	_check(
		bool(inspect_result.get("success", false))
		and session.stores["fact_store"].find_facts_by_type(
			"actor_inspected_trace"
		).size() == 1,
		"10. Granary supports the same data-driven investigation rules"
	)

	var returned: Dictionary = session.travel(RETURN_ROUTE)
	var returned_snapshot: Variant = session.get_snapshot()
	_check(
		bool(returned.get("success", false))
		and str(session.context.location_id) == "old_chen_shop"
		and int(session.get_time_summary().get("hour", -1)) == 18
		and int(returned_snapshot.get_player_value("food_count", -1)) == 0,
		"11. Return travel consumes the remaining food and restores shop view"
	)
	_check(
		bool(returned_snapshot.get_entity_state(
			"old_chen_shop_closing_shutters",
			"visible",
			false
		))
		and str(returned_snapshot.get_entity_state(
			"old_chen_shop_price_notice",
			"price_level",
			""
		)) == "raised_again"
		and returned_snapshot.get_entity(
			"abandoned_granary_broken_door"
		).is_empty(),
		"12. Returning preserves prior shop changes without leaking granary entities"
	)

	var blocked_option: Dictionary = session.get_travel_options()[0]
	var time_before_block := session.get_time_summary()
	var log_count_before_block := session.get_world_log_entries().size()
	var blocked_result: Dictionary = session.travel(OUTBOUND_ROUTE)
	_check(
		not bool(blocked_option.get("can_travel", true))
		and str(blocked_option.get("blocked_reason", "")) == "insufficient_food"
		and str(blocked_result.get("error", "")) == "insufficient_food",
		"13. Routes expose a stable insufficient-food failure"
	)
	_check(
		session.get_time_summary() == time_before_block
		and session.get_world_log_entries().size() == log_count_before_block,
		"14. Failed travel does not partially consume time or write logs"
	)

	var summary: Dictionary = session.build_result_summary()
	_check(
		int(summary.get("journeys_completed", 0)) == 2
		and int(summary.get("steps_executed", 0)) == 1
		and int(summary.get("world_ticks_executed", 0)) == 2,
		"15. Summary separates journeys, actions, and world ticks"
	)

	var runner = SimRunnerModel.new()
	var runner_result: Dictionary = runner.run_sequence(
		FIXTURE_PATH,
		SCENARIO_PATH,
		RULE_PATHS
	)
	_check(
		bool(runner_result.get("success", false))
		and int(runner_result.get("steps_executed", 0)) == 3,
		"16. Existing deterministic runner remains compatible"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_check(
		str(session.context.location_id) == "old_chen_shop"
		and int(session.get_snapshot().get_player_value("food_count", -1)) == 2
		and session.travel_count == 0,
		"17. Restart restores location, resources, and journey count"
	)
	_finish()


func _has_action(options: Array, action_id: String) -> bool:
	for option: Dictionary in options:
		if str(option.get("action_id", "")) == action_id:
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 LIVE TRAVEL SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 LIVE TRAVEL SESSION FAIL] " + failure)
	print("[V5 LIVE TRAVEL SESSION RESULT] FAIL: %s" % JSON.stringify(failures))
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 LIVE TRAVEL SESSION PASS] " + message)
	else:
		failures.append(message)
