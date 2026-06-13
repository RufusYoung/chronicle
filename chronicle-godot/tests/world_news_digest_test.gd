extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const PlayerActionsModel = preload("res://scripts/sim/player_world_actions.gd")
const DigestModel = preload("res://scripts/sim/world_news_digest.gd")
const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const PRE_DIGEST_BASELINE_NEWS_COUNT := 98

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator := SimulatorModel.new()
	var baseline := simulator.load_seed(SEED_PATH)
	var test_injection := simulator.load_seed(SEED_PATH)
	if baseline == null or test_injection == null:
		push_error("[WORLD NEWS DIGEST RESULT] FAIL: seed loading failed")
		quit(1)
		return

	simulator.advance_days(baseline, 30)
	for _index: int in range(30):
		simulator.advance_one_day(test_injection)
		if test_injection.day == 3:
			PlayerActionsModel.new().help_faction(
				test_injection,
				"wardens",
				"border_town"
			)

	var digest := DigestModel.new()
	var continuous := digest.build_continuous_summaries(baseline, 3)
	var repeated_text_count := _repeated_text_count(baseline)
	var repetition_rate := (
		float(repeated_text_count) / float(maxi(baseline.world_news.size(), 1))
	)

	_check(
		_macro_fact_count(baseline) == 192,
		"baseline macro WorldFact count remains complete at 192"
	)
	_check(
		_macro_fact_count(test_injection) == 202,
		"test injection macro WorldFact count remains complete at 202"
	)
	_check(
		baseline.world_news.size() < PRE_DIGEST_BASELINE_NEWS_COUNT,
		"WorldNews count is lower than the pre-digest baseline"
	)
	_check(
		baseline.world_news.size() <= 50,
		"30-day baseline WorldNews count is substantially reduced"
	)
	_check(
		repetition_rate <= 0.15,
		"exact WorldNews text repetition rate is at most 15 percent"
	)
	_check(
		_no_daily_same_key_repeats(baseline),
		"the same news_key is not published on consecutive days"
	)
	_check(
		_history_count_for_action(baseline, "raid_supplies") >= 20,
		"raid_supplies history continues accumulating during cooldown"
	)
	_check(
		_history_count_for_action(baseline, "suppress_smugglers") >= 10,
		"suppress_smugglers history continues accumulating during cooldown"
	)
	_check(
		_history_count_for_action(baseline, "harvest_herbs") >= 5,
		"harvest_herbs history continues accumulating during cooldown"
	)
	_check(
		_stage_news_action_count(baseline) >= 3,
		"at least three repeated action types produce staged news"
	)
	_check(
		_has_region_tag_news(baseline),
		"region tag changes still produce immediate WorldNews"
	)
	_check(
		not continuous.is_empty(),
		"continuous event summaries are available"
	)
	_check(
		_news_signatures(baseline) != _news_signatures(test_injection),
		"day 3 test injection still changes WorldNews output"
	)
	_check(
		_region_snapshots_differ(baseline, test_injection),
		"day 3 test injection still changes final region state"
	)

	print(
		"[WORLD NEWS DIGEST SUMMARY] facts=%d news=%d previous_news=%d histories=%d repeated_texts=%d repetition_rate=%.3f"
		% [
			baseline.world_facts.size(),
			baseline.world_news.size(),
			PRE_DIGEST_BASELINE_NEWS_COUNT,
			baseline.news_history.size(),
			repeated_text_count,
			repetition_rate,
		]
	)
	for summary_value: Variant in continuous:
		var summary := summary_value as Dictionary
		print(
			"[WORLD NEWS CONTINUOUS] %s | count=%d stage=%d | %s"
			% [
				summary.get("action_type", ""),
				int(summary.get("count", 0)),
				int(summary.get("stage", 0)),
				summary.get("summary", ""),
			]
		)
	for news in baseline.world_news:
		if news.stage >= 2:
			print(
				"[WORLD NEWS STAGE] day=%d key=%s count=%d stage=%d | %s"
				% [
					news.day,
					news.news_key,
					news.occurrence_count,
					news.stage,
					news.summary,
				]
			)

	if failures.is_empty():
		print("[WORLD NEWS DIGEST RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[WORLD NEWS DIGEST FAIL] " + failure)
		print("[WORLD NEWS DIGEST RESULT] FAIL: %s" % failures)
		quit(1)


func _repeated_text_count(state: WorldSimState) -> int:
	var counts: Dictionary = {}
	for news in state.world_news:
		counts[news.summary] = int(counts.get(news.summary, 0)) + 1
	var repeated := 0
	for count_value: Variant in counts.values():
		repeated += maxi(int(count_value) - 1, 0)
	return repeated


func _macro_fact_count(state: WorldSimState) -> int:
	var count := 0
	for fact in state.world_facts:
		if String(fact.data.get("scope", "")) != "micro":
			count += 1
	return count


func _no_daily_same_key_repeats(state: WorldSimState) -> bool:
	var last_day_by_key: Dictionary = {}
	for news in state.world_news:
		if news.news_key == "":
			continue
		var last_day := int(last_day_by_key.get(news.news_key, -999))
		if news.day - last_day <= 1:
			return false
		last_day_by_key[news.news_key] = news.day
	return true


func _history_count_for_action(state: WorldSimState, action_type: String) -> int:
	var total := 0
	for history_value: Variant in state.news_history.values():
		var history := history_value as Dictionary
		if String(history.get("action_type", "")) == action_type:
			total += int(history.get("count", 0))
	return total


func _stage_news_action_count(state: WorldSimState) -> int:
	var action_types: Dictionary = {}
	for news in state.world_news:
		if news.stage < 2:
			continue
		var parts := news.news_key.split("|")
		if parts.size() >= 3:
			action_types[String(parts[2])] = true
	return action_types.size()


func _has_region_tag_news(state: WorldSimState) -> bool:
	for news in state.world_news:
		if news.world_cause == "region_tags_changed":
			return true
	return false


func _news_signatures(state: WorldSimState) -> Array[String]:
	var output: Array[String] = []
	for news in state.world_news:
		output.append(
			"%d|%s|%d|%s"
			% [news.day, news.news_key, news.stage, news.summary]
		)
	return output


func _region_snapshots_differ(
		left: WorldSimState,
		right: WorldSimState
	) -> bool:
	return left.snapshot().get("regions", {}) != right.snapshot().get("regions", {})


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[WORLD NEWS DIGEST PASS] " + message)
	else:
		failures.append(message)
