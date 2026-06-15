extends SceneTree

const RunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)
const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const ProfileModel = preload("res://scripts/sim/lake_town_seed_profile.gd")

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_lake_town_history_variation_output.md"
)
const ALTERNATIVE_PATH_TYPES: Array[String] = [
	"ma_shen_helped_before_theft",
	"old_chen_bought_food_on_credit",
	"chen_mi_found_empty_granary",
	"guard_locked_abandoned_granary",
	"creditor_pressed_before_theft",
	"chen_mi_endured_hunger",
	"other_family_took_granary_grain",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var runner := RunnerModel.new()
	var batch := runner.run_batch()
	runner.export_markdown_report(batch, OUTPUT_PATH)
	var runs := batch.get("runs", []) as Array

	var same_left := runner.run_seed(2026061501, 30)
	var same_right := runner.run_seed(2026061501, 30)
	_check(
		same_left.get("signature", {}) == same_right.get("signature", {})
		and same_left.get("signature_hash", "")
		== same_right.get("signature_hash", ""),
		"1. same seed reruns produce identical HistorySignature"
	)
	_check(
		runs.size() >= 20 and _all_runs_reached_day(runs, 30),
		"2. at least 20 seeds run for 30 days"
	)
	_check(
		int(batch.get("outcome_class_count", 0)) >= 5,
		"3. at least five outcome classes appear"
	)
	_check(
		int(batch.get("unique_signature_count", 0)) >= 8,
		"4. at least eight unique history signatures appear"
	)
	_check(
		int(batch.get("theft_count", 0)) < runs.size(),
		"5. spoiled-grain taking does not occur for every seed"
	)
	_check(
		int(batch.get("theft_count", 0)) > 0,
		"6. spoiled-grain taking occurs for at least one seed"
	)
	_check(
		_unique_day_count(
			runs,
			["old_chen_closed_shop_due_to_family_crisis"]
		) >= 2,
		"7. Old Chen shop closure days vary"
	)
	_check(
		_unique_day_count(
			runs,
			[
				"ma_shen_brought_porridge",
				"ma_shen_helped_before_theft",
			]
		) >= 2,
		"8. Ma Shen intervention days vary"
	)
	_check(
		_unique_day_count(
			runs,
			[
				"creditor_left_debt_notice",
				"creditor_pressed_before_theft",
			]
		) >= 2,
		"9. creditor pressure days vary"
	)
	_check(
		int(batch.get("alternative_seed_count", 0)) >= 3,
		"10. at least three seeds enter an alternative path"
	)
	_check(
		_alternative_paths_are_world_facts(runs),
		"11. alternative paths are proved by WorldFact"
	)

	var simulator := SimulatorModel.new()
	var profile_model := ProfileModel.new()
	var profile_state: WorldSimState = simulator.load_seed(SEED_PATH)
	var fact_count_before := profile_state.world_facts.size()
	var profile := profile_model.build_profile(2026061599)
	profile_model.apply_profile_to_state(profile_state, profile)
	_check(
		profile_state.world_facts.size() == fact_count_before
		and not _profile_contains_outcome_fact(profile),
		"12. SeedProfile writes initial state but no outcome fact"
	)
	_check(
		_all_alternative_facts_have_causes(runs),
		"13. every alternative WorldFact has cause_fact_ids"
	)
	_check(
		_all_alternative_traces_have_sources(runs),
		"14. every alternative Trace has source_fact_id"
	)

	var missing_map := runner.build_fact_day_map(profile_state)
	_check(
		int(missing_map.get("chen_mi_took_spoiled_grain", 0)) == -1
		and int(
			missing_map.get("ma_shen_helped_before_theft", 0)
		) == -1,
		"15. missing facts use -1 in the history signature"
	)
	var synthetic_days: Dictionary = {}
	for type_name: String in RunnerModel.SIGNATURE_FACT_TYPES:
		synthetic_days[type_name] = -1
	synthetic_days["ma_shen_helped_before_theft"] = 3
	var synthetic_signature := {"fact_days": synthetic_days}
	_check(
		runner.classify_history_outcome(synthetic_signature)
		== "early_neighbor_help_no_theft",
		"16. outcome classification is derived from fact combinations"
	)

	var output_text := FileAccess.get_file_as_string(OUTPUT_PATH)
	_check(
		FileAccess.file_exists(OUTPUT_PATH)
		and "## 湖湾镇多 seed 历史差异摘要" in output_text,
		"17. multi-seed output exists with the required heading"
	)
	var samples_text := output_text.get_slice(
		"## 湖湾镇历史样例",
		1
	)
	_check(
		samples_text.count("### Seed") >= 5,
		"18. multi-seed output shows at least five seed histories"
	)

	print(
		"[LAKE TOWN HISTORY VARIATION SUMMARY] seeds=%d unique=%d classes=%d theft=%d no_theft=%d alternatives=%d outcomes=%s close=%s ma=%s creditor=%s"
		% [
			int(batch.get("seed_count", 0)),
			int(batch.get("unique_signature_count", 0)),
			int(batch.get("outcome_class_count", 0)),
			int(batch.get("theft_count", 0)),
			int(batch.get("no_theft_count", 0)),
			int(batch.get("alternative_seed_count", 0)),
			JSON.stringify(batch.get("outcome_counts", {})),
			JSON.stringify(batch.get("close_day_range", {})),
			JSON.stringify(batch.get("ma_intervention_day_range", {})),
			JSON.stringify(batch.get("creditor_day_range", {})),
		]
	)
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		var signature := run.get("signature", {}) as Dictionary
		print(
			"[LAKE TOWN HISTORY SEED] seed=%d outcome=%s hash=%s facts=%s"
			% [
				int(run.get("seed", 0)),
				signature.get("outcome_class", ""),
				run.get("signature_hash", ""),
				JSON.stringify(signature.get("fact_days", {})),
			]
		)

	if failures.is_empty():
		print("[LAKE TOWN HISTORY VARIATION RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN HISTORY VARIATION FAIL] " + failure)
		print(
			"[LAKE TOWN HISTORY VARIATION RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _all_runs_reached_day(runs: Array, expected_day: int) -> bool:
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		var state := run.get("state") as WorldSimState
		if state == null or state.day != expected_day:
			return false
	return true


func _unique_day_count(runs: Array, fact_types: Array) -> int:
	var unique: Dictionary = {}
	for run_value: Variant in runs:
		var signature := (
			(run_value as Dictionary).get("signature", {})
			as Dictionary
		)
		var fact_days := signature.get("fact_days", {}) as Dictionary
		var earliest := -1
		for fact_type_value: Variant in fact_types:
			var day := int(
				fact_days.get(String(fact_type_value), -1)
			)
			if day >= 0 and (earliest < 0 or day < earliest):
				earliest = day
		if earliest >= 0:
			unique[earliest] = true
	return unique.size()


func _alternative_paths_are_world_facts(runs: Array) -> bool:
	var found := 0
	for run_value: Variant in runs:
		var state := (run_value as Dictionary).get("state") as WorldSimState
		for fact in state.world_facts:
			if fact.type in ALTERNATIVE_PATH_TYPES:
				found += 1
	return found >= 3


func _profile_contains_outcome_fact(profile: Dictionary) -> bool:
	var profile_text := JSON.stringify(profile)
	for type_name: String in ALTERNATIVE_PATH_TYPES:
		if type_name in profile_text:
			return true
	return false


func _all_alternative_facts_have_causes(runs: Array) -> bool:
	var found := 0
	for run_value: Variant in runs:
		var state := (run_value as Dictionary).get("state") as WorldSimState
		for fact in state.world_facts:
			if fact.type not in ALTERNATIVE_PATH_TYPES:
				continue
			found += 1
			if fact.cause_fact_ids.is_empty():
				return false
	return found >= 3


func _all_alternative_traces_have_sources(runs: Array) -> bool:
	var alternative_fact_ids: Dictionary = {}
	for run_value: Variant in runs:
		var state := (run_value as Dictionary).get("state") as WorldSimState
		for fact in state.world_facts:
			if fact.type in ALTERNATIVE_PATH_TYPES:
				alternative_fact_ids[fact.id] = true
	var found := 0
	for run_value: Variant in runs:
		var state := (run_value as Dictionary).get("state") as WorldSimState
		for trace_value: Variant in state.traces:
			var trace := trace_value as Dictionary
			var source_id := String(trace.get("source_fact_id", ""))
			if not alternative_fact_ids.has(source_id):
				continue
			found += 1
			if source_id == "":
				return false
	return found >= 3


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN HISTORY VARIATION PASS] " + message)
	else:
		failures.append(message)
