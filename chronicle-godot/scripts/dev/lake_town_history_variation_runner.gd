extends RefCounted
class_name LakeTownHistoryVariationRunner

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const DEFAULT_OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_lake_town_history_variation_output.md"
)
const DEFAULT_SEEDS: Array[int] = [
	2026061501,
	2026061502,
	2026061503,
	2026061504,
	2026061505,
	2026061506,
	2026061507,
	2026061508,
	2026061509,
	2026061510,
	2026061511,
	2026061512,
	2026061513,
	2026061514,
	2026061515,
	2026061516,
	2026061517,
	2026061518,
	2026061519,
	2026061520,
]
const SIGNATURE_FACT_TYPES: Array[String] = [
	"lake_town_food_price_rising",
	"chen_mi_took_spoiled_grain",
	"old_chen_closed_shop_due_to_family_crisis",
	"chen_mi_ate_spoiled_grain",
	"chen_mi_fell_sick_from_spoiled_grain",
	"ma_shen_noticed_closed_shop",
	"ma_shen_brought_porridge",
	"creditor_left_debt_notice",
	"old_chen_reopened_shop_half_day",
	"ma_shen_helped_before_theft",
	"old_chen_bought_food_on_credit",
	"chen_mi_found_empty_granary",
	"guard_locked_abandoned_granary",
	"creditor_pressed_before_theft",
	"chen_mi_endured_hunger",
	"other_family_took_granary_grain",
]
const ALTERNATIVE_PATH_TYPES: Array[String] = [
	"ma_shen_helped_before_theft",
	"old_chen_bought_food_on_credit",
	"chen_mi_found_empty_granary",
	"guard_locked_abandoned_granary",
	"creditor_pressed_before_theft",
	"chen_mi_endured_hunger",
	"other_family_took_granary_grain",
]
const FACT_LABELS := {
	"lake_town_food_price_rising": "粮价上涨",
	"chen_mi_took_spoiled_grain": "陈米取走发霉麦子",
	"old_chen_closed_shop_due_to_family_crisis": "老陈因家庭危机闭店",
	"chen_mi_ate_spoiled_grain": "陈米吃下发霉麦子",
	"chen_mi_fell_sick_from_spoiled_grain": "陈米因发霉麦子生病",
	"ma_shen_noticed_closed_shop": "玛婶注意到闭店",
	"ma_shen_brought_porridge": "玛婶送粥",
	"creditor_left_debt_notice": "刘账房留下催债告示",
	"old_chen_reopened_shop_half_day": "老陈半日开店",
	"ma_shen_helped_before_theft": "玛婶在取粮前帮助",
	"old_chen_bought_food_on_credit": "老陈赊账买粮",
	"chen_mi_found_empty_granary": "陈米发现空粮仓",
	"guard_locked_abandoned_granary": "守卫封锁废弃粮仓",
	"creditor_pressed_before_theft": "刘账房在取粮前催债",
	"chen_mi_endured_hunger": "陈米忍耐饥饿",
	"other_family_took_granary_grain": "另一个饥饿家庭先取粮",
}

var simulator := SimulatorModel.new()


func run_seed(seed_value: int, days: int = 30) -> Dictionary:
	var state := simulator.load_seed_with_lake_town_profile(
		SEED_PATH,
		seed_value
	)
	if state == null:
		return {}
	simulator.advance_days(state, days)
	var signature := build_history_signature(state)
	return {
		"seed": seed_value,
		"days": days,
		"state": state,
		"profile_summary": signature.get("profile_summary", {}),
		"signature": signature,
		"signature_hash": build_history_hash(signature),
	}


func run_batch(
		seeds: Array = DEFAULT_SEEDS,
		days: int = 30
	) -> Dictionary:
	var runs: Array[Dictionary] = []
	var outcome_counts: Dictionary = {}
	var unique_hashes: Dictionary = {}
	var theft_count := 0
	var alternative_seed_count := 0
	var close_days: Array[int] = []
	var ma_days: Array[int] = []
	var creditor_days: Array[int] = []
	for seed_value: Variant in seeds:
		var run := run_seed(int(seed_value), days)
		if run.is_empty():
			continue
		runs.append(run)
		var signature := run.get("signature", {}) as Dictionary
		var fact_days := signature.get("fact_days", {}) as Dictionary
		var outcome := String(signature.get("outcome_class", ""))
		outcome_counts[outcome] = int(outcome_counts.get(outcome, 0)) + 1
		unique_hashes[String(run.get("signature_hash", ""))] = true
		if int(fact_days.get("chen_mi_took_spoiled_grain", -1)) >= 0:
			theft_count += 1
		if _signature_has_alternative_path(signature):
			alternative_seed_count += 1
		_append_day(
			close_days,
			int(
				fact_days.get(
					"old_chen_closed_shop_due_to_family_crisis",
					-1
				)
			)
		)
		_append_day(
			ma_days,
			_first_fact_day(
				fact_days,
				[
					"ma_shen_helped_before_theft",
					"ma_shen_brought_porridge",
				]
			)
		)
		_append_day(
			creditor_days,
			_first_fact_day(
				fact_days,
				[
					"creditor_pressed_before_theft",
					"creditor_left_debt_notice",
				]
			)
		)
	var reproducibility: Array[Dictionary] = []
	for index: int in range(mini(3, runs.size())):
		var seed_value := int(runs[index].get("seed", 0))
		var repeated := run_seed(seed_value, days)
		reproducibility.append({
			"seed": seed_value,
			"matches": (
				String(runs[index].get("signature_hash", ""))
				== String(repeated.get("signature_hash", ""))
				and runs[index].get("signature", {})
				== repeated.get("signature", {})
			),
		})
	return {
		"days": days,
		"runs": runs,
		"seed_count": runs.size(),
		"unique_signature_count": unique_hashes.size(),
		"outcome_counts": outcome_counts,
		"outcome_class_count": outcome_counts.size(),
		"theft_count": theft_count,
		"no_theft_count": runs.size() - theft_count,
		"alternative_seed_count": alternative_seed_count,
		"close_day_range": _day_range(close_days),
		"ma_intervention_day_range": _day_range(ma_days),
		"creditor_day_range": _day_range(creditor_days),
		"reproducibility": reproducibility,
		"all_reproducible": _all_reproducible(reproducibility),
	}


func build_history_signature(state: Variant) -> Dictionary:
	if not state is WorldSimState:
		return {}
	var fact_days := build_fact_day_map(state)
	var signature := {
		"seed": state.seed,
		"profile_summary": (
			state.micro_state.get("seed_profile_summary", {})
			as Dictionary
		).duplicate(true),
		"fact_days": fact_days,
		"final_state": _build_final_state(state),
		"narratable_state_ids": _narratable_state_ids(state),
		"trace_ids": _dictionary_ids(state.traces),
		"memory_ids": _dictionary_ids(state.memories),
		"trace_types": _dictionary_types(state.traces),
		"memory_types": _dictionary_types(state.memories),
		"outcome_class": "",
	}
	signature["outcome_class"] = classify_history_outcome(signature)
	return signature


func classify_history_outcome(signature: Dictionary) -> String:
	var fact_days := signature.get("fact_days", {}) as Dictionary
	var theft := _fact_happened(fact_days, "chen_mi_took_spoiled_grain")
	var sick := _fact_happened(
		fact_days,
		"chen_mi_fell_sick_from_spoiled_grain"
	)
	var debt_notice := _fact_happened(
		fact_days,
		"creditor_left_debt_notice"
	)
	var helped := (
		_fact_happened(fact_days, "ma_shen_brought_porridge")
		or _fact_happened(fact_days, "ma_shen_helped_before_theft")
	)
	if theft and sick and debt_notice:
		return "theft_sickness_debt"
	if theft and helped:
		return "theft_helped_recovery"
	if not theft:
		if _fact_happened(fact_days, "guard_locked_abandoned_granary"):
			return "guard_locked_granary"
		if _fact_happened(fact_days, "other_family_took_granary_grain"):
			return "other_family_took_grain"
		if _fact_happened(fact_days, "chen_mi_found_empty_granary"):
			return "empty_granary_no_theft"
		if _fact_happened(fact_days, "chen_mi_endured_hunger"):
			return "endured_hunger_no_theft"
		if _fact_happened(fact_days, "ma_shen_helped_before_theft"):
			return "early_neighbor_help_no_theft"
		if _fact_happened(fact_days, "creditor_pressed_before_theft"):
			return "early_debt_pressure"
		if _fact_happened(fact_days, "old_chen_bought_food_on_credit"):
			return "credit_purchase_delayed_crisis"
	return "mixed_or_unclassified"


func build_fact_day_map(state: Variant) -> Dictionary:
	var output: Dictionary = {}
	for type_name: String in SIGNATURE_FACT_TYPES:
		output[type_name] = -1
	if not state is WorldSimState:
		return output
	for fact in state.world_facts:
		if output.has(fact.type) and int(output[fact.type]) < 0:
			output[fact.type] = fact.day
	return output


func compare_history_signatures(
		a: Dictionary,
		b: Dictionary
	) -> Dictionary:
	return {
		"identical": a == b,
		"hash_a": build_history_hash(a),
		"hash_b": build_history_hash(b),
		"fact_days_differ": a.get("fact_days", {}) != b.get("fact_days", {}),
		"final_state_differ": (
			a.get("final_state", {}) != b.get("final_state", {})
		),
		"outcome_class_differ": (
			a.get("outcome_class", "") != b.get("outcome_class", "")
		),
	}


func build_history_hash(signature: Dictionary) -> String:
	var history_core := {
		"fact_days": signature.get("fact_days", {}),
		"final_state": signature.get("final_state", {}),
		"narratable_state_ids": signature.get("narratable_state_ids", []),
		"trace_types": signature.get("trace_types", []),
		"memory_types": signature.get("memory_types", []),
		"outcome_class": signature.get("outcome_class", ""),
	}
	return JSON.stringify(history_core).sha256_text().substr(0, 16)


func export_markdown_report(
		batch: Dictionary,
		output_path: String = DEFAULT_OUTPUT_PATH
	) -> void:
	var lines: Array[String] = [
		"# 湖湾镇多 seed 历史差异观察输出",
		"",
		"## 湖湾镇多 seed 历史差异摘要",
		"",
		"- 批量 seed：%d" % int(batch.get("seed_count", 0)),
		"- 每个 seed 推进：%d 天" % int(batch.get("days", 0)),
		"- 唯一历史签名：%d" % int(
			batch.get("unique_signature_count", 0)
		),
		"- 结局类型：%d" % int(batch.get("outcome_class_count", 0)),
		"- 结局分布：`%s`" % JSON.stringify(
			batch.get("outcome_counts", {})
		),
		"- 陈米取粮发生次数：%d / %d" % [
			int(batch.get("theft_count", 0)),
			int(batch.get("seed_count", 0)),
		],
		"- 陈米未取粮次数：%d / %d" % [
			int(batch.get("no_theft_count", 0)),
			int(batch.get("seed_count", 0)),
		],
		"- 出现替代路径的 seed：%d" % int(
			batch.get("alternative_seed_count", 0)
		),
		"- 老陈闭店发生日范围：%s" % _day_range_text(
			batch.get("close_day_range", {}) as Dictionary
		),
		"- 玛婶介入发生日范围：%s" % _day_range_text(
			batch.get("ma_intervention_day_range", {}) as Dictionary
		),
		"- 刘账房催债发生日范围：%s" % _day_range_text(
			batch.get("creditor_day_range", {}) as Dictionary
		),
		"- 三个 seed 双跑复现：%s" % (
			"通过" if bool(batch.get("all_reproducible", false)) else "失败"
		),
		"",
		"## 每个 seed 的签名摘要",
		"",
	]
	for run_value: Variant in batch.get("runs", []):
		var run := run_value as Dictionary
		var signature := run.get("signature", {}) as Dictionary
		lines.append("### Seed %d" % int(run.get("seed", 0)))
		lines.append("")
		lines.append(
			"- profile：`%s`"
			% JSON.stringify(run.get("profile_summary", {}))
		)
		lines.append(
			"- 关键事实日：`%s`"
			% JSON.stringify(signature.get("fact_days", {}))
		)
		lines.append(
			"- 最终状态：`%s`"
			% JSON.stringify(signature.get("final_state", {}))
		)
		lines.append(
			"- 结局分类：`%s`"
			% signature.get("outcome_class", "")
		)
		lines.append("- 历史签名 hash：`%s`" % run.get("signature_hash", ""))
		lines.append("")

	lines.append("## 湖湾镇历史样例")
	lines.append("")
	for run_value: Variant in _select_history_samples(
		batch.get("runs", []) as Array,
		5
	):
		var run := run_value as Dictionary
		var signature := run.get("signature", {}) as Dictionary
		lines.append(
			"### Seed %d：%s"
			% [
				int(run.get("seed", 0)),
				signature.get("outcome_class", ""),
			]
		)
		lines.append("")
		var events := _timeline_events(
			signature.get("fact_days", {}) as Dictionary
		)
		if events.is_empty():
			lines.append("- 30 天内没有形成关键微观事实。")
		else:
			for event: String in events:
				lines.append("- " + event)
		lines.append("")
	lines.append("## 复现性复核")
	lines.append("")
	for result_value: Variant in batch.get("reproducibility", []):
		var result := result_value as Dictionary
		lines.append(
			"- Seed %d：%s"
			% [
				int(result.get("seed", 0)),
				"一致" if bool(result.get("matches", false)) else "不一致",
			]
		)
	lines.append("")
	lines.append(
		"本输出来自无头批量模拟。seed 只生成初始状态、性格权重、"
		+ "资源与压力；结局分类由运行后实际 WorldFact 组合推导。"
	)
	lines.append("")

	var absolute_path := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"[LakeTownHistoryVariationRunner] Cannot write %s"
			% output_path
		)
		return
	file.store_string("\n".join(lines))


func _build_final_state(state: WorldSimState) -> Dictionary:
	var chen_mi := state.get_npc("chen_mi")
	var old_chen := state.get_npc("old_chen")
	var shop_state := (
		state.get_location("old_chen_shop").get("state", {})
		as Dictionary
	)
	var granary_state := (
		state.get_location("abandoned_granary").get("state", {})
		as Dictionary
	)
	return {
		"chen_mi_hunger": _round(float(chen_mi.get("hunger", 0.0))),
		"chen_mi_fear": _round(float(chen_mi.get("fear", 0.0))),
		"chen_mi_health": _round(float(chen_mi.get("health", 0.0))),
		"old_chen_stress": _round(float(old_chen.get("stress", 0.0))),
		"old_chen_debt": _round(float(old_chen.get("debt", 0.0))),
		"shop_open": bool(shop_state.get("is_open", false)),
		"shop_partial_open": bool(shop_state.get("partial_open", false)),
		"granary_stock": int(
			roundf(float(granary_state.get("spoiled_grain_stock", 0.0)))
		),
	}


func _narratable_state_ids(state: WorldSimState) -> Array[String]:
	var output: Array[String] = []
	for scene_value: Variant in state.narratable_states:
		output.append(String((scene_value as Dictionary).get("id", "")))
	output.sort()
	return output


func _dictionary_ids(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in values:
		output.append(String((value as Dictionary).get("id", "")))
	output.sort()
	return output


func _dictionary_types(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in values:
		output.append(String((value as Dictionary).get("type", "")))
	output.sort()
	return output


func _signature_has_alternative_path(signature: Dictionary) -> bool:
	var fact_days := signature.get("fact_days", {}) as Dictionary
	for type_name: String in ALTERNATIVE_PATH_TYPES:
		if _fact_happened(fact_days, type_name):
			return true
	return false


func _fact_happened(fact_days: Dictionary, type_name: String) -> bool:
	return int(fact_days.get(type_name, -1)) >= 0


func _append_day(days: Array[int], day: int) -> void:
	if day >= 0:
		days.append(day)


func _first_fact_day(fact_days: Dictionary, type_names: Array) -> int:
	var earliest := -1
	for type_value: Variant in type_names:
		var day := int(fact_days.get(String(type_value), -1))
		if day >= 0 and (earliest < 0 or day < earliest):
			earliest = day
	return earliest


func _day_range(days: Array[int]) -> Dictionary:
	if days.is_empty():
		return {"minimum": -1, "maximum": -1, "unique_days": []}
	var unique: Dictionary = {}
	for day: int in days:
		unique[day] = true
	var unique_days: Array = unique.keys()
	unique_days.sort()
	return {
		"minimum": unique_days.front(),
		"maximum": unique_days.back(),
		"unique_days": unique_days,
	}


func _day_range_text(day_range: Dictionary) -> String:
	var minimum := int(day_range.get("minimum", -1))
	var maximum := int(day_range.get("maximum", -1))
	if minimum < 0:
		return "未发生"
	return "Day %d - Day %d" % [minimum, maximum]


func _all_reproducible(results: Array[Dictionary]) -> bool:
	if results.size() < 3:
		return false
	for result: Dictionary in results:
		if not bool(result.get("matches", false)):
			return false
	return true


func _select_history_samples(runs: Array, limit: int) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var seen_outcomes: Dictionary = {}
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		var signature := run.get("signature", {}) as Dictionary
		var outcome := String(signature.get("outcome_class", ""))
		if seen_outcomes.has(outcome):
			continue
		seen_outcomes[outcome] = true
		output.append(run)
		if output.size() >= limit:
			return output
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		if run in output:
			continue
		output.append(run)
		if output.size() >= limit:
			break
	return output


func _timeline_events(fact_days: Dictionary) -> Array[String]:
	var events: Array[Dictionary] = []
	for type_name: String in SIGNATURE_FACT_TYPES:
		var day := int(fact_days.get(type_name, -1))
		if day < 0:
			continue
		events.append({
			"day": day,
			"type": type_name,
			"label": FACT_LABELS.get(type_name, type_name),
		})
	events.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("day", 0)) == int(b.get("day", 0)):
				return String(a.get("type", "")) < String(b.get("type", ""))
			return int(a.get("day", 0)) < int(b.get("day", 0))
	)
	var output: Array[String] = []
	for event: Dictionary in events:
		output.append(
			"Day %d：%s"
			% [int(event.get("day", 0)), event.get("label", "")]
		)
	return output


func _round(value: float) -> float:
	return snappedf(value, 0.01)
