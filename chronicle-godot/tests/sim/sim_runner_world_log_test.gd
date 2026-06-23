extends SceneTree

const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const LAKE_TOWN_FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"
const LAKE_TOWN_SCENARIO_PATH := "res://data/sim/fixtures/scenarios/lake_town_food_crisis_sequence.json"
const SEVENTH_OUTPOST_REPORT_SCENARIO_PATH := "res://data/sim/fixtures/scenarios/seventh_outpost_report_sequence.json"
const SEVENTH_OUTPOST_CONCEAL_SCENARIO_PATH := "res://data/sim/fixtures/scenarios/seventh_outpost_conceal_sequence.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_rule_paths := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var runner = SimRunnerModel.new()

	var lake_result: Dictionary = runner.run_sequence(
		LAKE_TOWN_FIXTURE_PATH,
		LAKE_TOWN_SCENARIO_PATH,
		raw_rule_paths
	)
	_check(
		bool(lake_result.get("success", false))
		and str(lake_result.get("scenario_id", "")) == "lake_town_food_crisis_sequence",
		"1. 能运行 lake_town_food_crisis_sequence"
	)
	_check(
		int(lake_result.get("steps_executed", 0)) == 3,
		"2. 湖湾镇执行 3 步"
	)
	_check(
		_world_log_has_fact(lake_result, "actor_gave_food_to_target"),
		"3. 湖湾镇 world_log 包含 actor_gave_food_to_target"
	)
	_check(
		_world_log_has_fact(lake_result, "actor_read_object"),
		"4. 湖湾镇 world_log 包含 actor_read_object"
	)
	_check(
		_world_log_has_fact(lake_result, "actor_inspected_trace"),
		"5. 湖湾镇 world_log 包含 actor_inspected_trace"
	)

	var report_result: Dictionary = runner.run_sequence(
		SEVENTH_OUTPOST_FIXTURE_PATH,
		SEVENTH_OUTPOST_REPORT_SCENARIO_PATH,
		raw_rule_paths
	)
	_check(
		bool(report_result.get("success", false))
		and str(report_result.get("scenario_id", "")) == "seventh_outpost_report_sequence",
		"6. 能运行 seventh_outpost_report_sequence"
	)
	_check(
		_world_log_has_fact(report_result, "actor_reported_discipline_violation"),
		"7. 第七哨站 report sequence 产生 actor_reported_discipline_violation"
	)
	_check(
		_world_log_has_trace_type(report_result, "institutional_record_mark")
		and int(report_result.get("store_summary", {}).get("traces", 0)) == 1,
		"8. 第七哨站 report sequence 产生 institutional_record_mark trace"
	)
	_check(
		_world_log_has_rumor_seed(report_result, "outpost_discipline_report_seed")
		and int(report_result.get("store_summary", {}).get("rumors", 0)) == 1,
		"9. 第七哨站 report sequence 产生 outpost_discipline_report_seed rumor seed"
	)

	var conceal_result: Dictionary = runner.run_sequence(
		SEVENTH_OUTPOST_FIXTURE_PATH,
		SEVENTH_OUTPOST_CONCEAL_SCENARIO_PATH,
		raw_rule_paths
	)
	_check(
		bool(conceal_result.get("success", false))
		and str(conceal_result.get("scenario_id", "")) == "seventh_outpost_conceal_sequence",
		"10. 能运行 seventh_outpost_conceal_sequence"
	)
	_check(
		_world_log_has_fact(conceal_result, "actor_concealed_discipline_violation"),
		"11. 第七哨站 conceal sequence 产生 actor_concealed_discipline_violation"
	)
	_check(
		not _world_log_has_any_rumor_seed(conceal_result)
		and int(conceal_result.get("store_summary", {}).get("rumors", 0)) == 0,
		"12. 第七哨站 conceal sequence 不产生 rumor seed"
	)

	_check(
		_uses_affordance_selection(lake_result)
		and _uses_affordance_selection(report_result)
		and _uses_affordance_selection(conceal_result),
		"13. 每个 sequence 都通过 ActionAffordanceSystem 选择候选"
	)

	_check(
		int(lake_result.get("store_summary", {}).get("facts", 0)) == 3
		and int(lake_result.get("store_summary", {}).get("memories", 0)) == 3
		and int(lake_result.get("store_summary", {}).get("relationships", 0)) == 3,
		"14. 湖湾镇 store 写回 facts / relationships / memories"
	)
	_check(
		int(report_result.get("store_summary", {}).get("facts", 0)) == 3
		and int(report_result.get("store_summary", {}).get("traces", 0)) == 1
		and int(report_result.get("store_summary", {}).get("rumors", 0)) == 1,
		"15. 第七哨站 report store 写回 facts / traces / rumors"
	)
	_check(
		_world_log_has_narrative(conceal_result, "actor_concealed_discipline_violation"),
		"16. 第七哨站 conceal sequence 生成 narrative summary"
	)

	_finish()


func _world_log_has_fact(result: Dictionary, fact_type: String) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if fact_type in (entry.get("facts_added", []) as Array):
			return true
	return false


func _world_log_has_trace_type(result: Dictionary, trace_type: String) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if trace_type in (entry.get("trace_types", []) as Array):
			return true
	return false


func _world_log_has_rumor_seed(result: Dictionary, rumor_id: String) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if rumor_id in (entry.get("rumor_seed_ids", []) as Array):
			return true
	return false


func _world_log_has_any_rumor_seed(result: Dictionary) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if not (entry.get("rumor_seed_ids", []) as Array).is_empty():
			return true
	return false


func _world_log_has_narrative(result: Dictionary, fact_type: String) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if (
			fact_type in (entry.get("facts_added", []) as Array)
			and str(entry.get("narrative_summary", "")) != ""
		):
			return true
	return false


func _uses_affordance_selection(result: Dictionary) -> bool:
	if str(result.get("candidate_selection_source", "")) != "ActionAffordanceSystem":
		return false
	if int(result.get("candidate_generation_count", 0)) != int(result.get("steps_executed", 0)):
		return false

	for entry: Dictionary in result.get("world_log", []):
		if not bool(entry.get("selected_from_candidates", false)):
			return false
		if int(entry.get("candidate_count", 0)) <= 0:
			return false
	return true


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SIM RUNNER WORLD LOG RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 SIM RUNNER WORLD LOG FAIL] " + failure)
		print("[V5 SIM RUNNER WORLD LOG RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 SIM RUNNER WORLD LOG PASS] " + message)
	else:
		failures.append(message)
