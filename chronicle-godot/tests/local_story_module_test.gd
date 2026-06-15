extends SceneTree

const RunnerModel = preload(
	"res://scripts/dev/local_story_module_runner.gd"
)
const RegionSimProfileModel = preload(
	"res://scripts/sim/region_sim_profile.gd"
)
const LegacyRunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)

const SCENE_ID := "chen_mi_hiding_spoiled_grain_scene"
const PROTECTED_STORY_PLAYER := (
	"chronicle-godot/scenes/ui/story_player.gd"
)
const PROTECTED_WORLD_GENERATION := (
	"chronicle-godot/scripts/gen/world_generation_v03.gd"
)
const REGRESSION_SCRIPTS: Array[String] = [
	"res://tests/lake_town_hunger_closure_test.gd",
	"res://tests/lake_town_branch_closure_test.gd",
	"res://tests/lake_town_history_variation_test.gd",
	"res://tests/lake_town_recovery_system_test.gd",
	"res://tests/lake_town_reaction_system_test.gd",
	"res://tests/micro_action_resolver_test.gd",
	"res://tests/lake_town_food_chain_test.gd",
	"res://tests/world_sim_observer_test.gd",
	"res://tests/world_news_digest_test.gd",
	"res://tests/world_sim_lead_adapter_test.gd",
	"res://scripts/sim/world_sim_debug_runner.gd",
	"res://tests/project_cleanup_smoke.gd",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var runner := RunnerModel.new()
	var module := runner.module
	var pipeline := runner.pipeline
	var region_profile := RegionSimProfileModel.new()
	var description: Dictionary = module.describe_module()

	_check(
		module.get_module_id() == "lake_town_food_crisis",
		"1. lake town module returns the expected module_id"
	)
	_check(
		_description_is_complete(description),
		"2. module description includes locations, NPCs, pressures, and outputs"
	)

	var seed_profile := (
		region_profile.lake_town_seed_profile.build_profile(
			2026061501
		)
	)
	var wrapped_profile := (
		region_profile.wrap_lake_town_seed_profile(seed_profile)
	)
	_check(
		_profile_wrap_is_complete(wrapped_profile),
		"3. RegionSimProfile wraps lake_town_seed_profile"
	)

	var profile_state: WorldSimState = (
		module.create_state_for_seed(2026061501)
	)
	var fact_count_before := profile_state.world_facts.size()
	module.initialize_module_state(profile_state, wrapped_profile)
	_check(
		profile_state.world_facts.size() == fact_count_before
		and not "WorldFact" in JSON.stringify(wrapped_profile)
		and not wrapped_profile.has("outcome_class"),
		"4. RegionSimProfile writes conditions without creating WorldFact"
	)

	var module_batch := runner.run_batch(
		LegacyRunnerModel.DEFAULT_SEEDS,
		30
	)
	var runs := module_batch.get("runs", []) as Array
	_check(
		runs.size() >= 20 and _all_runs_reached_day(runs, 30),
		"5. LocalStoryPipeline runs the lake town module for 30 days"
	)
	_check(
		int(module_batch.get("world_fact_count", 0)) > 0
		and int(module_batch.get("trace_count", 0)) > 0
		and int(module_batch.get("memory_count", 0)) > 0
		and int(module_batch.get("narratable_state_count", 0)) > 0,
		"6. pipeline results include facts, traces, memories, and narratable states"
	)
	_check(
		int(module_batch.get("seed_count", 0)) >= 20,
		"7. pipeline runs at least 20 seeds"
	)

	var same_left := runner.run_seed(2026061501, 30)
	var same_right := runner.run_seed(2026061501, 30)
	_check(
		same_left.get("signature", {}) == same_right.get("signature", {})
		and same_left.get("signature_hash", "")
		== same_right.get("signature_hash", "")
		and bool(module_batch.get("all_reproducible", false)),
		"8. same-seed reproducibility remains stable"
	)
	_check(
		int(module_batch.get("unique_signature_count", 0)) >= 8,
		"9. different seeds retain meaningful history variation"
	)
	_check(
		int(
			module_batch.get(
				"unresolved_extreme_hunger_count",
				-1
			)
		) == 0,
		"10. unresolved_extreme_hunger remains zero"
	)
	_check(
		int(module_batch.get("dangling_major_fact_count", -1)) == 0,
		"11. dangling_major_fact remains zero"
	)
	_check(
		int(module_batch.get("impossible_shop_state_count", -1)) == 0,
		"12. impossible_shop_state remains zero"
	)

	var legacy_batch := runner.run_legacy_batch(
		LegacyRunnerModel.DEFAULT_SEEDS,
		30
	)
	var comparison := runner.compare_with_legacy(
		module_batch,
		legacy_batch
	)
	_check(
		bool(comparison.get("matches", false)),
		"13. module wrapper matches legacy runner key statistics"
	)

	var action_state: WorldSimState = (
		module.create_state_for_seed(2026061501)
	)
	pipeline.run_days(action_state, module, 6)
	var actor := _test_actor()
	var candidates: Array = module.build_action_candidates(
		action_state,
		actor,
		SCENE_ID
	)
	_check(
		not candidates.is_empty()
		and "give_food_to_chen_mi" in _candidate_ids(candidates),
		"14. build_action_candidates works through the module interface"
	)
	var action_result: Dictionary = module.resolve_action(
		action_state,
		actor,
		"give_food_to_chen_mi",
		SCENE_ID
	)
	_check(
		bool(action_result.get("ok", false))
		and not (
			action_result.get("created_fact_ids", []) as Array
		).is_empty()
		and not (
			action_result.get("created_trace_ids", []) as Array
		).is_empty()
		and not (
			action_result.get("created_memory_ids", []) as Array
		).is_empty(),
		"15. resolve_action writes a fact, trace, and memory"
	)
	var quality: Dictionary = module.audit_quality(
		action_state,
		module.build_history_signature(action_state)
	)
	_check(
		quality.has("quality_flags")
		and quality.get("quality_flags", []) is Array,
		"16. quality audit returns quality_flags through the module interface"
	)
	_check(
		_runtime_layer_has_no_ui_dependency(),
		"17. LocalStoryModule runtime files do not depend on formal UI"
	)
	_check(
		_git_path_unchanged(PROTECTED_STORY_PLAYER),
		"18. story_player.gd is unchanged"
	)
	_check(
		_git_path_unchanged(PROTECTED_WORLD_GENERATION),
		"19. world_generation_v03.gd is unchanged"
	)

	var regression := _run_regression_suite()
	_check(
		bool(regression.get("all_passed", false)),
		"20. all required regression scripts pass"
	)

	print(
		"[LOCAL STORY MODULE SUMMARY] %s"
		% JSON.stringify(
			runner.build_report_summary(
				module_batch,
				legacy_batch
			)
		)
	)
	if failures.is_empty():
		print("[LOCAL STORY MODULE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LOCAL STORY MODULE FAIL] " + failure)
		print(
			"[LOCAL STORY MODULE RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _description_is_complete(description: Dictionary) -> bool:
	return (
		description.get("locations", []) is Array
		and (description.get("locations", []) as Array).size() >= 4
		and description.get("core_npcs", []) is Array
		and (description.get("core_npcs", []) as Array).size() >= 4
		and description.get("pressure_fields", []) is Array
		and (
			description.get("pressure_fields", []) as Array
		).size() >= 6
		and description.get("supported_outputs", []) is Array
		and "QualityAudit" in (
			description.get("supported_outputs", []) as Array
		)
	)


func _profile_wrap_is_complete(profile: Dictionary) -> bool:
	var required_fields: Array[String] = [
		"profile_id",
		"seed",
		"region_id",
		"module_id",
		"macro_pressure",
		"resources",
		"social_roles",
		"npc_bias",
		"location_bias",
		"external_pressure",
		"quality_targets",
		"legacy_profile",
	]
	for field: String in required_fields:
		if not profile.has(field):
			return false
	return (
		profile.get("module_id", "") == "lake_town_food_crisis"
		and profile.get("region_id", "") == "border_town"
	)


func _all_runs_reached_day(runs: Array, expected_day: int) -> bool:
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		var state := run.get("state") as WorldSimState
		if state == null or state.day != expected_day:
			return false
	return true


func _candidate_ids(candidates: Array) -> Array[String]:
	var output: Array[String] = []
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		output.append(String(candidate.get("id", "")))
	return output


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


func _runtime_layer_has_no_ui_dependency() -> bool:
	var paths: Array[String] = [
		"res://scripts/sim/local_story_module.gd",
		"res://scripts/sim/history_quality_audit.gd",
		"res://scripts/sim/region_sim_profile.gd",
		"res://scripts/sim/local_story_pipeline.gd",
		(
			"res://scripts/sim/modules/"
			+ "lake_town_food_crisis_module.gd"
		),
	]
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path)
		if (
			"scenes/ui" in source
			or "story_player.gd" in source
			or "mainui.tscn" in source
		):
			return false
	return true


func _git_path_unchanged(path: String) -> bool:
	var output: Array = []
	var repository_root := ProjectSettings.globalize_path("res://..")
	var exit_code := OS.execute(
		"git",
		[
			"-C",
			repository_root,
			"diff",
			"--quiet",
			"HEAD",
			"--",
			path,
		],
		output,
		true
	)
	return exit_code == 0


func _run_regression_suite() -> Dictionary:
	var failed_scripts: Array[String] = []
	var project_root := ProjectSettings.globalize_path("res://")
	for script_path: String in REGRESSION_SCRIPTS:
		var output: Array = []
		var exit_code := OS.execute(
			OS.get_executable_path(),
			[
				"--headless",
				"--path",
				project_root,
				"--script",
				script_path,
			],
			output,
			true
		)
		if exit_code != 0:
			failed_scripts.append(script_path)
			print(
				"[LOCAL STORY MODULE REGRESSION FAIL] %s %s"
				% [script_path, "\n".join(output)]
			)
		else:
			print(
				"[LOCAL STORY MODULE REGRESSION PASS] %s"
				% script_path
			)
	return {
		"all_passed": failed_scripts.is_empty(),
		"failed_scripts": failed_scripts,
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LOCAL STORY MODULE PASS] " + message)
	else:
		failures.append(message)
