extends RefCounted
class_name LakeTownHistoryVariationRunner

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const QualityAuditorModel = preload(
	"res://scripts/dev/lake_town_history_quality_auditor.gd"
)

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const DEFAULT_OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_lake_town_history_variation_output.md"
)
const DEFAULT_QUALITY_OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_lake_town_history_quality_output.md"
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
const PRIOR_UNRESOLVED_HUNGER_SEEDS: Array[int] = [
	2026061503,
	2026061507,
	2026061509,
]
const HUNGER_CLOSURE_FACT_TYPES: Array[String] = [
	"chen_mi_collapsed_from_hunger",
	"ma_shen_emergency_food_for_chen_mi",
	"old_chen_sold_shop_goods_for_food",
	"old_chen_took_chen_mi_to_seek_help",
	"lake_town_emergency_credit_food",
	"chen_mi_health_crashed_from_hunger",
	"chen_mi_temporarily_stayed_with_ma_shen",
	"chen_mi_hunger_unresolved_but_recorded",
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
	"chen_mi_blocked_by_guard_seal",
	"guard_noticed_child_near_granary",
	"chen_mi_returned_empty_handed",
	"old_chen_saw_chen_mi_empty_handed",
	"chen_mi_weakened_from_enduring_hunger",
	"neighbor_noticed_silent_hungry_child",
	"old_chen_tried_to_delay_debt",
	"creditor_refused_delay_request",
	"chen_mi_found_other_family_tracks",
	"market_rumor_about_other_hungry_family",
	"old_chen_shop_forced_abnormal_closure",
	"old_chen_shop_half_open_under_debt",
	"ma_shen_early_help_became_household_memory",
	"old_chen_credit_purchase_raised_debt_pressure",
	"old_chen_withheld_delay_request",
	"chen_mi_collapsed_from_hunger",
	"ma_shen_emergency_food_for_chen_mi",
	"old_chen_sold_shop_goods_for_food",
	"old_chen_took_chen_mi_to_seek_help",
	"lake_town_emergency_credit_food",
	"chen_mi_health_crashed_from_hunger",
	"chen_mi_temporarily_stayed_with_ma_shen",
	"chen_mi_hunger_unresolved_but_recorded",
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
	"chen_mi_blocked_by_guard_seal": "陈米被守卫封条挡回",
	"guard_noticed_child_near_granary": "守卫注意到粮仓外的孩子",
	"chen_mi_returned_empty_handed": "陈米空手回到店门口",
	"old_chen_saw_chen_mi_empty_handed": "老陈看见陈米空手回来",
	"chen_mi_weakened_from_enduring_hunger": "陈米因长期饥饿变虚弱",
	"neighbor_noticed_silent_hungry_child": "邻居注意到沉默的孩子",
	"old_chen_tried_to_delay_debt": "老陈请求推迟债务",
	"creditor_refused_delay_request": "刘账房拒绝延期",
	"chen_mi_found_other_family_tracks": "陈米发现陌生家庭的脚印",
	"market_rumor_about_other_hungry_family": "集市传出另一户挨饿家庭的传闻",
	"old_chen_shop_forced_abnormal_closure": "老陈店铺异常关闭",
	"old_chen_shop_half_open_under_debt": "老陈店铺在债务下半开",
	"ma_shen_early_help_became_household_memory": "玛婶的提前帮助成为家庭记忆",
	"old_chen_credit_purchase_raised_debt_pressure": "赊账买粮抬高后续债务压力",
	"old_chen_withheld_delay_request": "老陈没有说出口延期请求",
	"chen_mi_collapsed_from_hunger": "陈米倒在店门口",
	"ma_shen_emergency_food_for_chen_mi": "玛婶紧急给陈米送食",
	"old_chen_sold_shop_goods_for_food": "老陈卖掉店内物品换食物",
	"old_chen_took_chen_mi_to_seek_help": "老陈带陈米离店求助",
	"lake_town_emergency_credit_food": "湖湾镇提供临时救济赊食",
	"chen_mi_health_crashed_from_hunger": "陈米健康因饥饿严重恶化",
	"chen_mi_temporarily_stayed_with_ma_shen": "陈米暂住玛婶家",
	"chen_mi_hunger_unresolved_but_recorded": "持续饥饿被记录为坏结果",
}

var simulator := SimulatorModel.new()
var quality_auditor := QualityAuditorModel.new()


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
	var signatures: Array[Dictionary] = []
	var states: Array[WorldSimState] = []
	for seed_value: Variant in seeds:
		var run := run_seed(int(seed_value), days)
		if run.is_empty():
			continue
		runs.append(run)
		var signature := run.get("signature", {}) as Dictionary
		signatures.append(signature)
		states.append(run.get("state") as WorldSimState)
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
	var quality_audit := quality_auditor.audit_batch(signatures, states)
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
		"quality_audit": quality_audit,
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
		"outcome_reason": "",
		"quality_flags": [],
		"branch_closure_depth": 0,
		"consequence_depth": 0,
	}
	var classification := classify_history_outcome_details(signature)
	signature["outcome_class"] = classification.get("class", "")
	signature["outcome_reason"] = classification.get("reason", "")
	var quality := quality_auditor.audit_state(state)
	signature["quality_flags"] = (
		quality.get("quality_flags", []) as Array
	).duplicate()
	signature["branch_closure_depth"] = int(
		quality.get("branch_closure_depth", 0)
	)
	signature["consequence_depth"] = int(
		quality.get("consequence_depth", 0)
	)
	return signature


func classify_history_outcome(signature: Dictionary) -> String:
	return String(
		classify_history_outcome_details(signature).get("class", "")
	)


func classify_history_outcome_details(
		signature: Dictionary
	) -> Dictionary:
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
	var families: Array[String] = []
	if _fact_happened(fact_days, "guard_locked_abandoned_granary"):
		families.append("guard")
	if _fact_happened(fact_days, "chen_mi_found_empty_granary"):
		families.append("empty_granary")
	if _fact_happened(fact_days, "chen_mi_endured_hunger"):
		families.append("silent_hunger")
	if _fact_happened(fact_days, "creditor_pressed_before_theft"):
		families.append("early_debt")
	if _fact_happened(fact_days, "other_family_took_granary_grain"):
		families.append("other_family")
	if theft:
		families.append("theft")
	var family_text := ", ".join(families)
	if theft and sick and debt_notice:
		return {
			"class": "theft_sickness_debt",
			"reason": "取粮、生病与正式催债事实连续出现。",
		}
	if theft and helped:
		return {
			"class": "theft_helped_recovery",
			"reason": "取粮后出现邻里食物帮助或恢复事实。",
		}
	if not theft:
		if families.size() >= 3:
			return {
				"class": "mixed_interwoven",
				"reason": "多条结构化路径交织：%s。" % family_text,
			}
		if _fact_happened(fact_days, "guard_locked_abandoned_granary"):
			if _fact_happened(
				fact_days,
				"guard_noticed_child_near_granary"
			):
				return {
					"class": "guard_locked_guard_attention",
					"reason": "封仓后陈米被挡回，守卫随后注意到她。",
				}
			if _fact_happened(
				fact_days,
				"chen_mi_blocked_by_guard_seal"
			):
				return {
					"class": "guard_locked_child_blocked",
					"reason": "封仓后陈米被封条挡回并留下后续痕迹。",
				}
			return {
				"class": "guard_locked_unresolved",
				"reason": "守卫封仓已发生，但尚未形成孩子侧后续。",
			}
		if _fact_happened(fact_days, "other_family_took_granary_grain"):
			return {
				"class": "other_family_grain_conflict",
				"reason": "另一个家庭先取粮，并留下脚印或市场传闻。",
			}
		if _fact_happened(fact_days, "chen_mi_found_empty_granary"):
			return {
				"class": "empty_granary_returned_empty",
				"reason": "陈米发现空粮仓后空手返回。",
			}
		if _fact_happened(fact_days, "chen_mi_endured_hunger"):
			return {
				"class": "silent_hunger_decline",
				"reason": "陈米忍耐饥饿并出现虚弱或社会注意。",
			}
		if _fact_happened(
			fact_days,
			"creditor_refused_delay_request"
		):
			return {
				"class": "early_debt_negotiation_failed",
				"reason": "提前催债后，老陈的延期请求被拒绝。",
			}
		if _fact_happened(
			fact_days,
			"old_chen_shop_half_open_under_debt"
		):
			return {
				"class": "half_open_under_debt",
				"reason": "店铺恢复为半开，但高债务仍持续。",
			}
		if _fact_happened(
			fact_days,
			"old_chen_shop_forced_abnormal_closure"
		):
			return {
				"class": "forced_shop_closure_no_theft",
				"reason": "未发生取粮，但极端压力与债务迫使店铺异常关闭。",
			}
		if _fact_happened(fact_days, "ma_shen_helped_before_theft"):
			return {
				"class": "early_neighbor_help_no_theft",
				"reason": "玛婶在取粮前提供食物帮助。",
			}
		if _fact_happened(fact_days, "creditor_pressed_before_theft"):
			return {
				"class": "early_debt_pressure",
				"reason": "取粮前已出现结构化催债压力。",
			}
		if _fact_happened(fact_days, "old_chen_bought_food_on_credit"):
			return {
				"class": "credit_purchase_delayed_crisis",
				"reason": "老陈通过赊账补充食物，危机被推迟。",
			}
	if _fact_happened(
		fact_days,
		"old_chen_shop_half_open_under_debt"
	):
		return {
			"class": "half_open_under_debt",
			"reason": "取粮路径与店铺带债半开状态同时存在。",
		}
	return {
		"class": "mixed_interwoven",
		"reason": (
			"实际事实未落入单一主路径；已发生路径：%s。"
			% (family_text if family_text != "" else "基础压力演化")
		),
	}


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
		"outcome_reason": signature.get("outcome_reason", ""),
		"quality_flags": signature.get("quality_flags", []),
		"branch_closure_depth": signature.get(
			"branch_closure_depth",
			0
		),
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
		lines.append(
			"- 分类原因：%s"
			% signature.get("outcome_reason", "")
		)
		lines.append(
			"- 质量标记：`%s`；branch_closure_depth：%d"
			% [
				JSON.stringify(signature.get("quality_flags", [])),
				int(signature.get("branch_closure_depth", 0)),
			]
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
	var quality := batch.get("quality_audit", {}) as Dictionary
	lines.append("## 历史质量审计摘要")
	lines.append("")
	lines.append("- 批量 seed：%d" % int(quality.get("seed_count", 0)))
	lines.append(
		"- 无质量警告 seed：%d"
		% int(quality.get("no_warning_seed_count", 0))
	)
	lines.append(
		"- 存在悬空替代路径 seed：%d"
		% int(quality.get("dangling_major_fact_count", 0))
	)
	lines.append(
		"- 存在极端饥饿未闭合 seed：%d"
		% int(quality.get("unresolved_extreme_hunger_count", 0))
	)
	lines.append(
		"- impossible_shop_state：%d"
		% int(quality.get("impossible_shop_state_count", 0))
	)
	lines.append(
		"- 存在店铺状态矛盾 seed：%d"
		% int(quality.get("contradiction_seed_count", 0))
	)
	lines.append(
		"- 平均 branch_closure_depth：%.2f"
		% float(quality.get("average_branch_closure_depth", 0.0))
	)
	lines.append(
		"- bad_hunger_outcome：%d；emergency_food：%d；temporary_relocation：%d"
		% [
			int(quality.get("bad_hunger_outcome_count", 0)),
			int(quality.get("emergency_food_count", 0)),
			int(quality.get("temporary_relocation_count", 0)),
		]
	)
	lines.append("")
	lines.append("## 替代路径闭合样例")
	lines.append("")
	for run_value: Variant in _select_closure_samples(
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
		for event: String in _timeline_events(
			signature.get("fact_days", {}) as Dictionary
		):
			lines.append("- " + event)
		lines.append(
			"- 质量：%s；闭合深度：%d"
			% [
				(
					"closed"
					if (
						signature.get("quality_flags", []) as Array
					).is_empty()
					else JSON.stringify(
						signature.get("quality_flags", [])
					)
				),
				int(signature.get("branch_closure_depth", 0)),
			]
		)
		lines.append("")
	lines.append("## 极端饥饿闭合样例")
	lines.append("")
	for seed_value: int in PRIOR_UNRESOLVED_HUNGER_SEEDS:
		var run := _find_run_by_seed(
			batch.get("runs", []) as Array,
			seed_value
		)
		if run.is_empty():
			continue
		var signature := run.get("signature", {}) as Dictionary
		lines.append("### Seed %d" % seed_value)
		lines.append("")
		lines.append("- 原问题：极端饥饿未闭合")
		lines.append("- 新后续：")
		var hunger_events := _hunger_timeline_events(
			signature.get("fact_days", {}) as Dictionary
		)
		if hunger_events.is_empty():
			lines.append("  - 未生成极端饥饿闭合事实")
		else:
			for event: String in hunger_events:
				lines.append("  - " + event)
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


func export_history_quality_report(
		batch: Dictionary,
		output_path: String = DEFAULT_QUALITY_OUTPUT_PATH
	) -> void:
	var quality := batch.get("quality_audit", {}) as Dictionary
	var text := quality_auditor.build_quality_report(quality)
	var absolute_path := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"[LakeTownHistoryVariationRunner] Cannot write %s"
			% output_path
		)
		return
	file.store_string(text)


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
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	return {
		"chen_mi_hunger": _round(float(chen_mi.get("hunger", 0.0))),
		"chen_mi_fear": _round(float(chen_mi.get("fear", 0.0))),
		"chen_mi_health": _round(float(chen_mi.get("health", 0.0))),
		"old_chen_stress": _round(float(old_chen.get("stress", 0.0))),
		"old_chen_debt": _round(float(old_chen.get("debt", 0.0))),
		"old_chen_family_food": _round(
			float(old_chen.get("family_food", 0.0))
		),
		"chen_mi_location_id": String(
			chen_mi.get("location_id", "")
		),
		"old_chen_location_id": String(
			old_chen.get("location_id", "")
		),
		"shop_open": bool(shop_state.get("is_open", false)),
		"shop_partial_open": bool(shop_state.get("partial_open", false)),
		"granary_stock": int(
			roundf(float(granary_state.get("spoiled_grain_stock", 0.0)))
		),
		"extreme_hunger_days": int(
			hunger_state.get("extreme_hunger_days", 0)
		),
		"chen_mi_temporarily_relocated": bool(
			hunger_state.get(
				"chen_mi_temporarily_relocated",
				false
			)
		),
		"emergency_food_received": bool(
			hunger_state.get("emergency_food_received", false)
		),
		"critical_health_decline_recorded": bool(
			hunger_state.get(
				"critical_health_decline_recorded",
				false
			)
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


func _select_closure_samples(
		runs: Array,
		limit: int
	) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var required_groups: Array = [
		[
			"chen_mi_blocked_by_guard_seal",
			"guard_noticed_child_near_granary",
		],
		[
			"chen_mi_returned_empty_handed",
			"old_chen_saw_chen_mi_empty_handed",
		],
		[
			"chen_mi_weakened_from_enduring_hunger",
			"neighbor_noticed_silent_hungry_child",
		],
		[
			"old_chen_tried_to_delay_debt",
			"creditor_refused_delay_request",
			"old_chen_withheld_delay_request",
		],
		[
			"chen_mi_found_other_family_tracks",
			"market_rumor_about_other_hungry_family",
		],
	]
	for group_value: Variant in required_groups:
		var group := group_value as Array
		for run_value: Variant in runs:
			var run := run_value as Dictionary
			if run in output:
				continue
			var signature := run.get("signature", {}) as Dictionary
			var fact_days := signature.get("fact_days", {}) as Dictionary
			if _first_fact_day(fact_days, group) < 0:
				continue
			output.append(run)
			break
		if output.size() >= limit:
			return output
	var seen_outcomes: Dictionary = {}
	for run: Dictionary in output:
		var signature := run.get("signature", {}) as Dictionary
		seen_outcomes[String(signature.get("outcome_class", ""))] = true
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		if run in output:
			continue
		var signature := run.get("signature", {}) as Dictionary
		if int(signature.get("branch_closure_depth", 0)) <= 0:
			continue
		var outcome := String(signature.get("outcome_class", ""))
		if seen_outcomes.has(outcome):
			continue
		seen_outcomes[outcome] = true
		output.append(run)
		if output.size() >= limit:
			return output
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		var signature := run.get("signature", {}) as Dictionary
		if (
			int(signature.get("branch_closure_depth", 0)) <= 0
			or run in output
		):
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


func _hunger_timeline_events(
		fact_days: Dictionary
	) -> Array[String]:
	var events: Array[Dictionary] = []
	for type_name: String in HUNGER_CLOSURE_FACT_TYPES:
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


func _find_run_by_seed(runs: Array, seed_value: int) -> Dictionary:
	for run_value: Variant in runs:
		var run := run_value as Dictionary
		if int(run.get("seed", 0)) == seed_value:
			return run
	return {}


func _round(value: float) -> float:
	return snappedf(value, 0.01)
