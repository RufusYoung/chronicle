extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const ResolverModel = preload("res://scripts/sim/micro_action_resolver.gd")
const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const SCENE_ID := "chen_mi_hiding_spoiled_grain_scene"
const ACTION_IDS: Array[String] = [
	"give_food_to_chen_mi",
	"ask_grain_origin",
	"report_to_guard",
	"ignore_chen_mi",
	"buy_spoiled_grain_low",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator := SimulatorModel.new()
	var resolver := ResolverModel.new()
	var initial: WorldSimState = simulator.load_seed(SEED_PATH)
	var actor := _test_actor()
	_check(
		resolver.build_action_candidates(initial, actor, SCENE_ID).is_empty(),
		"no scene means no lake town action candidates"
	)

	var baseline: WorldSimState = simulator.load_seed(SEED_PATH)
	simulator.advance_days(baseline, 6)
	var scene := _find_scene(baseline)
	_check(not scene.is_empty(), "baseline reaches the traceable Chen Mi scene")
	var candidates := resolver.build_action_candidates(
		baseline,
		actor,
		SCENE_ID
	)
	_check(candidates.size() >= 5, "scene generates at least five action candidates")
	_check(
		_candidate_ids(candidates) == ACTION_IDS,
		"baseline generates the required five action candidates"
	)
	_check(
		_all_candidates_traceable(candidates, scene),
		"every candidate keeps the narratable state facts and traces"
	)

	var no_food_actor := _test_actor()
	(no_food_actor["inventory"] as Dictionary)["food"] = 0
	_check(
		not resolver.can_resolve_action(
			baseline,
			no_food_actor,
			"give_food_to_chen_mi",
			SCENE_ID
		),
		"actor without food cannot give food"
	)
	var no_money_actor := _test_actor()
	no_money_actor["money"] = 0.0
	_check(
		not resolver.can_resolve_action(
			baseline,
			no_money_actor,
			"buy_spoiled_grain_low",
			SCENE_ID
		),
		"actor without money cannot buy spoiled grain"
	)
	var missing_trace_state := baseline.duplicate_state()
	_remove_trace_type(missing_trace_state, "child_hiding_bag")
	_check(
		not resolver.can_resolve_action(
			missing_trace_state,
			_test_actor(),
			"ask_grain_origin",
			SCENE_ID
		),
		"missing child_hiding_bag trace prevents asking the grain origin"
	)
	var failed_result := resolver.resolve_micro_action(
		baseline.duplicate_state(),
		no_food_actor,
		"give_food_to_chen_mi",
		SCENE_ID
	)
	_check(
		not bool(failed_result.get("ok", true))
		and String(failed_result.get("error", "")) == "missing_required_state",
		"missing required state returns an explicit failure"
	)

	var action_summaries: Dictionary = {}
	for action_id: String in ACTION_IDS:
		var before := baseline.duplicate_state()
		var action_state := baseline.duplicate_state()
		var action_actor := _test_actor()
		var result := resolver.resolve_micro_action(
			action_state,
			action_actor,
			action_id,
			SCENE_ID
		)
		var summary := resolver.build_action_result_summary(
			before,
			action_state,
			result
		)
		action_summaries[action_id] = summary
		_check(bool(result.get("ok", false)), "%s resolves successfully" % action_id)
		_check(
			not (result.get("created_fact_ids", []) as Array).is_empty(),
			"%s creates a WorldFact" % action_id
		)
		_check(
			not (summary.get("state_changes", {}) as Dictionary).is_empty(),
			"%s writes structured world state changes" % action_id
		)
		_check(
			_changed_category_count(summary) >= 2,
			"%s changes at least two world-state categories" % action_id
		)
		_check(
			not resolver.can_resolve_action(
				action_state,
				action_actor,
				action_id,
				SCENE_ID
			),
			"%s locks the narratable state after resolution" % action_id
		)

	_check_give_food(baseline, resolver, action_summaries)
	_check_ask_origin(action_summaries)
	_check_report_to_guard(baseline, resolver, action_summaries)
	_check_ignore(baseline, resolver, action_summaries)
	_check_buy_grain(baseline, resolver, action_summaries)
	_check_reproducible(baseline, resolver)

	for action_id: String in ACTION_IDS:
		var summary := action_summaries.get(action_id, {}) as Dictionary
		print(
			"[MICRO ACTION SUMMARY] %s facts=%s traces=%s memories=%s changes=%s"
			% [
				action_id,
				", ".join(summary.get("created_fact_types", [])),
				", ".join(summary.get("created_trace_types", [])),
				", ".join(summary.get("created_memory_types", [])),
				JSON.stringify(summary.get("state_changes", {})),
			]
		)

	if failures.is_empty():
		print("[MICRO ACTION RESOLVER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[MICRO ACTION RESOLVER FAIL] " + failure)
		print("[MICRO ACTION RESOLVER RESULT] FAIL: %s" % failures)
		quit(1)


func _check_give_food(
		baseline: WorldSimState,
		resolver,
		summaries: Dictionary
	) -> void:
	var state := baseline.duplicate_state()
	var actor := _test_actor()
	var food_before := int((actor.get("inventory", {}) as Dictionary).get("food", 0))
	var hunger_before := float(state.get_npc("chen_mi").get("hunger", 0.0))
	var fear_before := float(state.get_npc("chen_mi").get("fear", 0.0))
	var result: Dictionary = resolver.resolve_micro_action(
		state,
		actor,
		"give_food_to_chen_mi",
		SCENE_ID
	)
	_check(
		int((actor.get("inventory", {}) as Dictionary).get("food", 0))
		== food_before - 1,
		"give_food_to_chen_mi reduces actor food"
	)
	_check(
		float(state.get_npc("chen_mi").get("hunger", 0.0)) < hunger_before,
		"give_food_to_chen_mi lowers Chen Mi hunger"
	)
	_check(
		float(state.get_npc("chen_mi").get("fear", 0.0)) < fear_before,
		"give_food_to_chen_mi lowers Chen Mi fear"
	)
	var summary := summaries.get("give_food_to_chen_mi", {}) as Dictionary
	_check(
		"actor_gave_food_to_chen_mi" in (
			summary.get("created_fact_types", []) as Array
		)
		and "chen_mi_empty_food_wrap" in (
			summary.get("created_trace_types", []) as Array
		)
		and "chen_mi_remembers_actor_gave_food" in (
			summary.get("created_memory_types", []) as Array
		),
		"give_food_to_chen_mi creates fact, memory, and trace"
	)
	_check(bool(result.get("ok", false)), "give food verification action succeeds")


func _check_ask_origin(summaries: Dictionary) -> void:
	var summary := summaries.get("ask_grain_origin", {}) as Dictionary
	_check(
		"actor_asked_chen_mi_about_grain" in (
			summary.get("created_fact_types", []) as Array
		),
		"ask_grain_origin creates the inquiry fact"
	)
	_check(
		"granary_hint" in (
			summary.get("created_trace_types", []) as Array
		),
		"ask_grain_origin creates a granary hint trace"
	)


func _check_report_to_guard(
		baseline: WorldSimState,
		resolver,
		summaries: Dictionary
	) -> void:
	var state := baseline.duplicate_state()
	var actor := _test_actor()
	var fear_before := float(state.get_npc("chen_mi").get("fear", 0.0))
	resolver.resolve_micro_action(
		state,
		actor,
		"report_to_guard",
		SCENE_ID
	)
	var relationships := (
		state.micro_state.get("micro_relationships", {}) as Dictionary
	)
	var actor_relationships := (
		relationships.get("test_actor", {}) as Dictionary
	)
	var chen_relation := (
		actor_relationships.get("chen_mi", {}) as Dictionary
	)
	_check(
		float(state.get_npc("chen_mi").get("fear", 0.0)) > fear_before,
		"report_to_guard raises Chen Mi fear"
	)
	_check(
		float(chen_relation.get("trust", 0.0)) < 0.0,
		"report_to_guard lowers relationship trust"
	)
	var summary := summaries.get("report_to_guard", {}) as Dictionary
	_check(
		"guard_attention_at_old_chen_shop" in (
			summary.get("created_trace_types", []) as Array
		),
		"report_to_guard creates guard attention trace"
	)


func _check_ignore(
		baseline: WorldSimState,
		resolver,
		summaries: Dictionary
	) -> void:
	var state := baseline.duplicate_state()
	var hunger_before := float(state.get_npc("chen_mi").get("hunger", 0.0))
	resolver.resolve_micro_action(
		state,
		_test_actor(),
		"ignore_chen_mi",
		SCENE_ID
	)
	_check(
		float(state.get_npc("chen_mi").get("hunger", 0.0)) == hunger_before,
		"ignore_chen_mi does not lower Chen Mi hunger"
	)
	var summary := summaries.get("ignore_chen_mi", {}) as Dictionary
	_check(
		"actor_ignored_chen_mi_scene" in (
			summary.get("created_fact_types", []) as Array
		),
		"ignore_chen_mi creates an ignored-scene fact"
	)


func _check_buy_grain(
		baseline: WorldSimState,
		resolver,
		summaries: Dictionary
	) -> void:
	var state := baseline.duplicate_state()
	var actor := _test_actor()
	resolver.resolve_micro_action(
		state,
		actor,
		"buy_spoiled_grain_low",
		SCENE_ID
	)
	var actor_inventory := actor.get("inventory", {}) as Dictionary
	var chen_inventory := (
		state.get_npc("chen_mi").get("inventory", []) as Array
	)
	_check(
		int(actor_inventory.get("spoiled_grain", 0)) == 1
		and not "spoiled_grain" in chen_inventory,
		"buy_spoiled_grain_low transfers spoiled grain to the actor"
	)
	var summary := summaries.get("buy_spoiled_grain_low", {}) as Dictionary
	_check(
		"missing_spoiled_grain_bag" in (
			summary.get("created_trace_types", []) as Array
		),
		"buy_spoiled_grain_low creates the missing bag trace"
	)


func _check_reproducible(
		baseline: WorldSimState,
		resolver
	) -> void:
	var left := baseline.duplicate_state()
	var right := baseline.duplicate_state()
	var left_actor := _test_actor()
	var right_actor := _test_actor()
	var left_result: Dictionary = resolver.resolve_micro_action(
		left,
		left_actor,
		"give_food_to_chen_mi",
		SCENE_ID
	)
	var right_result: Dictionary = resolver.resolve_micro_action(
		right,
		right_actor,
		"give_food_to_chen_mi",
		SCENE_ID
	)
	var left_summary: Dictionary = resolver.build_action_result_summary(
		baseline,
		left,
		left_result
	)
	var right_summary: Dictionary = resolver.build_action_result_summary(
		baseline,
		right,
		right_result
	)
	_check(
		JSON.stringify(left_summary) == JSON.stringify(right_summary)
		and JSON.stringify(left_actor) == JSON.stringify(right_actor),
		"same seed and same external simulation action are reproducible"
	)


func _test_actor() -> Dictionary:
	return {
		"id": "test_actor",
		"inventory": {
			"food": 1,
			"spoiled_grain": 0,
		},
		"money": 10.0,
		"traits": [],
		"perception": 5,
		"status_tags": [],
	}


func _find_scene(state: WorldSimState) -> Dictionary:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == SCENE_ID:
			return scene
	return {}


func _candidate_ids(candidates: Array) -> Array[String]:
	var output: Array[String] = []
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		output.append(String(candidate.get("id", "")))
	return output


func _all_candidates_traceable(
		candidates: Array,
		scene: Dictionary
	) -> bool:
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		if String(candidate.get("origin", "")) != "micro_world":
			return false
		if candidate.get("source_fact_ids", []) != scene.get("source_fact_ids", []):
			return false
		if candidate.get("trace_ids", []) != scene.get("trace_ids", []):
			return false
		if String(candidate.get("world_cause", "")) == "":
			return false
	return true


func _remove_trace_type(state: WorldSimState, type_name: String) -> void:
	for index: int in range(state.traces.size() - 1, -1, -1):
		if String(state.traces[index].get("type", "")) == type_name:
			state.traces.remove_at(index)
	for scene_index: int in range(state.narratable_states.size()):
		var scene := state.narratable_states[scene_index]
		var trace_ids := scene.get("trace_ids", []) as Array
		trace_ids.erase("trace_%s" % type_name)
		scene["trace_ids"] = trace_ids
		state.narratable_states[scene_index] = scene


func _changed_category_count(summary: Dictionary) -> int:
	var categories: Array[String] = []
	var changes := summary.get("state_changes", {}) as Dictionary
	for key_value: Variant in changes:
		var key := String(key_value)
		if key.begins_with("chen_mi.") or key.begins_with("old_chen."):
			_add_unique(categories, "npc")
		if "inventory" in key:
			_add_unique(categories, "item")
		if key.begins_with("old_chen_shop."):
			_add_unique(categories, "location")
		if key == "micro_relationships":
			_add_unique(categories, "relationship")
	if not (summary.get("created_memory_ids", []) as Array).is_empty():
		_add_unique(categories, "memory")
	if not (summary.get("created_fact_ids", []) as Array).is_empty():
		_add_unique(categories, "fact")
	if not (summary.get("created_trace_ids", []) as Array).is_empty():
		_add_unique(categories, "trace")
	return categories.size()


func _add_unique(values: Array[String], value: String) -> void:
	if not value in values:
		values.append(value)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[MICRO ACTION RESOLVER PASS] " + message)
	else:
		failures.append(message)
