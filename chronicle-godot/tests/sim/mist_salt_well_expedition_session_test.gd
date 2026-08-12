extends SceneTree

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

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
const READ_TAX_DEED := "read_visible_readable_object:old_chen_public_granary_tax_deed"
const NORTH_QUAY_OUTBOUND := "old_chen_shop_to_north_quay_record_house"
const ARCHIVE_PREPARE := "prepare_flooded_archive_search"
const ARCHIVE_SEARCH := "search_flooded_archive_stack"
const EXPEDITION_PREPARE := "prepare_mist_salt_well_expedition"
const WELL_OUTBOUND := "north_quay_record_house_to_mist_salt_well"
const WELL_RETURN := "mist_salt_well_to_north_quay_record_house"
const WELL_DESCENT := "descend_mist_salt_well_second_ring"
const WELL_TRACE_ACTION := (
	"inspect_visible_trace:mist_salt_well_mouth_crust"
)
const BREATHING_VEIL := "waxed_mist_salt_breathing_veil"
const WELL_SAMPLE := "mist_salt_reverse_flow_filament_sample"

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
		and session.context.get_locations().size() == 4
		and not _has_route(session.get_travel_options(), WELL_OUTBOUND),
		"1. Mist salt well exists without leaking before Lu Huai's record"
	)

	_complete_archive_record(session)
	var blocked_route := _route(
		session.get_travel_options(),
		WELL_OUTBOUND
	)
	_check(
		not blocked_route.is_empty()
		and not bool(blocked_route.get("can_travel", true))
		and str(blocked_route.get("blocked_reason", ""))
			== "missing_required_item"
		and int(blocked_route.get("food_cost", -1)) == 2
		and int(session.get_snapshot().get_player_value(
			"food_count",
			-1
		)) == 1
		and _has_option(
			session.get_challenge_options(),
			EXPEDITION_PREPARE
		),
		"2. Lu Huai's record reveals a blocked expedition and its preparation"
	)

	var blocked_time := session.get_time_summary()
	var blocked_departure: Dictionary = session.travel(WELL_OUTBOUND)
	_check(
		not bool(blocked_departure.get("success", true))
		and str(blocked_departure.get("error", ""))
			== "missing_required_item"
		and session.get_time_summary() == blocked_time,
		"3. Direct travel cannot bypass required expedition gear"
	)

	var prepared: Dictionary = session.execute_challenge_option(
		EXPEDITION_PREPARE
	)
	var prepared_snapshot: Variant = session.get_snapshot()
	var veil: Dictionary = prepared_snapshot.get_item(BREATHING_VEIL)
	_check(
		bool(prepared.get("success", false))
		and str(prepared.get("outcome", "")) == "prepared"
		and int(prepared.get("hours", 0)) == 2
		and int(session.get_time_summary().get("hour", -1)) == 12
		and int(prepared_snapshot.get_player_value("food_count", -1)) == 5,
		"4. Two hours of archive work grant exactly four return rations"
	)
	_check(
		str(veil.get("owner_id", "")) == "player"
		and str(veil.get("provenance", {}).get(
			"provided_by",
			""
		)) == "north_quay_record_keeper"
		and str(veil.get("provenance", {}).get(
			"acquired_at",
			""
		)) == "north_quay_record_house"
		and BREATHING_VEIL in (
			prepared_snapshot.get_player_value(
				"inventory_item_ids",
				[]
			) as Array
		),
		"5. Preparation creates owned protective gear with provenance"
	)
	_check(
		bool(prepared_snapshot.get_player_value(
			"mist_salt_expedition_prepared",
			false
		))
		and _fact_count(
			session,
			"actor_prepared_mist_salt_expedition"
		) == 1
		and not _has_option(
			session.get_challenge_options(),
			EXPEDITION_PREPARE
		),
		"6. Expedition preparation is factual, persistent, and one-shot"
	)

	var stale_time := session.get_time_summary()
	var stale_prepare: Dictionary = session.execute_challenge_option(
		EXPEDITION_PREPARE
	)
	_check(
		not bool(stale_prepare.get("success", true))
		and str(stale_prepare.get("error", ""))
			== "challenge_option_not_found"
		and session.get_time_summary() == stale_time
		and int(session.get_snapshot().get_player_value(
			"food_count",
			-1
		)) == 5,
		"7. Stale preparation cannot duplicate time, gear, or food"
	)

	var ready_route := _route(
		session.get_travel_options(),
		WELL_OUTBOUND
	)
	_check(
		bool(ready_route.get("can_travel", false))
		and "先在旧档房" in str(ready_route.get("access_hint", ""))
		and int(ready_route.get("hours", 0)) == 6,
		"8. Gear and rations turn the six-hour expedition route usable"
	)

	var outbound: Dictionary = session.travel(WELL_OUTBOUND)
	var well_snapshot: Variant = session.get_snapshot()
	_check(
		bool(outbound.get("success", false))
		and str(session.context.location_id) == "mist_salt_well"
		and int(session.get_time_summary().get("hour", -1)) == 18
		and int(well_snapshot.get_player_value("food_count", -1)) == 3,
		"9. Outbound travel reaches the well and reserves food for the return"
	)
	_check(
		not well_snapshot.get_entity(
			"mist_salt_well_mouth_crust"
		).is_empty()
		and not well_snapshot.get_entity(
			"mist_salt_second_ring_stairs"
		).is_empty()
		and well_snapshot.get_entity("north_quay_record_keeper").is_empty(),
		"10. Well projection contains only its warning, evidence, and descent"
	)

	var descent := _option(
		session.get_challenge_options(),
		WELL_DESCENT
	)
	var return_route := _route(
		session.get_travel_options(),
		WELL_RETURN
	)
	_check(
		_has_action(session.get_action_options(), WELL_TRACE_ACTION)
		and not descent.is_empty()
		and str(descent.get("risk_label", "")) == "不可逆"
		and "长期" in str(descent.get("risk_description", ""))
		and bool(return_route.get("can_travel", false))
		and "带着现有发现" in str(return_route.get("label", "")),
		"11. The well offers inspect, descend, and return as simultaneous choices"
	)

	var inspected: Dictionary = session.execute_action(WELL_TRACE_ACTION)
	var shallow_return: Dictionary = session.travel(WELL_RETURN)
	var shallow_snapshot: Variant = session.get_snapshot()
	_check(
		bool(inspected.get("success", false))
		and bool(shallow_return.get("success", false))
		and str(session.context.location_id) == "north_quay_record_house"
		and str(shallow_snapshot.get_player_value(
			"mist_salt_echo",
			"none"
		)) == "none"
		and shallow_snapshot.get_item(WELL_SAMPLE).is_empty(),
		"12. Inspecting the mouth and returning avoids the lasting descent cost"
	)
	_check(
		not _fact_for_target(
			shallow_snapshot.get_facts(),
			"actor_inspected_trace",
			"mist_salt_well_mouth_crust"
		).is_empty()
		and int(shallow_snapshot.get_player_value("food_count", -1)) == 1
		and int(session.get_time_summary().get("day", -1)) == 3
		and int(session.get_time_summary().get("hour", -1)) == 0,
		"13. A cautious return preserves the surface observation and pays the route"
	)

	session = _session_at_well()
	var failed: Dictionary = session.execute_challenge_option(
		WELL_DESCENT,
		{"source": "test_injection", "roll_override": 1}
	)
	var failed_snapshot: Variant = session.get_snapshot()
	_check(
		bool(failed.get("success", false))
		and str(failed.get("outcome", "")) == "failure"
		and int(failed_snapshot.get_player_value("health", 0)) == 90
		and str(failed_snapshot.get_player_value("injury", ""))
			== "mist_salt_throat_burn"
		and str(failed_snapshot.get_player_value("mist_salt_echo", ""))
			== "faint",
		"14. Failed descent causes ordinary injury and a separate lasting echo"
	)
	var failure_echo_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type("actor_acquired_mist_salt_echo")
	_check(
		failure_echo_facts.size() == 1
		and str((failure_echo_facts[0] as Dictionary).get(
			"epistemic_status",
			""
		)) == "experienced"
		and failed_snapshot.get_item(WELL_SAMPLE).is_empty()
		and _chronicle_by_title(
			failed_snapshot,
			"井下白丝朝水而生"
		).is_empty(),
		"15. Failure records experienced cost without fabricating discovery"
	)
	_check(
		_option(
			session.get_challenge_options(),
			WELL_DESCENT
		).is_empty()
		and bool(_route(
			session.get_travel_options(),
			WELL_RETURN
		).get("can_travel", false)),
		"16. A failed descent closes the danger but never traps the traveler"
	)
	session.travel(WELL_RETURN)
	_check(
		str(session.get_snapshot().get_player_value(
			"mist_salt_echo",
			""
		)) == "faint"
		and str(session.context.location_id)
			== "north_quay_record_house",
		"17. Returning to ordinary space does not erase the long-term condition"
	)

	session = _session_at_well()
	var succeeded: Dictionary = session.execute_challenge_option(
		WELL_DESCENT,
		{"source": "test_injection", "roll_override": 15}
	)
	var success_snapshot: Variant = session.get_snapshot()
	var sample: Dictionary = success_snapshot.get_item(WELL_SAMPLE)
	_check(
		bool(succeeded.get("success", false))
		and str(succeeded.get("outcome", "")) == "success"
		and str((succeeded.get(
			"transaction_result",
			{}
		) as Dictionary).get(
			"narrative_result",
			{}
		).get("stat_key", "")) == "constitution"
		and int((succeeded.get(
			"transaction_result",
			{}
		) as Dictionary).get(
			"narrative_result",
			{}
		).get("total", 0)) == 23
		and str(success_snapshot.get_player_value(
			"mist_salt_echo",
			""
		)) == "faint",
		"18. Successful descent still applies the same irreversible echo"
	)
	_check(
		str(sample.get("owner_id", "")) == "player"
		and str(sample.get("provenance", {}).get(
			"source_depth",
			""
		)) == "second_ring"
		and str(sample.get("provenance", {}).get(
			"epistemic_status",
			""
		)) == "direct_observation"
		and bool(success_snapshot.get_entity_state(
			"mist_salt_lu_huai_marker",
			"visible",
			false
		)),
		"19. Success creates a bounded field sample and reveals Lu Huai's marker"
	)
	_check(
		_fact_count(
			session,
			"actor_observed_mist_salt_filaments_follow_water"
		) == 1
		and _fact_count(
			session,
			"actor_found_lu_huai_second_ring_marker"
		) == 1
		and _fact_count(
			session,
			"actor_acquired_mist_salt_echo"
		) == 1,
		"20. Observation, historical marker, and personal cost remain separate facts"
	)

	var deep_entry := _chronicle_by_title(
		success_snapshot,
		"井下白丝朝水而生"
	)
	var source_types: Array = deep_entry.get("source_fact_types", [])
	_check(
		not deep_entry.is_empty()
		and str(deep_entry.get("branch", "")) == "direct"
		and (deep_entry.get("claims", []) as Array).size() == 4
		and "仍然没有答案" in str(deep_entry.get("body", ""))
		and WELL_SAMPLE in (
			deep_entry.get("source_item_ids", []) as Array
		),
		"21. Deep chronicle preserves both evidence and unresolved questions"
	)
	_check(
		"actor_traveled_route" in source_types
		and "actor_attempted_challenge" in source_types
		and "actor_acquired_mist_salt_echo" in source_types
		and "actor_discovered_item" in source_types
		and "actor_observed_mist_salt_filaments_follow_water"
			in source_types
		and "actor_found_lu_huai_second_ring_marker" in source_types,
		"22. Chronicle cites route, attempt, cost, sample, observation, and marker"
	)

	session.travel(WELL_RETURN)
	var returned_snapshot: Variant = session.get_snapshot()
	_check(
		not returned_snapshot.get_item(WELL_SAMPLE).is_empty()
		and str(returned_snapshot.get_player_value(
			"mist_salt_echo",
			""
		)) == "faint"
		and not _chronicle_by_title(
			returned_snapshot,
			"井下白丝朝水而生"
		).is_empty(),
		"23. Sample, chronicle, and lasting cost return to the continuing world"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	var restarted_snapshot: Variant = session.get_snapshot()
	_check(
		str(restarted_snapshot.get_player_value(
			"mist_salt_echo",
			""
		)) == "none"
		and restarted_snapshot.get_item(BREATHING_VEIL).is_empty()
		and restarted_snapshot.get_item(WELL_SAMPLE).is_empty()
		and not _has_route(session.get_travel_options(), WELL_OUTBOUND),
		"24. Restart clears expedition-specific state, gear, evidence, and route"
	)
	_finish()


func _session_at_well() -> Variant:
	var session = SimSessionModel.new()
	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_complete_archive_record(session)
	session.execute_challenge_option(EXPEDITION_PREPARE)
	session.travel(WELL_OUTBOUND)
	return session


func _complete_archive_record(session: Variant) -> void:
	session.travel(GRANARY_OUTBOUND)
	session.execute_challenge_option(GRANARY_PREPARE)
	session.execute_challenge_option(
		GRANARY_ENTER,
		{"source": "test_injection", "roll_override": 3}
	)
	session.travel(GRANARY_RETURN)
	session.execute_return_echo_option(ECHO_OPTION)
	session.execute_investigation_option(INVESTIGATE_OPTION)
	session.execute_action(READ_TAX_DEED)
	session.advance_time(6, "wait_for_north_quay_ferry")
	session.travel(NORTH_QUAY_OUTBOUND)
	session.execute_challenge_option(ARCHIVE_PREPARE)
	session.execute_challenge_option(
		ARCHIVE_SEARCH,
		{"source": "test_injection", "roll_override": 1}
	)


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


func _has_action(options: Array, action_id: String) -> bool:
	for option: Dictionary in options:
		if str(option.get("action_id", "")) == action_id:
			return true
	return false


func _fact_count(session: Variant, fact_type: String) -> int:
	return session.stores["fact_store"].find_facts_by_type(
		fact_type
	).size()


func _fact_for_target(
		facts: Array,
		fact_type: String,
		target_id: String
) -> Dictionary:
	for fact: Dictionary in facts:
		if (
			str(fact.get("fact_type", "")) == fact_type
			and str(fact.get("target_id", "")) == target_id
		):
			return fact.duplicate(true)
	return {}


func _chronicle_by_title(snapshot: Variant, title: String) -> Dictionary:
	for entry: Dictionary in snapshot.get_player_chronicle_entries():
		if str(entry.get("title", "")) == title:
			return entry.duplicate(true)
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 MIST SALT WELL EXPEDITION SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(
			"[V5 MIST SALT WELL EXPEDITION SESSION FAIL] " + failure
		)
	print(
		"[V5 MIST SALT WELL EXPEDITION SESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 MIST SALT WELL EXPEDITION SESSION PASS] " + message)
	else:
		failures.append(message)
