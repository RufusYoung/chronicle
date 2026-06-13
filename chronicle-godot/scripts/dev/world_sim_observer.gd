extends RefCounted
class_name WorldSimObserver

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const PlayerActionsModel = preload("res://scripts/sim/player_world_actions.gd")
const AdapterModel = preload("res://scripts/sim/world_sim_lead_adapter.gd")

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const REGION_METRICS: Array[String] = [
	"danger",
	"order",
	"scarcity",
	"mystic",
	"food",
	"herbs",
	"relics",
	"information",
]
const FACTION_METRICS: Array[String] = [
	"power",
	"wealth",
	"hostility_to_player",
]

var simulator := SimulatorModel.new()
var player_actions := PlayerActionsModel.new()
var adapter := AdapterModel.new()


func run_baseline(days: int = 30) -> Dictionary:
	return _run_observation(days, -1)


func run_with_test_injection(days: int = 30, injection_day: int = 3) -> Dictionary:
	return _run_observation(days, injection_day)


func build_daily_snapshot(state: Variant) -> Dictionary:
	var day := _state_day(state)
	var news := build_news_summary(state, day)
	var leads := build_lead_summary(state, day)
	var adapted_leads := build_adapted_lead_summary(state, day)
	return {
		"day": day,
		"regions": build_region_summary(state),
		"factions": build_faction_summary(state),
		"news": news,
		"leads": leads,
		"adapted_leads": adapted_leads,
		"news_signatures": _news_summary_signatures(news),
		"lead_signatures": _lead_summary_signatures(leads),
		"adapted_lead_signatures": _adapted_summary_signatures(adapted_leads),
	}


func build_region_summary(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if state is WorldSimState:
		var region_ids: Array = state.regions.keys()
		region_ids.sort()
		for region_id: String in region_ids:
			var region: WorldSimState.RegionState = state.get_region(region_id)
			output.append({
				"id": region.id,
				"name": region.name,
				"danger": _round(region.danger),
				"order": _round(region.order),
				"scarcity": _round(region.scarcity),
				"mystic": _round(region.mystic),
				"food": _round(region.food),
				"herbs": _round(region.herbs),
				"relics": _round(region.relics),
				"information": _round(region.information),
				"tags": region.tags.duplicate(),
			})
		return output

	if state is Dictionary:
		var regions := state.get("regions", {}) as Dictionary
		var region_ids: Array = regions.keys()
		region_ids.sort()
		for region_id: String in region_ids:
			var region := regions.get(region_id, {}) as Dictionary
			var summary: Dictionary = {
				"id": region_id,
				"name": String(region.get("name", region_id)),
				"tags": (region.get("tags", []) as Array).duplicate(),
			}
			for metric: String in REGION_METRICS:
				summary[metric] = _round(float(region.get(metric, 0.0)))
			output.append(summary)
	return output


func build_faction_summary(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if state is WorldSimState:
		var faction_ids: Array = state.factions.keys()
		faction_ids.sort()
		for faction_id: String in faction_ids:
			var faction: WorldSimState.FactionState = state.get_faction(faction_id)
			output.append({
				"id": faction.id,
				"name": faction.name,
				"power": _round(faction.power),
				"wealth": _round(faction.wealth),
				"hostility_to_player": _round(faction.hostility_to_player),
				"goal": faction.goal,
			})
		return output

	if state is Dictionary:
		var factions := state.get("factions", {}) as Dictionary
		var faction_ids: Array = factions.keys()
		faction_ids.sort()
		for faction_id: String in faction_ids:
			var faction := factions.get(faction_id, {}) as Dictionary
			output.append({
				"id": faction_id,
				"name": String(faction.get("name", faction_id)),
				"power": _round(float(faction.get("power", 0.0))),
				"wealth": _round(float(faction.get("wealth", 0.0))),
				"hostility_to_player": _round(
					float(faction.get("hostility_to_player", 0.0))
				),
				"goal": String(faction.get("goal", "")),
			})
	return output


func build_news_summary(state: Variant, day: int) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	for news in state.world_news:
		if news.day != day:
			continue
		output.append({
			"id": news.id,
			"day": news.day,
			"region_id": news.region_id,
			"source": news.source,
			"summary": news.summary,
			"truth_level": _round(news.truth_level),
			"related_fact_id": news.related_fact_id,
		})
	return output


func build_lead_summary(state: Variant, day: int) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	for lead in state.lead_candidates:
		if lead.day != day:
			continue
		output.append({
			"id": lead.id,
			"day": lead.day,
			"type": lead.type,
			"world_cause": lead.world_cause,
			"related_fact_id": lead.related_fact_id,
			"region_id": lead.region_id,
			"source_faction_id": lead.source_faction_id,
			"risk": _round(lead.risk),
			"urgency": _round(lead.urgency),
			"freshness": _round(lead.freshness),
			"possible_actions": lead.possible_actions.duplicate(),
		})
	return output


func build_adapted_lead_summary(state: Variant, day: int) -> Array:
	if not state is WorldSimState:
		return []
	var candidates: Array[Dictionary] = []
	for lead in state.lead_candidates:
		if lead.day == day:
			candidates.append(_candidate_dictionary(lead))
	var adapted := adapter.adapt_lead_candidates(candidates)
	var output: Array[Dictionary] = []
	for clue_value: Variant in adapted:
		var clue := clue_value as Dictionary
		output.append({
			"id": String(clue.get("id", "")),
			"type": String(clue.get("type", "")),
			"title": String(clue.get("title", "")),
			"direction": String(clue.get("direction", "")),
			"freshness": _round(float(clue.get("freshness", 0.0))),
			"risk": _round(float(clue.get("risk", 0.0))),
			"possible_actions": (clue.get("possible_actions", []) as Array).duplicate(),
			"world_cause": String(clue.get("world_cause", "")),
			"related_fact_id": String(clue.get("related_fact_id", "")),
		})
	return output


func compare_runs(a_result: Dictionary, b_result: Dictionary) -> Dictionary:
	var a_day_10 := _snapshot_for_day(a_result, 10)
	var b_day_10 := _snapshot_for_day(b_result, 10)
	var day_10_differences := {
		"regions": a_day_10.get("regions", []) != b_day_10.get("regions", []),
		"factions": a_day_10.get("factions", []) != b_day_10.get("factions", []),
		"world_news": (
			a_day_10.get("news_signatures", [])
			!= b_day_10.get("news_signatures", [])
		),
		"lead_candidates": (
			a_day_10.get("lead_signatures", [])
			!= b_day_10.get("lead_signatures", [])
		),
		"adapted_leads": (
			a_day_10.get("adapted_lead_signatures", [])
			!= b_day_10.get("adapted_lead_signatures", [])
		),
	}
	var a_totals := a_result.get("totals", {}) as Dictionary
	var b_totals := b_result.get("totals", {}) as Dictionary
	return {
		"day_10_has_difference": _dictionary_has_true_value(day_10_differences),
		"day_10_differences": day_10_differences,
		"final_region_differences": _compare_summary_arrays(
			a_result.get("final_regions", []) as Array,
			b_result.get("final_regions", []) as Array,
			REGION_METRICS
		),
		"final_faction_differences": _compare_summary_arrays(
			a_result.get("final_factions", []) as Array,
			b_result.get("final_factions", []) as Array,
			FACTION_METRICS
		),
		"world_news_delta": (
			int(b_totals.get("world_news", 0))
			- int(a_totals.get("world_news", 0))
		),
		"lead_candidate_delta": (
			int(b_totals.get("lead_candidates", 0))
			- int(a_totals.get("lead_candidates", 0))
		),
		"adapted_lead_delta": (
			int(b_totals.get("adapted_leads", 0))
			- int(a_totals.get("adapted_leads", 0))
		),
		"lead_signatures_differ": (
			a_result.get("lead_signatures", [])
			!= b_result.get("lead_signatures", [])
		),
		"adapted_lead_signatures_differ": (
			a_result.get("adapted_lead_signatures", [])
			!= b_result.get("adapted_lead_signatures", [])
		),
	}


func export_markdown_report(result: Dictionary, output_path: String) -> void:
	var baseline := result.get("baseline", {}) as Dictionary
	var injected := result.get("test_injection", {}) as Dictionary
	var comparison := result.get("comparison", {}) as Dictionary
	var lines: Array[String] = [
		"# world_sim 观察输出",
		"",
		"## 1. 运行设置",
		"",
		"- 固定 seed：`%s`" % baseline.get("seed", ""),
		"- A 组：无模拟干预，运行 %d 天" % int(baseline.get("days", 0)),
		"- B 组：第 %d 天测试注入 `help_faction(state, \"wardens\", \"border_town\")`"
			% int(injected.get("test_injection_day", 0)),
		"- 输出为开发者观察数据，不接入正式 UI。",
		"",
		"## 2. 无模拟干预 30 天总览",
		"",
	]
	_append_run_overview(lines, baseline)
	lines.append("")
	lines.append("## 3. 每日摘要")
	lines.append("")
	for snapshot_value: Variant in baseline.get("daily_snapshots", []):
		_append_daily_snapshot(lines, snapshot_value as Dictionary)
	lines.append("## 4. 第 3 天测试注入后 30 天总览")
	lines.append("")
	_append_run_overview(lines, injected)
	lines.append("")
	lines.append("## 5. A/B 差异")
	lines.append("")
	_append_comparison(lines, comparison)
	lines.append("")
	lines.append("## 6. 适配后线索样例")
	lines.append("")
	var samples := _adapted_samples(baseline, 5)
	for sample_value: Variant in samples:
		var sample := sample_value as Dictionary
		lines.append(
			"- %s｜%s｜%s｜新鲜度 %.2f｜风险 %.2f｜行动：%s"
			% [
				sample.get("type", ""),
				sample.get("title", ""),
				sample.get("direction", ""),
				float(sample.get("freshness", 0.0)),
				float(sample.get("risk", 0.0)),
				", ".join(sample.get("possible_actions", [])),
			]
		)
	lines.append("")
	lines.append("## 7. 结论")
	lines.append("")
	lines.append(
		"固定 seed 下，world_sim 可稳定输出地区、势力、新闻与线索；"
		+ "第 3 天测试注入会改变后续状态与线索签名。"
	)
	lines.append("观察器只读取并整理模拟结果，没有创建新的世界事实规则。")
	lines.append("")

	var absolute_path := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("[WorldSimObserver] Could not write Markdown: %s" % output_path)
		return
	file.store_string("\n".join(lines))


func _run_observation(days: int, injection_day: int) -> Dictionary:
	var state := simulator.load_seed(SEED_PATH)
	if state == null:
		return {}
	var initial_regions := build_region_summary(state)
	var daily_snapshots: Array[Dictionary] = []
	for _index: int in range(maxi(days, 0)):
		simulator.advance_one_day(state)
		if injection_day > 0 and state.day == injection_day:
			player_actions.help_faction(state, "wardens", "border_town")
		daily_snapshots.append(build_daily_snapshot(state))

	var all_candidates := _candidate_dictionaries(state.lead_candidates)
	var all_adapted := adapter.adapt_lead_candidates(all_candidates)
	return {
		"mode": "baseline" if injection_day < 0 else "test_injection",
		"seed": state.seed,
		"days": days,
		"test_injection_day": injection_day,
		"daily_snapshots": daily_snapshots,
		"final_regions": build_region_summary(state),
		"final_factions": build_faction_summary(state),
		"totals": {
			"world_facts": state.world_facts.size(),
			"world_news": state.world_news.size(),
			"lead_candidates": state.lead_candidates.size(),
			"adapted_leads": all_adapted.size(),
		},
		"lead_type_distribution": _type_distribution(all_adapted),
		"region_tag_changes": _region_tag_changes(
			initial_regions,
			build_region_summary(state)
		),
		"lead_signatures": _lead_object_signatures(state.lead_candidates),
		"adapted_lead_signatures": _adapted_object_signatures(all_adapted),
	}


func _state_day(state: Variant) -> int:
	if state is WorldSimState:
		return state.day
	if state is Dictionary:
		return int(state.get("day", 0))
	return 0


func _candidate_dictionary(lead: Variant) -> Dictionary:
	return {
		"id": lead.id,
		"day": lead.day,
		"type": lead.type,
		"region_id": lead.region_id,
		"source_faction_id": lead.source_faction_id,
		"world_cause": lead.world_cause,
		"urgency": lead.urgency,
		"freshness": lead.freshness,
		"risk": lead.risk,
		"possible_actions": lead.possible_actions.duplicate(),
		"projected_consequences": lead.projected_consequences.duplicate(true),
		"related_fact_id": lead.related_fact_id,
	}


func _candidate_dictionaries(candidates: Array) -> Array:
	var output: Array[Dictionary] = []
	for candidate in candidates:
		output.append(_candidate_dictionary(candidate))
	return output


func _snapshot_for_day(result: Dictionary, day: int) -> Dictionary:
	for snapshot_value: Variant in result.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		if int(snapshot.get("day", 0)) == day:
			return snapshot
	return {}


func _compare_summary_arrays(
		a_summaries: Array,
		b_summaries: Array,
		metrics: Array[String]
	) -> Array:
	var a_by_id := _summaries_by_id(a_summaries)
	var b_by_id := _summaries_by_id(b_summaries)
	var ids: Array = a_by_id.keys()
	for id_value: Variant in b_by_id.keys():
		if not id_value in ids:
			ids.append(id_value)
	ids.sort()
	var output: Array[Dictionary] = []
	for id_value: Variant in ids:
		var id := String(id_value)
		var a := a_by_id.get(id, {}) as Dictionary
		var b := b_by_id.get(id, {}) as Dictionary
		var deltas: Dictionary = {}
		for metric: String in metrics:
			deltas[metric] = _round(
				float(b.get(metric, 0.0)) - float(a.get(metric, 0.0))
			)
		output.append({
			"id": id,
			"deltas": deltas,
			"tags_a": (a.get("tags", []) as Array).duplicate(),
			"tags_b": (b.get("tags", []) as Array).duplicate(),
		})
	return output


func _summaries_by_id(summaries: Array) -> Dictionary:
	var output: Dictionary = {}
	for summary_value: Variant in summaries:
		var summary := summary_value as Dictionary
		output[String(summary.get("id", ""))] = summary
	return output


func _dictionary_has_true_value(values: Dictionary) -> bool:
	for value: Variant in values.values():
		if bool(value):
			return true
	return false


func _type_distribution(adapted: Array) -> Dictionary:
	var counts: Dictionary = {}
	for clue_value: Variant in adapted:
		var clue := clue_value as Dictionary
		var type_name := String(clue.get("type", ""))
		counts[type_name] = int(counts.get(type_name, 0)) + 1
	return counts


func _region_tag_changes(initial: Array, final: Array) -> Array:
	var initial_by_id := _summaries_by_id(initial)
	var output: Array[Dictionary] = []
	for final_value: Variant in final:
		var final_region := final_value as Dictionary
		var region_id := String(final_region.get("id", ""))
		var initial_region := initial_by_id.get(region_id, {}) as Dictionary
		var before := (initial_region.get("tags", []) as Array).duplicate()
		var after := (final_region.get("tags", []) as Array).duplicate()
		output.append({
			"id": region_id,
			"before": before,
			"after": after,
			"added": _array_difference(after, before),
			"removed": _array_difference(before, after),
		})
	return output


func _array_difference(left: Array, right: Array) -> Array:
	var output: Array[String] = []
	for value: Variant in left:
		var text := String(value)
		if not text in right:
			output.append(text)
	return output


func _news_summary_signatures(news: Array) -> Array[String]:
	var output: Array[String] = []
	for news_value: Variant in news:
		var item := news_value as Dictionary
		output.append(
			"%s|%s|%s"
			% [
				item.get("region_id", ""),
				item.get("source", ""),
				item.get("summary", ""),
			]
		)
	return output


func _lead_summary_signatures(leads: Array) -> Array[String]:
	var output: Array[String] = []
	for lead_value: Variant in leads:
		var lead := lead_value as Dictionary
		output.append(
			"%s|%s|%s|%s"
			% [
				lead.get("type", ""),
				lead.get("region_id", ""),
				lead.get("world_cause", ""),
				lead.get("related_fact_id", ""),
			]
		)
	return output


func _adapted_summary_signatures(leads: Array) -> Array[String]:
	var output: Array[String] = []
	for lead_value: Variant in leads:
		var lead := lead_value as Dictionary
		output.append(
			"%s|%s|%s|%s"
			% [
				lead.get("type", ""),
				lead.get("title", ""),
				lead.get("world_cause", ""),
				lead.get("related_fact_id", ""),
			]
		)
	return output


func _lead_object_signatures(leads: Array) -> Array[String]:
	var output: Array[String] = []
	for lead in leads:
		output.append(
			"%d|%s|%s|%s|%s"
			% [
				lead.day,
				lead.type,
				lead.region_id,
				lead.world_cause,
				lead.related_fact_id,
			]
		)
	return output


func _adapted_object_signatures(leads: Array) -> Array[String]:
	var output: Array[String] = []
	for lead_value: Variant in leads:
		var lead := lead_value as Dictionary
		output.append(
			"%s|%s|%s|%s"
			% [
				lead.get("id", ""),
				lead.get("type", ""),
				lead.get("world_cause", ""),
				lead.get("related_fact_id", ""),
			]
		)
	return output


func _append_run_overview(lines: Array[String], run: Dictionary) -> void:
	var totals := run.get("totals", {}) as Dictionary
	lines.append(
		"- 总量：world_fact %d，world_news %d，LeadCandidate %d，适配后线索 %d"
		% [
			int(totals.get("world_facts", 0)),
			int(totals.get("world_news", 0)),
			int(totals.get("lead_candidates", 0)),
			int(totals.get("adapted_leads", 0)),
		]
	)
	lines.append(
		"- 线索类型分布：`%s`"
		% JSON.stringify(run.get("lead_type_distribution", {}))
	)
	lines.append("- 30 天后地区最终状态：")
	for region_value: Variant in run.get("final_regions", []):
		var region := region_value as Dictionary
		lines.append("  - %s：%s" % [region.get("id", ""), _region_metric_text(region)])
	lines.append("- 30 天后势力最终状态：")
	for faction_value: Variant in run.get("final_factions", []):
		var faction := faction_value as Dictionary
		lines.append("  - %s：%s" % [faction.get("id", ""), _faction_metric_text(faction)])
	lines.append("- 地区 tag 变化：")
	for change_value: Variant in run.get("region_tag_changes", []):
		var change := change_value as Dictionary
		lines.append(
			"  - %s：新增 [%s]，移除 [%s]"
			% [
				change.get("id", ""),
				", ".join(change.get("added", [])),
				", ".join(change.get("removed", [])),
			]
		)


func _append_daily_snapshot(lines: Array[String], snapshot: Dictionary) -> void:
	lines.append("### Day %d" % int(snapshot.get("day", 0)))
	lines.append("")
	lines.append("地区摘要：")
	for region_value: Variant in snapshot.get("regions", []):
		var region := region_value as Dictionary
		lines.append("- %s：%s" % [region.get("id", ""), _region_metric_text(region)])
	lines.append("")
	lines.append("势力摘要：")
	for faction_value: Variant in snapshot.get("factions", []):
		var faction := faction_value as Dictionary
		lines.append("- %s：%s" % [faction.get("id", ""), _faction_metric_text(faction)])
	lines.append("")
	lines.append("当天新闻：")
	_append_limited_news(lines, snapshot.get("news", []) as Array, 3)
	lines.append("")
	lines.append("当天 LeadCandidate：")
	_append_limited_leads(lines, snapshot.get("leads", []) as Array, 3)
	lines.append("")
	lines.append("当天适配后 v0.3 线索：")
	_append_limited_adapted(lines, snapshot.get("adapted_leads", []) as Array, 3)
	lines.append("")


func _append_limited_news(lines: Array[String], news: Array, limit: int) -> void:
	if news.is_empty():
		lines.append("- 无")
		return
	for index: int in range(mini(limit, news.size())):
		var item := news[index] as Dictionary
		lines.append(
			"- %s / %s：%s"
			% [item.get("region_id", ""), item.get("source", ""), item.get("summary", "")]
		)


func _append_limited_leads(lines: Array[String], leads: Array, limit: int) -> void:
	if leads.is_empty():
		lines.append("- 无")
		return
	for index: int in range(mini(limit, leads.size())):
		var lead := leads[index] as Dictionary
		lines.append(
			"- %s / %s / %s / risk %.2f / urgency %.2f"
			% [
				lead.get("type", ""),
				lead.get("world_cause", ""),
				lead.get("related_fact_id", ""),
				float(lead.get("risk", 0.0)),
				float(lead.get("urgency", 0.0)),
			]
		)


func _append_limited_adapted(lines: Array[String], leads: Array, limit: int) -> void:
	if leads.is_empty():
		lines.append("- 无")
		return
	for index: int in range(mini(limit, leads.size())):
		var lead := leads[index] as Dictionary
		lines.append(
			"- %s / %s / %s / freshness %.2f / risk %.2f / %s"
			% [
				lead.get("type", ""),
				lead.get("title", ""),
				lead.get("direction", ""),
				float(lead.get("freshness", 0.0)),
				float(lead.get("risk", 0.0)),
				", ".join(lead.get("possible_actions", [])),
			]
		)


func _append_comparison(lines: Array[String], comparison: Dictionary) -> void:
	var day_10 := comparison.get("day_10_differences", {}) as Dictionary
	lines.append(
		"- 第 10 天是否已出现差异：%s"
		% ("是" if bool(comparison.get("day_10_has_difference", false)) else "否")
	)
	lines.append("- 第 10 天差异项：`%s`" % JSON.stringify(day_10))
	lines.append(
		"- 数量差：world_news %+d，LeadCandidate %+d，适配后线索 %+d"
		% [
			int(comparison.get("world_news_delta", 0)),
			int(comparison.get("lead_candidate_delta", 0)),
			int(comparison.get("adapted_lead_delta", 0)),
		]
	)
	lines.append(
		"- 线索签名是否不同：%s；适配后线索签名是否不同：%s"
		% [
			"是" if bool(comparison.get("lead_signatures_differ", false)) else "否",
			"是" if bool(comparison.get("adapted_lead_signatures_differ", false)) else "否",
		]
	)
	lines.append("- 第 30 天地区状态差异：")
	for region_value: Variant in comparison.get("final_region_differences", []):
		var region := region_value as Dictionary
		lines.append(
			"  - %s：`%s`"
			% [region.get("id", ""), JSON.stringify(region.get("deltas", {}))]
		)
	lines.append("- 第 30 天势力状态差异：")
	for faction_value: Variant in comparison.get("final_faction_differences", []):
		var faction := faction_value as Dictionary
		lines.append(
			"  - %s：`%s`"
			% [faction.get("id", ""), JSON.stringify(faction.get("deltas", {}))]
		)


func _adapted_samples(run: Dictionary, limit: int) -> Array:
	var output: Array[Dictionary] = []
	for snapshot_value: Variant in run.get("daily_snapshots", []):
		var snapshot := snapshot_value as Dictionary
		for clue_value: Variant in snapshot.get("adapted_leads", []):
			output.append(clue_value as Dictionary)
			if output.size() >= limit:
				return output
	return output


func _region_metric_text(region: Dictionary) -> String:
	return (
		"danger %.2f / order %.2f / scarcity %.2f / mystic %.2f / "
		+ "food %.2f / herbs %.2f / relics %.2f / information %.2f / tags [%s]"
	) % [
		float(region.get("danger", 0.0)),
		float(region.get("order", 0.0)),
		float(region.get("scarcity", 0.0)),
		float(region.get("mystic", 0.0)),
		float(region.get("food", 0.0)),
		float(region.get("herbs", 0.0)),
		float(region.get("relics", 0.0)),
		float(region.get("information", 0.0)),
		", ".join(region.get("tags", [])),
	]


func _faction_metric_text(faction: Dictionary) -> String:
	return "power %.2f / wealth %.2f / hostility %.2f / goal %s" % [
		float(faction.get("power", 0.0)),
		float(faction.get("wealth", 0.0)),
		float(faction.get("hostility_to_player", 0.0)),
		faction.get("goal", ""),
	]


func _round(value: float) -> float:
	return snappedf(value, 0.01)
