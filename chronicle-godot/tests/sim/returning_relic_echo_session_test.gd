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
			"return_echo_definition_count",
			0
		)) == 1
		and session.get_return_echo_options().is_empty(),
		"1. Return echo definition loads but stays hidden without its causes"
	)

	var fake_fixture := _fixture_data()
	var fake_item := (
		(
			(fake_fixture.get("challenges", []) as Array)[0]
			as Dictionary
		).get("success", {}) as Dictionary
	).get("item", {}) as Dictionary
	fake_item = fake_item.duplicate(true)
	fake_item.erase("item_id")
	fake_item["item_instance_id"] = DISCOVERY_ITEM
	fake_item["holder"] = {"kind": "entity", "id": "player"}
	var fake_provenance: Dictionary = (
		fake_item.get("provenance", {}) as Dictionary
	).duplicate(true)
	fake_provenance["discovered_at"] = "abandoned_granary"
	fake_provenance["source_challenge_id"] = (
		"granary_rotten_floor_entry"
	)
	fake_item["provenance"] = fake_provenance
	fake_fixture["initial_items"] = [fake_item]
	var fake_session = SimSessionModel.new()
	fake_session.start_from_fixture_data(fake_fixture, RULE_PATHS)
	_check(
		fake_session.get_snapshot().get_player_items().size() == 1
		and fake_session.get_return_echo_options().is_empty(),
		"2. An injected matching item cannot bypass travel and discovery facts"
	)

	session.travel(OUTBOUND_ROUTE)
	_check(
		session.get_return_echo_options().is_empty(),
		"3. The echo stays hidden while the traveler is still at the granary"
	)
	session.execute_challenge_option(PREPARE_OPTION)
	session.execute_challenge_option(
		ENTER_OPTION,
		{"source": "test_injection", "roll_override": 3}
	)
	_check(
		session.get_snapshot().get_player_items().size() == 1
		and session.get_return_echo_options().is_empty(),
		"4. Discovery alone is insufficient before the return journey"
	)

	session.travel(RETURN_ROUTE)
	var options := session.get_return_echo_options()
	var option := _option(options, ECHO_OPTION)
	_check(
		options.size() == 1
		and str(option.get("item_id", "")) == DISCOVERY_ITEM
		and str(option.get("target_entity_id", "")) == "chen_mi"
		and "旧物" in str(option.get("label", "")),
		"5. Returning with the provenanced token exposes one recognition choice"
	)

	var result: Dictionary = session.execute_return_echo_option(
		ECHO_OPTION,
		{"source": "returning_relic_echo_session_test"}
	)
	var transaction: Dictionary = result.get("transaction_result", {})
	var snapshot: Variant = session.get_snapshot()
	_check(
		bool(result.get("success", false))
		and int(result.get("return_echo_count", 0)) == 1
		and int(result.get("time", {}).get("hour", 0)) == 21
		and str(
			(transaction.get("narrative_result", {}) as Dictionary).get(
				"outcome",
				""
			)
		) == "recognized",
		"6. Recognition consumes one real hour and resolves once"
	)
	_check(
		bool(snapshot.get_entity_state(
			"chen_mi",
			"recognized_granary_measure_token",
			false
		))
		and int(snapshot.get_relation(
			"chen_mi",
			"player",
			"trust",
			0
		)) == 12
		and int(snapshot.get_relation(
			"chen_mi",
			"player",
			"familiarity",
			0
		)) == 15,
		"7. Chen Mi remembers the recognition state and changes relationship axes"
	)

	var recognition_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type("chen_mi_recognized_granary_measure_token")
	var clue_facts: Array = session.stores[
		"fact_store"
	].find_facts_by_type(
		"lake_town_public_granary_sealed_after_spoiled_grain"
	)
	var recognition_fact: Dictionary = recognition_facts[0]
	var clue_fact: Dictionary = clue_facts[0]
	_check(
		recognition_facts.size() == 1
		and clue_facts.size() == 1
		and (recognition_fact.get("cause_fact_ids", []) as Array).size()
			>= 5
		and str(clue_fact.get("item_id", "")) == DISCOVERY_ITEM
		and str(clue_fact.get("source_id", "")) == "chen_mi",
		"8. Recognition and local history are stored as causally linked facts"
	)

	var memories: Array = session.stores["memory_store"].find_memories_by_type(
		"chen_mi",
		"remembers_traveler_returned_granary_token"
	)
	_check(
		memories.size() == 1
		and str((memories[0] as Dictionary).get("item_id", ""))
			== DISCOVERY_ITEM
		and ((
			(memories[0] as Dictionary).get("source_fact_ids", [])
		) as Array).size() == 2,
		"9. The fixed NPC receives a structured memory with source facts"
	)

	var item: Dictionary = snapshot.get_item(DISCOVERY_ITEM)
	var item_history: Array = item.get("history", [])
	_check(
		item_history.size() == 1
		and str((item_history[0] as Dictionary).get(
			"event_type",
			""
		)) == "recognized_by"
		and str((item_history[0] as Dictionary).get("actor_id", ""))
			== "chen_mi"
		and int((item_history[0] as Dictionary).get("hour", 0)) == 21,
		"10. The token retains a history entry instead of being consumed"
	)

	var chronicle_entries: Array = snapshot.get_player_chronicle_entries()
	var chronicle: Dictionary = chronicle_entries[0]
	var source_types: Array = chronicle.get("source_fact_types", [])
	_check(
		chronicle_entries.size() == 1
		and str(chronicle.get("title", ""))
			== "被认出的验粮铜牌"
		and "第1天21:00" in str(chronicle.get("body", ""))
		and "废弃粮仓" in str(chronicle.get("body", ""))
		and "陈米" in str(chronicle.get("body", "")),
		"11. A readable personal chronicle is produced from the resolved event"
	)
	_check(
		"actor_traveled_route" in source_types
		and "actor_attempted_challenge" in source_types
		and "actor_discovered_item" in source_types
		and "chen_mi_recognized_granary_measure_token" in source_types
		and (
			"lake_town_public_granary_sealed_after_spoiled_grain"
			in source_types
		)
		and DISCOVERY_ITEM in (
			chronicle.get("source_item_ids", []) as Array
		),
		"12. Chronicle sources cover travel, check, discovery, recognition, and item"
	)
	_check(
		(chronicle.get("claims", []) as Array).size() == 2
		and (chronicle.get("source_fact_ids", []) as Array).size()
			>= 7
		and (chronicle.get("source_memory_ids", []) as Array).size()
			== 1,
		"13. Chronicle claims retain inspectable evidence references"
	)

	var world_summary := session.get_world_log_summary()
	_check(
		int(world_summary.get("relationship_change_count", 0)) == 2
		and int(world_summary.get("memory_count", 0)) >= 1
		and int(world_summary.get("chronicle_entry_count", 0)) == 1
		and int(world_summary.get("item_change_count", 0)) == 2,
		"14. WorldLog counts relationship, memory, item history, and chronicle writes"
	)
	_check(
		session.get_return_echo_options().is_empty(),
		"15. Completed recognition is no longer offered"
	)

	var time_before_stale := session.get_time_summary()
	var log_before_stale := session.get_world_log_entries().size()
	var stale: Dictionary = session.execute_return_echo_option(ECHO_OPTION)
	_check(
		not bool(stale.get("success", true))
		and str(stale.get("error", ""))
			== "return_echo_option_not_found"
		and session.get_time_summary() == time_before_stale
		and session.get_world_log_entries().size() == log_before_stale,
		"16. A stale echo cannot consume time or duplicate history"
	)

	var summary: Dictionary = session.build_result_summary()
	_check(
		int(summary.get("return_echoes_resolved", 0)) == 1
		and int(summary.get("world_ticks_executed", 0)) == 5
		and int(summary.get("store_summary", {}).get(
			"chronicle_entries",
			0
		)) == 1
		and int(summary.get("snapshot_summary", {}).get(
			"final_chronicle_entry_count",
			0
		)) == 1,
		"17. Session summary exposes echo and chronicle counts"
	)

	session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	_check(
		session.return_echo_count == 0
		and session.stores["chronicle_store"].list_entries().is_empty()
		and session.stores["memory_store"].memories.is_empty()
		and session.stores["item_store"].list_items().is_empty(),
		"18. Restart clears echo, memory, item, and chronicle state"
	)
	_finish()


func _fixture_data() -> Dictionary:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return (parsed as Dictionary).duplicate(true) if parsed is Dictionary else {}


func _option(options: Array, option_id: String) -> Dictionary:
	for option: Dictionary in options:
		if str(option.get("option_id", "")) == option_id:
			return option.duplicate(true)
	return {}


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RETURNING RELIC ECHO SESSION RESULT] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[V5 RETURNING RELIC ECHO SESSION FAIL] " + failure)
	print(
		"[V5 RETURNING RELIC ECHO SESSION RESULT] FAIL: %s"
		% JSON.stringify(failures)
	)
	quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 RETURNING RELIC ECHO SESSION PASS] " + message)
	else:
		failures.append(message)
