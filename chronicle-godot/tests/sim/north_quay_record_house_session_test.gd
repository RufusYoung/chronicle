extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const ChallengeResolverModel = preload(
	"res://scripts/sim/challenge/challenge_resolver.gd"
)

const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]
const GRANARY_OUTBOUND := "old_chen_shop_to_abandoned_granary"
const GRANARY_RETURN := "abandoned_granary_to_old_chen_shop"
const GRANARY_PREPARE := "prepare_granary_entry"
const GRANARY_ENTER := "enter_abandoned_granary"
const ECHO_OPTION := "show_granary_measure_token_to_chen_mi"
const INVESTIGATE_OPTION := "investigate_public_granary_seal_records"
const NORTH_QUAY_OUTBOUND := "old_chen_shop_to_north_quay_record_house"
const NORTH_QUAY_RETURN := "north_quay_record_house_to_old_chen_shop"
const ARCHIVE_PREPARE := "prepare_flooded_archive_search"
const ARCHIVE_SEARCH := "search_flooded_archive_stack"
const ARCHIVE_ITEM := "lu_huai_last_inspection_leaf"

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
		and not _has_route(
			session.get_travel_options(),
			NORTH_QUAY_OUTBOUND
		),
		"1. North quay exists in the world but is hidden before archive evidence"
	)

	var time_before_hidden_route := session.get_time_summary()
	var hidden_route: Dictionary = session.travel(NORTH_QUAY_OUTBOUND)
	_check(
		not bool(hidden_route.get("success", true))
		and str(hidden_route.get("error", "")) == "route_not_discovered"
		and session.get_time_summary() == time_before_hidden_route,
		"2. Direct calls cannot bypass the undiscovered route requirement"
	)

	_complete_granary_investigation(session)
	var night_route := _route(
		session.get_travel_options(),
		NORTH_QUAY_OUTBOUND
	)
	_check(
		not night_route.is_empty()
		and not bool(night_route.get("can_travel", true))
		and str(night_route.get("blocked_reason", ""))
			== "outside_access_window"
		and "06:00" in str(night_route.get("access_hint", "")),
		"3. Archive evidence reveals the ferry route but midnight blocks departure"
	)

	var time_before_night_departure := session.get_time_summary()
	var log_before_night_departure := session.get_world_log_entries().size()
	var night_departure: Dictionary = session.travel(NORTH_QUAY_OUTBOUND)
	_check(
		not bool(night_departure.get("success", true))
		and str(night_departure.get("error", ""))
			== "outside_access_window"
		and session.get_time_summary() == time_before_night_departure
		and session.get_world_log_entries().size()
			== log_before_night_departure,
		"4. Closed ferry attempts consume neither time nor world history"
	)

	session.advance_time(6, "wait_for_north_quay_ferry")
	var morning_route := _route(
		session.get_travel_options(),
		NORTH_QUAY_OUTBOUND
	)
	_check(
		int(session.get_time_summary().get("hour", -1)) == 6
		and bool(morning_route.get("can_travel", false))
		and int(morning_route.get("hours", 0)) == 2
		and int(morning_route.get("food_cost", -1)) == 0,
		"5. Waiting until morning opens the two-hour ferry without fabricating food"
	)

	var outbound: Dictionary = session.travel(NORTH_QUAY_OUTBOUND)
	var archive_snapshot: Variant = session.get_snapshot()
	_check(
		bool(outbound.get("success", false))
		and str(session.context.location_id) == "north_quay_record_house"
		and int(session.get_time_summary().get("hour", -1)) == 8
		and int(archive_snapshot.get_player_value("food_count", -1)) == 0,
		"6. Ferry travel advances time and arrives at the real archive location"
	)
	_check(
		not archive_snapshot.get_entity(
			"north_quay_record_keeper"
		).is_empty()
		and not archive_snapshot.get_entity(
			"north_quay_flooded_stack_door"
		).is_empty()
		and archive_snapshot.get_entity("chen_mi").is_empty(),
		"7. Archive snapshot projects only north quay people and evidence"
	)

	var archive_options := session.get_challenge_options()
	var attempt := _option(archive_options, ARCHIVE_SEARCH)
	_check(
		archive_options.size() == 2
		and _has_option(archive_options, ARCHIVE_PREPARE)
		and _has_option(archive_options, ARCHIVE_SEARCH)
		and str(attempt.get("risk_label", "")) == "中"
		and "d20 + 感知 10 / 难度 19" in str(
			attempt.get("check_text", "")
		),
		"8. Flooded stacks expose preparation, direct risk, and the real formula"
	)

	var failed: Dictionary = session.execute_challenge_option(
		ARCHIVE_SEARCH,
		{"source": "test_injection", "roll_override": 1}
	)
	var failed_snapshot: Variant = session.get_snapshot()
	_check(
		bool(failed.get("success", false))
		and str(failed.get("outcome", "")) == "failure"
		and int(failed_snapshot.get_player_value("health", 0)) == 92
		and str(failed_snapshot.get_player_value("injury", ""))
			== "archive_splinter_cut",
		"9. Direct low roll causes a persistent non-lethal archive injury"
	)
	_check(
		failed_snapshot.get_item(ARCHIVE_ITEM).is_empty()
		and failed_snapshot.get_player_chronicle_entries().size() == 2
		and session.get_challenge_options().is_empty(),
		"10. Failed search finds no record or chronicle and closes the danger"
	)

	session = SimSessionModel.new()
	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_complete_granary_investigation(session)
	session.advance_time(6, "wait_for_north_quay_ferry")
	session.travel(NORTH_QUAY_OUTBOUND)

	var prepared: Dictionary = session.execute_challenge_option(
		ARCHIVE_PREPARE
	)
	var prepared_option := _option(
		session.get_challenge_options(),
		ARCHIVE_SEARCH
	)
	_check(
		bool(prepared.get("success", false))
		and int(session.get_time_summary().get("hour", -1)) == 9
		and "准备 8" in str(prepared_option.get("check_text", ""))
		and not _has_option(
			session.get_challenge_options(),
			ARCHIVE_PREPARE
		),
		"11. Lantern and tide preparation costs an hour and changes the check"
	)

	var searched: Dictionary = session.execute_challenge_option(
		ARCHIVE_SEARCH,
		{"source": "test_injection", "roll_override": 1}
	)
	var resolved_snapshot: Variant = session.get_snapshot()
	var narrative: Dictionary = (
		searched.get("transaction_result", {}) as Dictionary
	).get("narrative_result", {})
	_check(
		bool(searched.get("success", false))
		and str(searched.get("outcome", "")) == "success"
		and int(narrative.get("total", 0)) == 19
		and int(session.get_time_summary().get("hour", -1)) == 10,
		"12. The same low roll succeeds after preparation at a real time cost"
	)

	var record: Dictionary = resolved_snapshot.get_item(ARCHIVE_ITEM)
	var provenance: Dictionary = record.get("provenance", {})
	_check(
		str(record.get("owner_id", "")) == "player"
		and str(provenance.get("author_id", "")) == "lu_huai"
		and str(provenance.get("discovered_at", ""))
			== "north_quay_record_house"
		and str(provenance.get("epistemic_status", ""))
			== "document_claim"
		and bool(resolved_snapshot.get_entity_state(
			"north_quay_open_record_case",
			"visible",
			false
		)),
		"13. Success creates the provenanced record and reveals its discovery site"
	)

	var claim_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type(
		"lu_huai_record_claimed_spoilage_was_not_mold"
	)
	var departure_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type(
		"lu_huai_recorded_departure_for_mist_salt_well"
	)
	_check(
		claim_facts.size() == 1
		and str(
			(claim_facts[0] as Dictionary).get(
				"epistemic_status",
				""
			)
		) == "document_claim"
		and departure_facts.size() == 1
		and str(
			(departure_facts[0] as Dictionary).get("target_id", "")
		) == "mist_salt_well",
		"14. Facts preserve the document claim boundary and Lu Huai's destination"
	)

	var entries: Array = resolved_snapshot.get_player_chronicle_entries()
	var archive_entry := entries[entries.size() - 1] as Dictionary
	var source_types: Array = archive_entry.get("source_fact_types", [])
	_check(
		entries.size() == 3
		and str(archive_entry.get("title", ""))
			== "潮水下没有归档的一页"
		and str(archive_entry.get("branch", "")) == "prepared"
		and "这只是旧文书留下的说法" in str(
			archive_entry.get("body", "")
		)
		and (archive_entry.get("claims", []) as Array).size() == 3,
		"15. Prepared discovery creates a distinct, epistemically careful chronicle"
	)
	_check(
		"actor_traveled_route" in source_types
		and "actor_prepared_for_challenge" in source_types
		and "actor_attempted_challenge" in source_types
		and "actor_discovered_item" in source_types
		and "lu_huai_recorded_departure_for_mist_salt_well"
			in source_types
		and ARCHIVE_ITEM in (
			archive_entry.get("source_item_ids", []) as Array
		),
		"16. Archive chronicle cites journey, preparation, check, item, and record"
	)
	_check(
		session.get_challenge_options().is_empty()
		and _has_route(session.get_travel_options(), NORTH_QUAY_RETURN),
		"17. Resolved search cannot duplicate but leaves a route home"
	)

	var stale_time := session.get_time_summary()
	var stale: Dictionary = session.execute_challenge_option(ARCHIVE_SEARCH)
	_check(
		not bool(stale.get("success", true))
		and str(stale.get("error", "")) == "challenge_option_not_found"
		and session.get_time_summary() == stale_time,
		"18. Stale archive options cannot duplicate time, facts, items, or chronicle"
	)

	var returned: Dictionary = session.travel(NORTH_QUAY_RETURN)
	_check(
		bool(returned.get("success", false))
		and str(session.context.location_id) == "old_chen_shop"
		and int(session.get_time_summary().get("hour", -1)) == 12
		and not session.get_snapshot().get_item(ARCHIVE_ITEM).is_empty(),
		"19. The record returns to ordinary life as a persistent owned object"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_check(
		not _has_route(
			session.get_travel_options(),
			NORTH_QUAY_OUTBOUND
		)
		and session.get_snapshot().get_item(ARCHIVE_ITEM).is_empty()
		and session.get_snapshot().get_player_chronicle_entries().is_empty(),
		"20. Restart clears the route discovery, archive record, and chronicle"
	)

	session.travel_routes.append({
		"route_id": "invalid_partial_access_window",
		"from_location_id": "old_chen_shop",
		"to_location_id": "north_quay_record_house",
		"hours": 1,
		"food_cost": 0,
		"available_hour_start": 6,
	})
	var invalid_route_option := _route(
		session.get_travel_options(),
		"invalid_partial_access_window"
	)
	var invalid_route_time := session.get_time_summary()
	var invalid_route_result: Dictionary = session.travel(
		"invalid_partial_access_window"
	)
	_check(
		not bool(invalid_route_option.get("can_travel", true))
		and str(invalid_route_option.get("blocked_reason", ""))
			== "invalid_route_contract"
		and str(invalid_route_result.get("error", ""))
			== "invalid_route_contract"
		and session.get_time_summary() == invalid_route_time,
		"21. Partial access windows are invalid contracts, not ordinary closures"
	)
	session.travel_routes.remove_at(session.travel_routes.size() - 1)

	var challenge_resolver = ChallengeResolverModel.new()
	var fact_only_result: Variant = challenge_resolver.resolve_attempt(
		{
			"challenge_id": "fact_only_success_contract",
			"target_entity_id": "chen_mi",
			"stat_key": "perception",
			"difficulty": 1,
			"success": {
				"additional_facts": [{
					"fact_type": "fact_only_challenge_discovery",
					"target_id": "test_subject",
					"summary": "A fact-only challenge succeeded.",
				}],
			},
			"failure": {},
		},
		session.get_snapshot(),
		1,
		91,
		session.get_time_summary()
	)
	var fact_only_discovery := _fact(
		fact_only_result.facts_added,
		"fact_only_challenge_discovery"
	)
	_check(
		not fact_only_discovery.is_empty()
		and fact_only_result.item_changes.is_empty()
		and (
			fact_only_discovery.get("cause_fact_ids", []) as Array
		) == ["actor_attempted_challenge:91"],
		"22. Additional success facts work without requiring a discovered item"
	)
	_finish()


func _complete_granary_investigation(session: Variant) -> void:
	session.travel(GRANARY_OUTBOUND)
	session.execute_challenge_option(GRANARY_PREPARE)
	session.execute_challenge_option(
		GRANARY_ENTER,
		{"source": "test_injection", "roll_override": 3}
	)
	session.travel(GRANARY_RETURN)
	session.execute_return_echo_option(ECHO_OPTION)
	session.execute_investigation_option(INVESTIGATE_OPTION)


func _has_route(options: Array, route_id: String) -> bool:
	return not _route(options, route_id).is_empty()


func _route(options: Array, route_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("route_id", "")) == route_id:
			return option.duplicate(true)
	return {}


func _has_option(options: Array, option_id: String) -> bool:
	return not _option(options, option_id).is_empty()


func _option(options: Array, option_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _fact(facts: Array, fact_type: String) -> Dictionary:
	for fact: Dictionary in facts:
		if str(fact.get("fact_type", "")) == fact_type:
			return fact.duplicate(true)
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 NORTH QUAY RECORD HOUSE SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 NORTH QUAY RECORD HOUSE SESSION FAIL] " + failure)
	print(
		"[V5 NORTH QUAY RECORD HOUSE SESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 NORTH QUAY RECORD HOUSE SESSION PASS] " + message)
	else:
		failures.append(message)
