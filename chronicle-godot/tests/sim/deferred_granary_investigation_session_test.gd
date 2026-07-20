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
const ECHO_OPTION := "show_granary_measure_token_to_chen_mi"
const INVESTIGATE_OPTION := "investigate_public_granary_seal_records"
const DEFER_OPTION := "defer_public_granary_seal_records"
const LEAD_ID := "public_granary_seal_records"
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
		and int(start_result.get(
			"investigation_definition_count",
			0
		)) == 1
		and session.get_investigation_options().is_empty()
		and session.get_snapshot().get_investigation_leads().is_empty(),
		"1. Investigation definition loads without fabricating an initial lead"
	)

	_complete_return_echo(session)
	var opened_snapshot: Variant = session.get_snapshot()
	var opened_lead: Dictionary = (
		opened_snapshot.get_investigation_lead(LEAD_ID)
	)
	_check(
		str(opened_lead.get("status", "")) == "open"
		and str(opened_lead.get("disposition", "")) == "fresh"
		and (opened_lead.get("source_fact_ids", []) as Array).size()
			== 3
		and DISCOVERY_ITEM in (
			opened_lead.get("source_item_ids", []) as Array
		),
		"2. Token recognition opens a structured lead with facts and item source"
	)
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"investigation_lead_opened"
		).size() == 1
		and (opened_lead.get("history", []) as Array).size() == 1,
		"3. Opening the lead is itself a traceable fact and history event"
	)

	var fresh_options := session.get_investigation_options()
	var investigate_option := _option(
		fresh_options,
		INVESTIGATE_OPTION
	)
	var defer_option := _option(fresh_options, DEFER_OPTION)
	_check(
		fresh_options.size() == 2
		and int(investigate_option.get("hours", 0)) == 3
		and int(defer_option.get("hours", 0)) == 1
		and str(investigate_option.get("action_type", ""))
			== "investigation"
		and str(defer_option.get("action_type", "")) == "life",
		"4. Fresh lead offers a three-hour search and a one-hour life choice"
	)

	var time_before_invalid := session.get_time_summary()
	var log_before_invalid := session.get_world_log_entries().size()
	var invalid: Dictionary = session.execute_investigation_option(
		"missing_investigation_option"
	)
	_check(
		not bool(invalid.get("success", true))
		and str(invalid.get("error", ""))
			== "investigation_option_not_found"
		and session.get_time_summary() == time_before_invalid
		and session.get_world_log_entries().size() == log_before_invalid,
		"5. Invalid investigation choice cannot consume time or write history"
	)

	var deferred: Dictionary = session.execute_investigation_option(
		DEFER_OPTION
	)
	var deferred_snapshot: Variant = session.get_snapshot()
	var deferred_lead: Dictionary = (
		deferred_snapshot.get_investigation_lead(LEAD_ID)
	)
	_check(
		bool(deferred.get("success", false))
		and str(deferred.get("option_type", "")) == "defer"
		and int(deferred.get("time", {}).get("hour", 0)) == 22
		and int(deferred.get("investigation_defer_count", 0)) == 1,
		"6. Deferring the lead consumes one real world hour"
	)
	_check(
		str(deferred_lead.get("status", "")) == "open"
		and str(deferred_lead.get("disposition", "")) == "deferred"
		and (deferred_lead.get("history", []) as Array).size() == 2
		and str(deferred_lead.get("defer_fact_id", "")) != "",
		"7. Deferred lead remains open and records the postponement"
	)
	_check(
		str(deferred_snapshot.get_entity_state(
			"chen_mi",
			"granary_record_stance",
			""
		)) == "waiting_for_return"
		and session.stores["memory_store"].find_memories_by_type(
			"chen_mi",
			"remembers_traveler_deferred_granary_records"
		).size() == 1,
		"8. Chen Mi adopts a waiting stance and remembers the life choice"
	)
	_check(
		session.stores["fact_store"].find_facts_by_type(
			"actor_deferred_public_granary_investigation"
		).size() == 1
		and deferred_snapshot.get_player_chronicle_entries().size() == 2
		and str(
			(
				deferred_snapshot.get_player_chronicle_entries()[1]
				as Dictionary
			).get("branch", "")
		) == "defer",
		"9. Deferral creates a fact and its own personal chronicle branch"
	)
	var defer_chronicle: Dictionary = (
		deferred_snapshot.get_player_chronicle_entries()[1]
	)
	_check(
		str(defer_chronicle.get("title", ""))
			== "留到以后追查的旧事"
		and "第1天22:00" in str(defer_chronicle.get("body", ""))
		and (defer_chronicle.get("source_fact_ids", []) as Array).size()
			== 4
		and (defer_chronicle.get("claims", []) as Array).size() == 1,
		"10. Deferred chronicle retains lead causes and the explicit choice"
	)

	var after_defer_options := session.get_investigation_options()
	_check(
		after_defer_options.size() == 1
		and not _has_option(after_defer_options, DEFER_OPTION)
		and _has_option(after_defer_options, INVESTIGATE_OPTION),
		"11. Defer cannot be repeated but the investigation remains available"
	)
	session.advance_time(2, "continue_daily_life")
	_check(
		int(session.get_time_summary().get("day", 0)) == 2
		and int(session.get_time_summary().get("hour", -1)) == 0
		and _has_option(
			session.get_investigation_options(),
			INVESTIGATE_OPTION
		),
		"12. Ordinary life can continue while the deferred lead persists"
	)

	var investigated: Dictionary = session.execute_investigation_option(
		INVESTIGATE_OPTION
	)
	var resolved_snapshot: Variant = session.get_snapshot()
	var resolved_lead: Dictionary = (
		resolved_snapshot.get_investigation_lead(LEAD_ID)
	)
	var narrative: Dictionary = (
		investigated.get("transaction_result", {}) as Dictionary
	).get("narrative_result", {})
	_check(
		bool(investigated.get("success", false))
		and int(investigated.get("time", {}).get("day", 0)) == 2
		and int(investigated.get("time", {}).get("hour", -1)) == 3
		and bool(narrative.get("resumed_after_defer", false))
		and str(narrative.get("title", ""))
			== "重新翻开的税契匣",
		"13. Deferred investigation can be resumed later for a real three-hour cost"
	)
	_check(
		str(resolved_lead.get("status", "")) == "resolved"
		and str(resolved_lead.get("disposition", ""))
			== "investigated"
		and bool(resolved_lead.get("resumed_after_defer", false))
		and (resolved_lead.get("history", []) as Array).size() == 3,
		"14. Resumed investigation resolves the same persistent lead"
	)
	_check(
		bool(resolved_snapshot.get_entity_state(
			"old_chen_public_granary_tax_deed",
			"visible",
			false
		))
		and str(resolved_snapshot.get_entity_state(
			"chen_mi",
			"granary_record_stance",
			""
		)) == "helped_search",
		"15. Search reveals a concrete record and changes Chen Mi's stance"
	)

	var archive_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type(
		"actor_found_public_granary_archive_reference"
	)
	var archive_fact: Dictionary = archive_facts[0]
	_check(
		archive_facts.size() == 1
		and str(archive_fact.get("former_clerk_name", "")) == "陆槐"
		and str(archive_fact.get("archive_location_name", ""))
			== "北埠旧档房"
		and (
			str(deferred_lead.get("defer_fact_id", ""))
			in (
				(
					session.stores["fact_store"].find_facts_by_type(
						"actor_investigated_public_granary_records"
					)[0] as Dictionary
				).get("cause_fact_ids", []) as Array
			)
		),
		"16. Archive reference names a person and place with defer evidence"
	)
	_check(
		int(resolved_snapshot.get_relation(
			"chen_mi",
			"player",
			"trust",
			0
		)) == 16
		and int(resolved_snapshot.get_relation(
			"chen_mi",
			"player",
			"familiarity",
			0
		)) == 20,
		"17. Shared late-night search builds on the existing relationship"
	)
	var completed_memories: Array = session.stores[
		"memory_store"
	].find_memories_by_type(
		"chen_mi",
		"remembers_searching_granary_records_together"
	)
	var item: Dictionary = resolved_snapshot.get_item(DISCOVERY_ITEM)
	_check(
		completed_memories.size() == 1
		and (item.get("history", []) as Array).size() == 2
		and str(
			(
				(item.get("history", []) as Array)[1]
				as Dictionary
			).get("event_type", "")
		) == "used_to_trace_archive",
		"18. NPC memory and token history preserve the resumed investigation"
	)

	var chronicle_entries: Array = (
		resolved_snapshot.get_player_chronicle_entries()
	)
	var investigation_chronicle: Dictionary = chronicle_entries[2]
	_check(
		chronicle_entries.size() == 3
		and str(investigation_chronicle.get("title", ""))
			== "税契夹页上的名字"
		and "第2天03:00" in str(
			investigation_chronicle.get("body", "")
		)
		and "搁置线索后" in str(
			investigation_chronicle.get("body", "")
		)
		and bool(
			investigation_chronicle.get(
				"resumed_after_defer",
				false
			)
		),
		"19. Resumed path generates a distinct evidence-backed chronicle"
	)
	_check(
		str(deferred_lead.get("defer_fact_id", "")) in (
			investigation_chronicle.get("source_fact_ids", []) as Array
		)
		and (
			"actor_deferred_public_granary_investigation"
			in (
				investigation_chronicle.get(
					"source_fact_types",
					[]
				) as Array
			)
		)
		and (
			investigation_chronicle.get("claims", []) as Array
		).size() == 2,
		"20. Resumed chronicle cites the deferred choice and both new claims"
	)
	_check(
		session.get_investigation_options().is_empty(),
		"21. Resolved lead leaves no duplicate investigation action"
	)

	var time_before_stale := session.get_time_summary()
	var log_before_stale := session.get_world_log_entries().size()
	var stale: Dictionary = session.execute_investigation_option(
		INVESTIGATE_OPTION
	)
	_check(
		not bool(stale.get("success", true))
		and str(stale.get("error", ""))
			== "investigation_option_not_found"
		and session.get_time_summary() == time_before_stale
		and session.get_world_log_entries().size() == log_before_stale,
		"22. Stale investigation cannot duplicate time, facts, or chronicle"
	)
	var summary: Dictionary = session.build_result_summary()
	_check(
		int(summary.get("investigations_resolved", 0)) == 1
		and int(summary.get("investigations_deferred", 0)) == 1
		and int(summary.get("store_summary", {}).get(
			"investigation_leads",
			0
		)) == 1
		and int(summary.get("snapshot_summary", {}).get(
			"final_open_investigation_lead_count",
			-1
		)) == 0
		and int(summary.get("world_log_summary", {}).get(
			"investigation_change_count",
			0
		)) == 3,
		"23. Summary separates opened, deferred, and resolved investigation state"
	)

	var immediate_session = SimSessionModel.new()
	immediate_session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_complete_return_echo(immediate_session)
	var immediate: Dictionary = (
		immediate_session.execute_investigation_option(
			INVESTIGATE_OPTION
		)
	)
	var immediate_entries: Array = (
		immediate_session.get_snapshot().get_player_chronicle_entries()
	)
	_check(
		bool(immediate.get("success", false))
		and int(immediate.get("time", {}).get("day", 0)) == 2
		and int(immediate.get("time", {}).get("hour", -1)) == 0
		and not bool(
			(immediate.get("transaction_result", {}) as Dictionary)
			.get("narrative_result", {})
			.get("resumed_after_defer", false)
		)
		and immediate_entries.size() == 2
		and "搁置线索后" not in str(
			(immediate_entries[1] as Dictionary).get("body", "")
		),
		"24. Immediate search forms a different time and chronicle branch"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_check(
		session.investigation_count == 0
		and session.investigation_defer_count == 0
		and session.stores["investigation_store"].list_leads().is_empty()
		and session.get_snapshot().get_player_chronicle_entries().is_empty(),
		"25. Restart clears lead, branch counters, and chronicle state"
	)
	_finish()


func _complete_return_echo(session: Variant) -> void:
	session.travel(OUTBOUND_ROUTE)
	session.execute_challenge_option(PREPARE_OPTION)
	session.execute_challenge_option(
		ENTER_OPTION,
		{"source": "test_injection", "roll_override": 3}
	)
	session.travel(RETURN_ROUTE)
	session.execute_return_echo_option(ECHO_OPTION)


func _has_option(options: Array, option_id: String) -> bool:
	return not _option(options, option_id).is_empty()


func _option(options: Array, option_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 DEFERRED GRANARY INVESTIGATION SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 DEFERRED GRANARY INVESTIGATION SESSION FAIL] " + failure)
	print(
		"[V5 DEFERRED GRANARY INVESTIGATION SESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 DEFERRED GRANARY INVESTIGATION SESSION PASS] " + message)
	else:
		failures.append(message)
