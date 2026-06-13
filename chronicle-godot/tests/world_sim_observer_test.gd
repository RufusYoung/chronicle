extends SceneTree

const ObserverModel = preload("res://scripts/dev/world_sim_observer.gd")
const OUTPUT_PATH := "res://texts/reports/2026/2026-06-13_world_sim_observer_output.md"
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
	var baseline := observer.run_baseline(30)
	var test_injection := observer.run_with_test_injection(30, 3)
	var comparison := observer.compare_runs(baseline, test_injection)
	observer.export_markdown_report(
		{
			"baseline": baseline,
			"test_injection": test_injection,
			"comparison": comparison,
		},
		OUTPUT_PATH
	)
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
		print("[WORLD SIM OBSERVER RESULT] FAIL: %s" % failures)
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


func _markdown_has_required_sections() -> bool:
	var text := FileAccess.get_file_as_string(OUTPUT_PATH)
	for heading: String in [
		"# world_sim 观察输出",
		"## 1. 运行设置",
		"## 2. 无模拟干预 30 天总览",
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
