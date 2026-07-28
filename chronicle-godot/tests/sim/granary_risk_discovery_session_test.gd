extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const OUTBOUND_ROUTE := "old_chen_shop_to_abandoned_granary"
const RETURN_ROUTE := "abandoned_granary_to_old_chen_shop"
const PREPARE_OPTION := "prepare_granary_entry"
const ENTER_OPTION := "enter_abandoned_granary"
const DISCOVERY_ITEM := "lake_town_granary_measure_token"

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
		and int(start_result.get("challenge_definition_count", 0)) == 4
		and session.get_challenge_options().is_empty(),
		"1. Challenge definitions load but stay hidden outside their locations"
	)

	session.travel(OUTBOUND_ROUTE)
	var initial_options := session.get_challenge_options()
	_check(
		initial_options.size() == 2
		and _has_option(initial_options, PREPARE_OPTION)
		and _has_option(initial_options, ENTER_OPTION),
		"2. Arrival exposes preparation and direct-entry choices"
	)
	var enter_option := _option(initial_options, ENTER_OPTION)
	_check(
		str(enter_option.get("risk_label", "")) == "高"
		and "d20 + 感知 10 / 难度 21" in str(
			enter_option.get("check_text", "")
		)
		and "不会死亡" in str(enter_option.get("failure_hint", "")),
		"3. Challenge option exposes risk, formula, and non-death consequence"
	)

	var failed_attempt: Dictionary = session.execute_challenge_option(
		ENTER_OPTION,
		{"source": "test_injection", "roll_override": 3}
	)
	var failure_snapshot: Variant = session.get_snapshot()
	var failed_check: Dictionary = (
		failed_attempt.get("transaction_result", {}) as Dictionary
	).get("narrative_result", {})
	_check(
		bool(failed_attempt.get("success", false))
		and str(failed_attempt.get("outcome", "")) == "failure"
		and int(failed_check.get("roll", 0)) == 3
		and int(failed_check.get("total", 0)) == 13
		and int(failed_check.get("difficulty", 0)) == 21,
		"4. Unprepared low roll resolves through the real check formula"
	)
	_check(
		int(failure_snapshot.get_player_value("health", 0)) == 88
		and str(failure_snapshot.get_player_value("injury", ""))
			== "twisted_ankle"
		and int(failure_snapshot.get_player_value("health", 0)) > 0,
		"5. Failure causes a persistent non-lethal injury"
	)
	_check(
		session.stores["item_store"].list_items().is_empty()
		and failure_snapshot.get_player_items().is_empty()
		and str(failure_snapshot.get_entity_state(
			"abandoned_granary_broken_door",
			"challenge_status",
			""
		)) == "failure",
		"6. Failure grants no discovery and closes the resolved challenge"
	)
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"actor_attempted_challenge"
		).size() == 1
		and session.stores["fact_store"].find_facts_by_type(
			"actor_injured_during_challenge"
		).size() == 1
		and session.get_challenge_options().is_empty(),
		"7. Failure becomes facts and cannot be retried in the same world"
	)

	var time_before_stale := session.get_time_summary()
	var log_before_stale := session.get_world_log_entries().size()
	var stale_result: Dictionary = session.execute_challenge_option(ENTER_OPTION)
	_check(
		not bool(stale_result.get("success", true))
		and str(stale_result.get("error", ""))
			== "challenge_option_not_found"
		and session.get_time_summary() == time_before_stale
		and session.get_world_log_entries().size() == log_before_stale,
		"8. Stale challenge choice cannot consume time or duplicate consequences"
	)

	session.travel(RETURN_ROUTE)
	_check(
		str(session.context.location_id) == "old_chen_shop"
		and int(session.get_snapshot().get_player_value("health", 0)) == 88
		and str(session.get_snapshot().get_player_value("injury", ""))
			== "twisted_ankle",
		"9. Injury persists after retreating to the shop"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	session.travel(OUTBOUND_ROUTE)
	var preparation: Dictionary = session.execute_challenge_option(
		PREPARE_OPTION
	)
	var prepared_snapshot: Variant = session.get_snapshot()
	_check(
		bool(preparation.get("success", false))
		and str(preparation.get("outcome", "")) == "prepared"
		and bool(prepared_snapshot.get_entity_state(
			"abandoned_granary_broken_door",
			"entry_prepared",
			false
		))
		and int(session.get_time_summary().get("hour", 0)) == 15,
		"10. Preparation consumes one hour and persists on the challenge target"
	)
	var prepared_options := session.get_challenge_options()
	_check(
		prepared_options.size() == 1
		and not _has_option(prepared_options, PREPARE_OPTION)
		and "准备 10" in str(
			_option(prepared_options, ENTER_OPTION).get("check_text", "")
		),
		"11. Preparation disappears after use and changes the displayed formula"
	)

	var time_before_invalid := session.get_time_summary()
	var unauthorized_roll: Dictionary = session.execute_challenge_option(
		ENTER_OPTION,
		{"roll_override": 3}
	)
	var invalid_roll: Dictionary = session.execute_challenge_option(
		ENTER_OPTION,
		{"source": "test_injection", "roll_override": 0}
	)
	_check(
		not bool(unauthorized_roll.get("success", true))
		and str(unauthorized_roll.get("error", ""))
			== "roll_override_requires_test_injection"
		and not bool(invalid_roll.get("success", true))
		and str(invalid_roll.get("error", "")) == "invalid_roll_override"
		and session.get_time_summary() == time_before_invalid
		and _has_option(session.get_challenge_options(), ENTER_OPTION),
		"12. Unmarked or invalid test injection cannot change the challenge"
	)

	var success_attempt: Dictionary = session.execute_challenge_option(
		ENTER_OPTION,
		{"source": "test_injection", "roll_override": 3}
	)
	var success_snapshot: Variant = session.get_snapshot()
	var success_check: Dictionary = (
		success_attempt.get("transaction_result", {}) as Dictionary
	).get("narrative_result", {})
	_check(
		bool(success_attempt.get("success", false))
		and str(success_attempt.get("outcome", "")) == "success"
		and int(success_check.get("roll", 0)) == 3
		and int(success_check.get("stat_value", 0)) == 10
		and int(success_check.get("preparation_bonus", 0)) == 10
		and int(success_check.get("total", 0)) == 23,
		"13. The same low roll succeeds after preparation bonus"
	)
	_check(
		int(success_snapshot.get_player_value("health", 0)) == 100
		and str(success_snapshot.get_player_value("injury", ""))
			== "none"
		and bool(success_snapshot.get_entity_state(
			"abandoned_granary_hidden_niche",
			"visible",
			false
		)),
		"14. Success reveals the discovery site without fabricating an injury"
	)

	var item: Dictionary = session.stores["item_store"].get_item(
		DISCOVERY_ITEM
	)
	var provenance: Dictionary = item.get("provenance", {})
	var inventory_ids: Array = success_snapshot.get_player_value(
		"inventory_item_ids",
		[]
	)
	_check(
		str(item.get("display_name", "")) == "旧粮仓验粮铜牌"
		and str(item.get("owner_id", "")) == "player"
		and DISCOVERY_ITEM in inventory_ids
		and success_snapshot.get_player_items().size() == 1,
		"15. Success creates a real owned item and updates player inventory"
	)
	_check(
		str(provenance.get("created_for", ""))
			== "lake_town_public_granary"
		and str(provenance.get("discovered_at", ""))
			== "abandoned_granary"
		and str(provenance.get("source_challenge_id", ""))
			== "granary_rotten_floor_entry"
		and int(provenance.get("discovered_day", 0)) == 1
		and int(provenance.get("discovered_hour", 0)) == 16,
		"16. Item provenance records origin, discovery place, cause, and time"
	)
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"actor_discovered_item"
		).size() == 1
		and int(session.get_world_log_summary().get(
			"item_change_count",
			0
		)) == 1,
		"17. Discovery enters both facts and persistent WorldLog"
	)

	session.travel(RETURN_ROUTE)
	var returned_snapshot: Variant = session.get_snapshot()
	_check(
		str(session.context.location_id) == "old_chen_shop"
		and returned_snapshot.get_player_items().size() == 1
		and DISCOVERY_ITEM in (
			returned_snapshot.get_player_value(
				"inventory_item_ids",
				[]
			) as Array
		),
		"18. Discovery remains owned after returning to the shop"
	)
	var summary: Dictionary = session.build_result_summary()
	_check(
		int(summary.get("challenges_resolved", 0)) == 1
		and int(summary.get("challenge_preparations", 0)) == 1
		and int(summary.get("world_ticks_executed", 0)) == 4
		and int(summary.get("store_summary", {}).get("items", 0)) == 1,
		"19. Summary separates preparation, check, world ticks, and items"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_check(
		int(session.get_snapshot().get_player_value("health", 0)) == 100
		and str(session.get_snapshot().get_player_value("injury", ""))
			== "none"
		and session.stores["item_store"].list_items().is_empty()
		and session.challenge_count == 0
		and session.challenge_preparation_count == 0,
		"20. Restart resets injury, discovery, and challenge counters"
	)
	_finish()


func _has_option(options: Array, option_id: String) -> bool:
	return not _option(options, option_id).is_empty()


func _option(options: Array, option_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 GRANARY RISK DISCOVERY SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 GRANARY RISK DISCOVERY SESSION FAIL] " + failure)
	print(
		"[V5 GRANARY RISK DISCOVERY SESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 GRANARY RISK DISCOVERY SESSION PASS] " + message)
	else:
		failures.append(message)
