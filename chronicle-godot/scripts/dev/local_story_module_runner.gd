extends RefCounted
class_name LocalStoryModuleRunner

const LocalStoryPipelineModel = preload(
	"res://scripts/sim/local_story_pipeline.gd"
)
const LakeTownModuleModel = preload(
	"res://scripts/sim/modules/lake_town_food_crisis_module.gd"
)
const LegacyRunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)

var pipeline := LocalStoryPipelineModel.new()
var module := LakeTownModuleModel.new()
var legacy_runner := LegacyRunnerModel.new()


func run_seed(seed_value: int, days: int = 30) -> Dictionary:
	var state: Variant = module.create_state_for_seed(seed_value)
	return pipeline.run_days(
		state,
		module,
		days,
		module.build_profile_for_seed(seed_value)
	)


func run_batch(
		seeds: Array = LegacyRunnerModel.DEFAULT_SEEDS,
		days: int = 30
	) -> Dictionary:
	return pipeline.run_seed_batch(module, seeds, days)


func run_legacy_batch(
		seeds: Array = LegacyRunnerModel.DEFAULT_SEEDS,
		days: int = 30
	) -> Dictionary:
	return legacy_runner.run_batch(seeds, days)


func compare_with_legacy(
		module_batch: Dictionary,
		legacy_batch: Dictionary
	) -> Dictionary:
	var legacy_quality := (
		legacy_batch.get("quality_audit", {}) as Dictionary
	)
	var comparisons := {
		"seed_count": (
			module_batch.get("seed_count", 0)
			== legacy_batch.get("seed_count", 0)
		),
		"unique_signature_count": (
			module_batch.get("unique_signature_count", 0)
			== legacy_batch.get("unique_signature_count", 0)
		),
		"outcome_counts": (
			module_batch.get("outcome_counts", {})
			== legacy_batch.get("outcome_counts", {})
		),
		"all_reproducible": (
			module_batch.get("all_reproducible", false)
			== legacy_batch.get("all_reproducible", false)
		),
		"unresolved_extreme_hunger_count": (
			module_batch.get(
				"unresolved_extreme_hunger_count",
				-1
			)
			== legacy_quality.get(
				"unresolved_extreme_hunger_count",
				-2
			)
		),
		"dangling_major_fact_count": (
			module_batch.get("dangling_major_fact_count", -1)
			== legacy_quality.get("dangling_major_fact_count", -2)
		),
		"impossible_shop_state_count": (
			module_batch.get("impossible_shop_state_count", -1)
			== legacy_quality.get(
				"impossible_shop_state_count",
				-2
			)
		),
	}
	var differences: Array[String] = []
	for key: String in comparisons:
		if not bool(comparisons[key]):
			differences.append(key)
	return {
		"matches": differences.is_empty(),
		"comparisons": comparisons,
		"differences": differences,
	}


func build_report_summary(
		module_batch: Dictionary,
		legacy_batch: Dictionary
	) -> Dictionary:
	return {
		"module_id": module.get_module_id(),
		"module_version": module.get_module_version(),
		"seed_count": int(module_batch.get("seed_count", 0)),
		"days": int(module_batch.get("days", 0)),
		"unique_signature_count": int(
			module_batch.get("unique_signature_count", 0)
		),
		"outcome_counts": (
			module_batch.get("outcome_counts", {}) as Dictionary
		).duplicate(true),
		"unresolved_extreme_hunger_count": int(
			module_batch.get(
				"unresolved_extreme_hunger_count",
				0
			)
		),
		"dangling_major_fact_count": int(
			module_batch.get("dangling_major_fact_count", 0)
		),
		"impossible_shop_state_count": int(
			module_batch.get("impossible_shop_state_count", 0)
		),
		"legacy_comparison": compare_with_legacy(
			module_batch,
			legacy_batch
		),
	}
