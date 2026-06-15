extends RefCounted
class_name WorldSimObserver

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const PlayerActionsModel = preload("res://scripts/sim/player_world_actions.gd")
const AdapterModel = preload("res://scripts/sim/world_sim_lead_adapter.gd")
const NewsDigestModel = preload("res://scripts/sim/world_news_digest.gd")
const MicroActionResolverModel = preload("res://scripts/sim/micro_action_resolver.gd")

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
var news_digest := NewsDigestModel.new()
var micro_action_resolver := MicroActionResolverModel.new()


func run_baseline(days: int = 30) -> Dictionary:
	return _run_observation(days, -1)


func run_with_test_injection(days: int = 30, injection_day: int = 3) -> Dictionary:
	return _run_observation(days, injection_day)


func build_daily_snapshot(state: Variant) -> Dictionary:
	var day := _state_day(state)
	var news := build_news_summary(state, day)
	var continuous_news := build_continuous_news_summary(state)
	var leads := build_lead_summary(state, day)
	var adapted_leads := build_adapted_lead_summary(state, day)
	return {
		"day": day,
		"regions": build_region_summary(state),
		"factions": build_faction_summary(state),
		"news": news,
		"continuous_news": continuous_news,
		"leads": leads,
		"adapted_leads": adapted_leads,
		"lake_town": build_lake_town_summary(state, day),
		"news_signatures": _news_summary_signatures(news),
		"lead_signatures": _lead_summary_signatures(leads),
		"adapted_lead_signatures": _adapted_summary_signatures(adapted_leads),
	}


func build_lake_town_summary(state: Variant, target_day: int = -1) -> Dictionary:
	if not state is WorldSimState:
		return {}
	if state.get_npc("old_chen").is_empty():
		return {}
	var old_chen: Dictionary = state.get_npc("old_chen")
	var chen_mi: Dictionary = state.get_npc("chen_mi")
	var shop: Dictionary = state.get_location("old_chen_shop")
	var granary: Dictionary = state.get_location("abandoned_granary")
	var shop_state := shop.get("state", {}) as Dictionary
	var granary_state := granary.get("state", {}) as Dictionary
	var facts: Array[Dictionary] = []
	for fact in state.world_facts:
		if String(fact.data.get("scope", "")) != "micro":
			continue
		if target_day >= 0 and fact.day != target_day:
			continue
		facts.append({
			"id": fact.id,
			"type": fact.type,
			"day": fact.day,
			"location_id": fact.location_id,
			"cause_fact_ids": fact.cause_fact_ids.duplicate(),
		})
	var traces: Array[Dictionary] = []
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		if target_day >= 0 and int(trace.get("created_day", 0)) != target_day:
			continue
		traces.append(trace.duplicate(true))
	var scenes: Array[Dictionary] = []
	for scene_value: Variant in state.narratable_states:
		var scene := (scene_value as Dictionary).duplicate(true)
		if target_day >= 0 and int(scene.get("created_day", 0)) != target_day:
			continue
		scene["source_fact_types"] = _fact_types_for_ids(
			state,
			scene.get("source_fact_ids", []) as Array
		)
		scene["trace_types"] = _trace_types_for_ids(
			state,
			scene.get("trace_ids", []) as Array
		)
		scenes.append(scene)
	var old_chen_summary: Dictionary = {
		"stress": _round(float(old_chen.get("stress", 0.0))),
		"debt": _round(float(old_chen.get("debt", 0.0))),
		"family_food": _round(float(old_chen.get("family_food", 0.0))),
		"money": _round(float(old_chen.get("money", 0.0))),
		"shop_open": bool(shop_state.get("is_open", false)),
		"status_tags": (
			old_chen.get("status_tags", []) as Array
		).duplicate(),
	}
	var chen_mi_summary: Dictionary = {
		"hunger": _round(float(chen_mi.get("hunger", 0.0))),
		"fear": _round(float(chen_mi.get("fear", 0.0))),
		"health": _round(float(chen_mi.get("health", 0.0))),
		"inventory": (
			chen_mi.get("inventory", []) as Array
		).duplicate(),
		"status_tags": (
			chen_mi.get("status_tags", []) as Array
		).duplicate(),
	}
	var shop_summary: Dictionary = {
		"is_open": bool(shop_state.get("is_open", false)),
		"food_stock": _round(float(shop_state.get("food_stock", 0.0))),
		"family_crisis": bool(shop_state.get("family_crisis", false)),
		"traces": (shop.get("traces", []) as Array).duplicate(),
	}
	var granary_summary: Dictionary = {
		"spoiled_grain_stock": _round(
			float(granary_state.get("spoiled_grain_stock", 0.0))
		),
		"disease_risk": _round(
			float(granary_state.get("disease_risk", 0.0))
		),
		"traces": (granary.get("traces", []) as Array).duplicate(),
	}
	var output: Dictionary = {}
	output["old_chen"] = old_chen_summary
	output["chen_mi"] = chen_mi_summary
	output["old_chen_shop"] = shop_summary
	output["abandoned_granary"] = granary_summary
	output["food_price_index"] = _round(
		float(state.micro_state.get("food_price_index", 1.0))
	)
	output["new_facts"] = facts
	output["new_traces"] = traces
	output["narratable_states"] = scenes
	return output


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
			"news_key": news.news_key,
			"stage": news.stage,
			"occurrence_count": news.occurrence_count,
			"world_cause": news.world_cause,
			"kind": news.kind,
		})
	return output


func build_continuous_news_summary(state: Variant) -> Array:
	if not state is WorldSimState:
		return []
	return news_digest.build_continuous_summaries(state, 3)


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
	lines.append("## 湖湾镇微观链观察")
	lines.append("")
	_append_lake_town_overview(
		lines,
		baseline.get("lake_town_final", {}) as Dictionary
	)
	_append_micro_action_candidates(
		lines,
		baseline.get("micro_action_candidates", []) as Array
	)
	lines.append("")
	lines.append("## 湖湾镇模拟行动后果对照")
	lines.append("")
	lines.append(
		"- 以下结果来自同一基线场景的独立克隆状态，是无头模拟行动，"
		+ "不是真实 UI 输入。"
	)
	lines.append("")
	_append_micro_action_results(
		lines,
		baseline.get("micro_action_results", []) as Array
	)
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
	var micro_action_baseline: WorldSimState = null
	for _index: int in range(maxi(days, 0)):
		simulator.advance_one_day(state)
		if injection_day > 0 and state.day == injection_day:
			player_actions.help_faction(state, "wardens", "border_town")
		if (
			micro_action_baseline == null
			and _has_open_micro_scene(state)
		):
			micro_action_baseline = state.duplicate_state()
		daily_snapshots.append(build_daily_snapshot(state))

	var all_candidates := _candidate_dictionaries(state.lead_candidates)
	var all_adapted := adapter.adapt_lead_candidates(all_candidates)
	var micro_action_observation := _build_micro_action_observation(
		micro_action_baseline
	)
	return {
		"mode": "baseline" if injection_day < 0 else "test_injection",
		"seed": state.seed,
		"days": days,
		"test_injection_day": injection_day,
		"daily_snapshots": daily_snapshots,
		"final_regions": build_region_summary(state),
		"final_factions": build_faction_summary(state),
		"lake_town_final": build_lake_town_summary(state, -1),
		"micro_action_candidates": micro_action_observation.get(
			"candidates",
			[]
		),
		"micro_action_results": micro_action_observation.get("results", []),
		"totals": {
			"world_facts": state.world_facts.size(),
			"micro_world_facts": _micro_fact_count(state),
			"world_news": state.world_news.size(),
			"news_history": state.news_history.size(),
			"lead_candidates": state.lead_candidates.size(),
			"adapted_leads": all_adapted.size(),
			"traces": state.traces.size(),
			"memories": state.memories.size(),
			"narratable_states": state.narratable_states.size(),
		},
		"lead_type_distribution": _type_distribution(all_adapted),
		"region_tag_changes": _region_tag_changes(
			initial_regions,
			build_region_summary(state)
		),
		"lead_signatures": _lead_object_signatures(state.lead_candidates),
		"adapted_lead_signatures": _adapted_object_signatures(all_adapted),
	}


func _build_micro_action_observation(
		baseline: WorldSimState
	) -> Dictionary:
	if baseline == null:
		return {"candidates": [], "results": []}
	var actor := _test_actor()
	var candidates := micro_action_resolver.build_action_candidates(
		baseline,
		actor,
		"chen_mi_hiding_spoiled_grain_scene"
	)
	var results: Array[Dictionary] = []
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		var before := baseline.duplicate_state()
		var after := baseline.duplicate_state()
		var action_actor := _test_actor()
		var result: Dictionary = micro_action_resolver.resolve_micro_action(
			after,
			action_actor,
			String(candidate.get("id", "")),
			"chen_mi_hiding_spoiled_grain_scene"
		)
		var summary: Dictionary = (
			micro_action_resolver.build_action_result_summary(
				before,
				after,
				result
			)
		)
		results.append({
			"action_id": String(candidate.get("id", "")),
			"label": String(candidate.get("label", "")),
			"ok": bool(summary.get("ok", false)),
			"created_fact_types": (
				summary.get("created_fact_types", []) as Array
			).duplicate(),
			"created_trace_types": (
				summary.get("created_trace_types", []) as Array
			).duplicate(),
			"created_memory_types": (
				summary.get("created_memory_types", []) as Array
			).duplicate(),
			"state_changes": _compact_micro_action_changes(
				summary.get("state_changes", {}) as Dictionary
			),
		})
	return {
		"candidates": candidates,
		"results": results,
	}


func _compact_micro_action_changes(changes: Dictionary) -> Dictionary:
	var output: Dictionary = {}
	var preferred_keys: Array[String] = [
		"actor.inventory.food",
		"actor.inventory.spoiled_grain",
		"actor.money",
		"chen_mi.hunger",
		"chen_mi.fear",
		"chen_mi.inventory",
		"chen_mi.status_tags",
		"old_chen.stress",
		"old_chen.status_tags",
		"micro_relationships",
		"guard_attention",
	]
	for key: String in preferred_keys:
		if changes.has(key):
			output[key] = changes[key]
	return output


func _has_open_micro_scene(state: WorldSimState) -> bool:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if (
			String(scene.get("id", ""))
			== "chen_mi_hiding_spoiled_grain_scene"
			and not bool(scene.get("action_locked", false))
		):
			return true
	return false


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


func _state_day(state: Variant) -> int:
	if state is WorldSimState:
		return state.day
	if state is Dictionary:
		return int(state.get("day", 0))
	return 0


func _micro_fact_count(state: WorldSimState) -> int:
	var count := 0
	for fact in state.world_facts:
		if String(fact.data.get("scope", "")) == "micro":
			count += 1
	return count


func _fact_types_for_ids(
		state: WorldSimState,
		fact_ids: Array
	) -> Array[String]:
	var output: Array[String] = []
	for fact_id_value: Variant in fact_ids:
		var fact_id := String(fact_id_value)
		for fact in state.world_facts:
			if fact.id == fact_id:
				output.append(fact.type)
				break
	return output


func _trace_types_for_ids(
		state: WorldSimState,
		trace_ids: Array
	) -> Array[String]:
	var output: Array[String] = []
	for trace_id_value: Variant in trace_ids:
		var trace_id := String(trace_id_value)
		for trace_value: Variant in state.traces:
			var trace := trace_value as Dictionary
			if String(trace.get("id", "")) == trace_id:
				output.append(String(trace.get("type", "")))
				break
	return output


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
			"%s|%s|%d|%s"
			% [
				item.get("news_key", ""),
				item.get("kind", ""),
				int(item.get("stage", 0)),
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
	var total_format := (
		"- 总量：world_fact %d（微观事实 %d），world_news %d，新闻历史 %d，"
		+ "LeadCandidate %d，适配后线索 %d，Trace %d，可叙述状态 %d"
	)
	lines.append(total_format % [
		int(totals.get("world_facts", 0)),
		int(totals.get("micro_world_facts", 0)),
		int(totals.get("world_news", 0)),
		int(totals.get("news_history", 0)),
		int(totals.get("lead_candidates", 0)),
		int(totals.get("adapted_leads", 0)),
		int(totals.get("traces", 0)),
		int(totals.get("narratable_states", 0)),
	])
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
	_append_lake_town_daily(
		lines,
		snapshot.get("lake_town", {}) as Dictionary
	)
	lines.append("")
	lines.append("当天新新闻：")
	_append_limited_news(lines, snapshot.get("news", []) as Array, 3)
	lines.append("")
	lines.append("连续事件摘要：")
	_append_limited_continuous_news(
		lines,
		snapshot.get("continuous_news", []) as Array,
		3
	)
	lines.append("")
	lines.append("当天 LeadCandidate：")
	_append_limited_leads(lines, snapshot.get("leads", []) as Array, 3)
	lines.append("")
	lines.append("当天适配后 v0.3 线索：")
	_append_limited_adapted(lines, snapshot.get("adapted_leads", []) as Array, 3)
	lines.append("")


func _append_lake_town_daily(
		lines: Array[String],
		summary: Dictionary
	) -> void:
	lines.append("湖湾镇微观状态：")
	if summary.is_empty():
		lines.append("- 未初始化")
		return
	var old_chen := summary.get("old_chen", {}) as Dictionary
	var chen_mi := summary.get("chen_mi", {}) as Dictionary
	var shop := summary.get("old_chen_shop", {}) as Dictionary
	var granary := summary.get("abandoned_granary", {}) as Dictionary
	var old_chen_format := (
		"- old_chen：stress %.2f / debt %.2f / family_food %.2f / "
		+ "shop_open %s / tags [%s]"
	)
	lines.append(old_chen_format % [
		float(old_chen.get("stress", 0.0)),
		float(old_chen.get("debt", 0.0)),
		float(old_chen.get("family_food", 0.0)),
		old_chen.get("shop_open", false),
		", ".join(old_chen.get("status_tags", [])),
	])
	var chen_mi_format := (
		"- chen_mi：hunger %.2f / fear %.2f / health %.2f / "
		+ "inventory [%s] / tags [%s]"
	)
	lines.append(chen_mi_format % [
		float(chen_mi.get("hunger", 0.0)),
		float(chen_mi.get("fear", 0.0)),
		float(chen_mi.get("health", 0.0)),
		", ".join(chen_mi.get("inventory", [])),
		", ".join(chen_mi.get("status_tags", [])),
	])
	var shop_format := (
		"- old_chen_shop：is_open %s / food_stock %.2f / "
		+ "family_crisis %s / traces [%s]"
	)
	lines.append(shop_format % [
		shop.get("is_open", false),
		float(shop.get("food_stock", 0.0)),
		shop.get("family_crisis", false),
		", ".join(shop.get("traces", [])),
	])
	var granary_format := (
		"- abandoned_granary：spoiled_grain_stock %.2f / "
		+ "disease_risk %.2f / traces [%s]"
	)
	lines.append(granary_format % [
		float(granary.get("spoiled_grain_stock", 0.0)),
		float(granary.get("disease_risk", 0.0)),
		", ".join(granary.get("traces", [])),
	])
	var facts := summary.get("new_facts", []) as Array
	var traces := summary.get("new_traces", []) as Array
	var scenes := summary.get("narratable_states", []) as Array
	if facts.is_empty() and traces.is_empty() and scenes.is_empty():
		lines.append("湖湾镇微观链：无新增事实、痕迹或可叙述状态。")
		return
	lines.append("湖湾镇新增事实：")
	for fact_value: Variant in facts:
		var fact := fact_value as Dictionary
		lines.append(
			"- %s / %s / causes [%s]"
			% [
				fact.get("type", ""),
				fact.get("id", ""),
				", ".join(fact.get("cause_fact_ids", [])),
			]
		)
	lines.append("湖湾镇新增痕迹：")
	for trace_value: Variant in traces:
		var trace := trace_value as Dictionary
		lines.append(
			"- %s / %s / source %s"
			% [
				trace.get("type", ""),
				trace.get("id", ""),
				trace.get("source_fact_id", ""),
			]
		)
	lines.append("湖湾镇可叙述状态：")
	for scene_value: Variant in scenes:
		_append_narratable_scene(lines, scene_value as Dictionary)


func _append_lake_town_overview(
		lines: Array[String],
		summary: Dictionary
	) -> void:
	if summary.is_empty():
		lines.append("- 未初始化")
		return
	lines.append(
		"- 当前微观区域从 `border_town` 读取宏观粮食与匮乏压力，"
		+ "尚未独立为正式 RegionState。"
	)
	lines.append(
		"- 粮价指数：%.2f；微观事实：%d；Trace：%d；可叙述状态：%d"
		% [
			float(summary.get("food_price_index", 1.0)),
			(summary.get("new_facts", []) as Array).size(),
			(summary.get("new_traces", []) as Array).size(),
			(summary.get("narratable_states", []) as Array).size(),
		]
	)
	for scene_value: Variant in summary.get("narratable_states", []):
		_append_narratable_scene(lines, scene_value as Dictionary)


func _append_micro_action_candidates(
		lines: Array[String],
		candidates: Array
	) -> void:
	lines.append("")
	lines.append("湖湾镇可行动候选：")
	if candidates.is_empty():
		lines.append("- 无")
		return
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		lines.append(
			"- %s：%s"
			% [
				candidate.get("label", ""),
				candidate.get("condition_summary", ""),
			]
		)


func _append_micro_action_results(
		lines: Array[String],
		results: Array
	) -> void:
	if results.is_empty():
		lines.append("- 未生成行动对照。")
		return
	for result_value: Variant in results:
		var result := result_value as Dictionary
		lines.append("### %s" % result.get("action_id", ""))
		lines.append("")
		lines.append(
			"- 新事实：%s"
			% _joined_or_none(result.get("created_fact_types", []) as Array)
		)
		lines.append(
			"- 状态变化：%s"
			% _state_change_text(result.get("state_changes", {}) as Dictionary)
		)
		lines.append(
			"- 新 Trace：%s"
			% _joined_or_none(result.get("created_trace_types", []) as Array)
		)
		lines.append(
			"- 新 Memory：%s"
			% _joined_or_none(result.get("created_memory_types", []) as Array)
		)
		lines.append("")


func _joined_or_none(values: Array) -> String:
	if values.is_empty():
		return "无"
	return ", ".join(values)


func _state_change_text(changes: Dictionary) -> String:
	if changes.is_empty():
		return "无"
	var entries: Array[String] = []
	var keys: Array = changes.keys()
	keys.sort()
	for key_value: Variant in keys:
		var key := String(key_value)
		var change := changes.get(key, {}) as Dictionary
		entries.append(
			"%s: %s -> %s"
			% [
				key,
				_compact_value(change.get("before")),
				_compact_value(change.get("after")),
			]
		)
	return "；".join(entries)


func _compact_value(value: Variant) -> String:
	if value is float:
		return "%.2f" % float(value)
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)


func _append_narratable_scene(
		lines: Array[String],
		scene: Dictionary
	) -> void:
	lines.append("- 可叙述状态：%s" % scene.get("title", ""))
	lines.append(
		"  原因：%s"
		% _typed_reference_chain(
			scene.get("source_fact_types", []) as Array,
			scene.get("source_fact_ids", []) as Array
		)
	)
	lines.append(
		"  痕迹：%s"
		% _typed_reference_chain(
			scene.get("trace_types", []) as Array,
			scene.get("trace_ids", []) as Array
		)
	)


func _typed_reference_chain(types: Array, ids: Array) -> String:
	var output: Array[String] = []
	for index: int in range(mini(types.size(), ids.size())):
		output.append("%s (%s)" % [types[index], ids[index]])
	return " -> ".join(output)


func _append_limited_news(lines: Array[String], news: Array, limit: int) -> void:
	if news.is_empty():
		lines.append("- 无")
		return
	for index: int in range(mini(limit, news.size())):
		var item := news[index] as Dictionary
		lines.append(
			"- %s / %s / 阶段 %d / 累计 %d：%s"
			% [
				item.get("region_id", ""),
				item.get("source", ""),
				int(item.get("stage", 0)),
				int(item.get("occurrence_count", 0)),
				item.get("summary", ""),
			]
		)


func _append_limited_continuous_news(
		lines: Array[String],
		news: Array,
		limit: int
	) -> void:
	if news.is_empty():
		lines.append("- 无")
		return
	for index: int in range(mini(limit, news.size())):
		var item := news[index] as Dictionary
		lines.append(
			"- %s / 阶段 %d / 累计 %d：%s"
			% [
				item.get("region_id", ""),
				int(item.get("stage", 0)),
				int(item.get("count", 0)),
				item.get("summary", ""),
			]
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
