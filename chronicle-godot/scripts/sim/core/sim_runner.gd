extends RefCounted
class_name V5SimRunner

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")


func run_sequence(
		fixture_path: String,
		scenario_path: String,
		raw_rule_paths: Array
) -> Dictionary:
	var loader = SimRegistryModel.new()
	var fixture: Dictionary = loader.load_json(fixture_path)
	var scenario: Dictionary = loader.load_json(scenario_path)
	if fixture.is_empty():
		return _failure_result("", "", "fixture_not_loaded", 0, {}, null)
	if scenario.is_empty():
		return _failure_result(
			str(fixture.get("fixture_id", "")),
			"",
			"scenario_not_loaded",
			0,
			{},
			null
		)

	var fixture_id := str(fixture.get("fixture_id", ""))
	var scenario_id := str(scenario.get("scenario_id", ""))
	var expected_fixture_id := str(scenario.get("fixture_id", ""))
	if expected_fixture_id != "" and fixture_id != expected_fixture_id:
		return _failure_result(
			fixture_id,
			scenario_id,
			"scenario_fixture_mismatch",
			0,
			{},
			null
		)

	var session = SimSessionModel.new()
	var start_result: Dictionary = session.start_from_fixture_data(
		fixture,
		raw_rule_paths
	)
	if not bool(start_result.get("success", false)):
		return _failure_result(
			fixture_id,
			scenario_id,
			str(start_result.get("error", "session_start_failed")),
			0,
			{},
			session
		)

	var steps: Array = scenario.get("steps", [])
	for step_index: int in range(steps.size()):
		var step: Dictionary = steps[step_index]
		var select: Dictionary = step.get("select", {})
		var execution: Dictionary = session.execute_selection(
			str(select.get("rule_id", "")),
			str(select.get("target_id", "")),
			{
				"step_index": step_index,
				"step_id": str(step.get("step_id", "")),
			}
		)
		if not bool(execution.get("success", false)):
			return _failure_result(
				fixture_id,
				scenario_id,
				str(execution.get("error", "action_execution_failed")),
				step_index,
				step,
				session
			)

	return session.build_result_summary({
		"scenario_id": scenario_id,
	})


func _build_world_log_entry(
		step_index: int,
		step: Dictionary,
		candidate: Variant,
		result: Variant,
		candidate_count: int,
		candidate_context_source: String,
		resolver_context_source: String
) -> Dictionary:
	var session = SimSessionModel.new()
	var entry: Dictionary = session._build_world_log_entry(
		step_index,
		str(step.get("step_id", "")),
		candidate,
		result,
		candidate_count
	)
	entry["candidate_context_source"] = candidate_context_source
	entry["resolver_context_source"] = resolver_context_source
	return entry


func _failure_result(
		fixture_id: String,
		scenario_id: String,
		error: String,
		failed_step_index: int,
		failed_step: Dictionary,
		session: Variant
) -> Dictionary:
	var world_log: Array = []
	var store_summary := _empty_store_summary()
	var candidate_generation_count := 0
	if session != null:
		world_log = session.get_world_log_entries()
		store_summary = session.get_store_summary()
		candidate_generation_count = int(session.candidate_generation_count)

	return {
		"fixture_id": fixture_id,
		"scenario_id": scenario_id,
		"success": false,
		"error": error,
		"failed_step_index": failed_step_index,
		"failed_step": failed_step.duplicate(true),
		"steps_executed": failed_step_index,
		"candidate_selection_source": "ActionAffordanceSystem",
		"candidate_context_source": "SimSnapshot" if session != null else "",
		"candidate_generation_count": candidate_generation_count,
		"world_log": world_log,
		"store_summary": store_summary,
	}


func _empty_store_summary() -> Dictionary:
	return {
		"facts": 0,
		"states": 0,
		"relationships": 0,
		"memories": 0,
		"traces": 0,
		"rumors": 0,
		"pressures": 0,
		"obligations": 0,
		"exchanges": 0,
		"deferred_consequences": 0,
	}
