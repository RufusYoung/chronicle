extends SceneTree

const ObserverModel = preload("res://scripts/dev/world_sim_observer.gd")
const OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_world_sim_observer_output.md"
)
const PROTECTED_PATHS: Array[String] = [
	"res://scenes/ui/story_player.gd",
	"res://scripts/gen/world_generation_v03.gd",
	"res://scenes/ui/mainui.tscn",
	"res://project.godot",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var protected_before := _read_protected_files()
	var observer := ObserverModel.new()
	print("[WORLD SIM OBSERVER TEST] baseline start")
	var baseline := observer.run_baseline(30)
	print("[WORLD SIM OBSERVER TEST] baseline complete")
	var test_injection := observer.run_with_test_injection(30, 3)
	print("[WORLD SIM OBSERVER TEST] test injection complete")
	var comparison := observer.compare_runs(baseline, test_injection)
	print("[WORLD SIM OBSERVER TEST] comparison complete")
	observer.export_markdown_report(
		{
			"baseline": baseline,
			"test_injection": test_injection,
			"comparison": comparison,
		},
		OUTPUT_PATH
	)
	print("[WORLD SIM OBSERVER TEST] Markdown export complete")
	var protected_after := _read_protected_files()

	_check(not baseline.is_empty(), "baseline observation completed")
	_check(not test_injection.is_empty(), "test injection observation completed")
	_check(
		(baseline.get("daily_snapshots", []) as Array).size() == 30,
		"baseline contains 30 daily snapshots"
	)
	_check(
		(test_injection.get("daily_snapshots", []) as Array).size() == 30,
		"test injection run contains 30 daily snapshots"
	)
	_check(_daily_summaries_exist(baseline), "every baseline day has region and faction summaries")
	_check(_has_daily_news(baseline), "baseline includes world_news summaries")
	_check(_has_continuous_news(baseline), "baseline includes continuous event summaries")
	_check(_has_daily_leads(baseline), "baseline includes LeadCandidate summaries")
	_check(_has_daily_adapted_leads(baseline), "baseline includes adapted v0.3 lead summaries")
	_check(_has_lake_town_chain(baseline), "baseline includes lake town micro chain summaries")
	_check(
		_has_micro_action_candidates(baseline),
		"baseline includes five state-derived lake town action candidates"
	)
	_check(
		_has_micro_action_results(baseline),
		"baseline includes isolated micro action result comparisons"
	)
	_check(
		_has_reaction_timeline(baseline),
		"baseline includes traceable lake town reaction timeline"
	)
	_check(
		_has_micro_action_followups(baseline),
		"baseline includes differentiated three-day action followups"
	)
	_check(
		bool(comparison.get("day_10_has_difference", false)),
		"A/B comparison differs by day 10"
	)
	_check(
		bool(comparison.get("lead_signatures_differ", false)),
		"A/B LeadCandidate signatures differ"
	)
	_check(
		bool(comparison.get("adapted_lead_signatures_differ", false)),
		"A/B adapted lead signatures differ"
	)
	_check(FileAccess.file_exists(OUTPUT_PATH), "Markdown observation output exists")
	_check(_markdown_has_required_sections(), "Markdown observation output has required sections")
	_check(_markdown_has_news_categories(), "Markdown separates new news and continuous summaries")
	_check(_markdown_has_lake_town_chain(), "Markdown includes the lake town micro chain section")
	_check(_markdown_has_traceable_micro_scene(), "Markdown shows the complete micro scene causes")
	_check(
		_markdown_has_micro_action_sections(),
		"Markdown includes micro action candidates and consequence comparisons"
	)
	_check(_observer_news_not_repetitive(baseline), "observer output avoids repeated daily news text")
	_check(_markdown_uses_test_injection_terms(), "Markdown uses test injection terminology")
	_check(protected_before == protected_after, "protected Demo files were not modified")

	_print_summary("BASELINE", baseline)
	_print_summary("TEST INJECTION", test_injection)
	print(
		"[OBSERVER A/B] day10_difference=%s news_delta=%+d leads_delta=%+d adapted_delta=%+d signatures_differ=%s"
		% [
			comparison.get("day_10_has_difference", false),
			int(comparison.get("world_news_delta", 0)),
			int(comparison.get("lead_candidate_delta", 0)),
			int(comparison.get("adapted_lead_delta", 0)),
			comparison.get("adapted_lead_signatures_differ", false),
		]
	)

	if failures.is_empty():
		print("[WORLD SIM OBSERVER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[WORLD SIM OBSERVER FAIL] " + failure)
		print("[WORLD SIM OBSERVER RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _daily_summaries_exist(result: Dictionary) -> bool:
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		if (snapshot.get("regions", []) as Array).is_empty():
			return false
		if (snapshot.get("factions", []) as Array).is_empty():
			return false
		if not snapshot.has("news") or not snapshot.has("leads"):
			return false
		if not snapshot.has("continuous_news"):
			return false
		if not snapshot.has("adapted_leads"):
			return false
		if not snapshot.has("lake_town"):
			return false
	return true


func _has_daily_news(result: Dictionary) -> bool:
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		if not (snapshot.get("news", []) as Array).is_empty():
			return true
	return false


func _has_continuous_news(result: Dictionary) -> bool:
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		if not (snapshot.get("continuous_news", []) as Array).is_empty():
			return true
	return false


func _has_daily_leads(result: Dictionary) -> bool:
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		if not (snapshot.get("leads", []) as Array).is_empty():
			return true
	return false


func _has_daily_adapted_leads(result: Dictionary) -> bool:
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		if not (snapshot.get("adapted_leads", []) as Array).is_empty():
			return true
	return false


func _has_lake_town_chain(result: Dictionary) -> bool:
	var final_summary := result.get("lake_town_final", {}) as Dictionary
	if final_summary.is_empty():
		return false
	for scene_value: Variant in final_summary.get("narratable_states", []):
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == "chen_mi_hiding_spoiled_grain_scene":
			return (
				not (scene.get("source_fact_ids", []) as Array).is_empty()
				and not (scene.get("trace_ids", []) as Array).is_empty()
			)
	return false


func _has_micro_action_candidates(result: Dictionary) -> bool:
	var candidates := result.get("micro_action_candidates", []) as Array
	var ids: Array[String] = []
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		ids.append(String(candidate.get("id", "")))
	return ids == [
		"give_food_to_chen_mi",
		"ask_grain_origin",
		"report_to_guard",
		"ignore_chen_mi",
		"buy_spoiled_grain_low",
	]


func _has_micro_action_results(result: Dictionary) -> bool:
	var action_results := result.get("micro_action_results", []) as Array
	if action_results.size() != 5:
		return false
	for result_value: Variant in action_results:
		var action_result := result_value as Dictionary
		if not bool(action_result.get("ok", false)):
			return false
		if (action_result.get("created_fact_types", []) as Array).is_empty():
			return false
		if (action_result.get("state_changes", {}) as Dictionary).is_empty():
			return false
	return true


func _has_reaction_timeline(result: Dictionary) -> bool:
	var timeline := result.get("lake_town_reaction_timeline", []) as Array
	if timeline.size() < 2:
		return false
	var fact_types: Array[String] = []
	for entry_value: Variant in timeline:
		var entry := entry_value as Dictionary
		if (entry.get("cause_fact_ids", []) as Array).is_empty():
			return false
		if (entry.get("trace_types", []) as Array).is_empty():
			return false
		if (entry.get("memory_types", []) as Array).is_empty():
			return false
		fact_types.append(String(entry.get("fact_type", "")))
	return (
		"chen_mi_ate_spoiled_grain" in fact_types
		and "ma_shen_noticed_closed_shop" in fact_types
	)


func _has_micro_action_followups(result: Dictionary) -> bool:
	var followups := result.get("micro_action_followups", []) as Array
	if followups.size() != 5:
		return false
	var by_action: Dictionary = {}
	for followup_value: Variant in followups:
		var followup := followup_value as Dictionary
		by_action[String(followup.get("action_id", ""))] = followup
	for action_id: String in [
		"give_food_to_chen_mi",
		"ignore_chen_mi",
		"report_to_guard",
		"buy_spoiled_grain_low",
	]:
		if not by_action.has(action_id):
			return false
	var give := by_action["give_food_to_chen_mi"] as Dictionary
	var ignore := by_action["ignore_chen_mi"] as Dictionary
	var report := by_action["report_to_guard"] as Dictionary
	var buy := by_action["buy_spoiled_grain_low"] as Dictionary
	var give_facts := give.get("new_fact_types", []) as Array
	var ignore_facts := ignore.get("new_fact_types", []) as Array
	var report_facts := report.get("new_fact_types", []) as Array
	var buy_facts := buy.get("new_fact_types", []) as Array
	var buy_chen_mi := buy.get("chen_mi", {}) as Dictionary
	return (
		not "chen_mi_ate_spoiled_grain" in give_facts
		and "chen_mi_ate_spoiled_grain" in ignore_facts
		and "chen_mi_fell_sick_from_spoiled_grain" in ignore_facts
		and "guard_checked_old_chen_shop" in report_facts
		and not "chen_mi_ate_spoiled_grain" in buy_facts
		and (buy_chen_mi.get("inventory", []) as Array).is_empty()
	)


func _markdown_has_required_sections() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	for heading: String in [
		"# world_sim 观察输出",
		"## 1. 运行设置",
		"## 2. 无模拟干预 30 天总览",
		"## 湖湾镇微观链观察",
		"## 湖湾镇微观后续反应时间线",
		"## 外部模拟行动后三日后续分支",
		"## 3. 每日摘要",
		"### Day 1",
		"### Day 30",
		"## 4. 第 3 天测试注入后 30 天总览",
		"## 5. A/B 差异",
		"## 6. 适配后线索样例",
		"## 7. 结论",
	]:
		if not heading in text:
			return false
	return true


func _markdown_has_news_categories() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	return "当天新新闻：" in text and "连续事件摘要：" in text


func _markdown_has_lake_town_chain() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	return (
		"湖湾镇微观链：" in text
		and "湖湾镇新增基础事实：" in text
		and "湖湾镇新增基础痕迹：" in text
		and "湖湾镇基础可叙述状态：" in text
	)


func _markdown_has_traceable_micro_scene() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	return (
		"陈米藏着一袋发霉麦子" in text
		and "lake_town_food_price_rising" in text
		and "chen_mi_took_spoiled_grain" in text
		and "old_chen_closed_shop_due_to_family_crisis" in text
		and "child_hiding_bag" in text
		and "spoiled_grain_bag" in text
	)


func _markdown_has_micro_action_sections() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	return (
		"湖湾镇可行动候选：" in text
		and "## 湖湾镇模拟行动后果对照" in text
		and "## 外部模拟行动后三日后续分支" in text
		and "### give_food_to_chen_mi" in text
		and "### ask_grain_origin" in text
		and "### report_to_guard" in text
		and "### ignore_chen_mi" in text
		and "### buy_spoiled_grain_low" in text
		and "无头模拟行动" in text
		and "不是真实 UI 输入" in text
		and "guard_checked_old_chen_shop" in text
	)


func _observer_news_not_repetitive(result: Dictionary) -> bool:
	var counts: Dictionary = {}
	var total := 0
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		for news_value: Variant in snapshot.get("news", []):
			var news := news_value as Dictionary
			var summary := String(news.get("summary", ""))
			counts[summary] = int(counts.get(summary, 0)) + 1
			total += 1
	var repeated := 0
	for count_value: Variant in counts.values():
		repeated += maxi(int(count_value) - 1, 0)
	return float(repeated) / float(maxi(total, 1)) <= 0.15


func _markdown_uses_test_injection_terms() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	for forbidden: String in ["玩家选择", "玩家行为", "玩家干预"]:
		if forbidden in text:
			return false
	return "测试注入" in text and "模拟干预" in text


func _read_protected_files() -> Dictionary:
	var output: Dictionary = {}
	for path: String in PROTECTED_PATHS:
		output[path] = FileAccess.get_file_as_bytes(path)
	return output


func _print_summary(label: String, result: Dictionary) -> void:
	var totals := result.get("totals", {}) as Dictionary
	print(
		"[OBSERVER %s] facts=%d news=%d histories=%d candidates=%d adapted=%d types=%s"
		% [
			label,
			int(totals.get("world_facts", 0)),
			int(totals.get("world_news", 0)),
			int(totals.get("news_history", 0)),
			int(totals.get("lead_candidates", 0)),
			int(totals.get("adapted_leads", 0)),
			JSON.stringify(result.get("lead_type_distribution", {})),
		]
	)
	for region_value: Variant in result.get("final_regions", []):
		var region := region_value as Dictionary
		print(
			"[OBSERVER %s REGION] %s danger=%.2f order=%.2f scarcity=%.2f mystic=%.2f food=%.2f tags=%s"
			% [
				label,
				region.get("id", ""),
				float(region.get("danger", 0.0)),
				float(region.get("order", 0.0)),
				float(region.get("scarcity", 0.0)),
				float(region.get("mystic", 0.0)),
				float(region.get("food", 0.0)),
				", ".join(region.get("tags", [])),
			]
		)
	for faction_value: Variant in result.get("final_factions", []):
		var faction := faction_value as Dictionary
		print(
			"[OBSERVER %s FACTION] %s power=%.2f wealth=%.2f hostility=%.2f"
			% [
				label,
				faction.get("id", ""),
				float(faction.get("power", 0.0)),
				float(faction.get("wealth", 0.0)),
				float(faction.get("hostility_to_player", 0.0)),
			]
		)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[WORLD SIM OBSERVER PASS] " + message)
	else:
		failures.append(message)
