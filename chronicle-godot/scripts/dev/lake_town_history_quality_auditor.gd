extends RefCounted
class_name LakeTownHistoryQualityAuditor

const MAJOR_BRANCH_CLOSURES := {
	"guard_locked_abandoned_granary": [
		"chen_mi_blocked_by_guard_seal",
		"guard_noticed_child_near_granary",
	],
	"chen_mi_found_empty_granary": [
		"chen_mi_returned_empty_handed",
		"old_chen_saw_chen_mi_empty_handed",
	],
	"chen_mi_endured_hunger": [
		"chen_mi_weakened_from_enduring_hunger",
		"neighbor_noticed_silent_hungry_child",
	],
	"creditor_pressed_before_theft": [
		"old_chen_tried_to_delay_debt",
		"creditor_refused_delay_request",
		"old_chen_withheld_delay_request",
	],
	"other_family_took_granary_grain": [
		"chen_mi_found_other_family_tracks",
		"market_rumor_about_other_hungry_family",
	],
	"ma_shen_helped_before_theft": [
		"ma_shen_early_help_became_household_memory",
	],
	"old_chen_bought_food_on_credit": [
		"old_chen_credit_purchase_raised_debt_pressure",
	],
}
const HUNGER_FOLLOWUPS: Array[String] = [
	"chen_mi_blocked_by_guard_seal",
	"guard_noticed_child_near_granary",
	"chen_mi_returned_empty_handed",
	"old_chen_saw_chen_mi_empty_handed",
	"chen_mi_weakened_from_enduring_hunger",
	"neighbor_noticed_silent_hungry_child",
	"ma_shen_brought_porridge",
	"ma_shen_helped_before_theft",
	"chen_mi_stabilized_after_food_help",
	"chen_mi_took_spoiled_grain",
	"chen_mi_ate_spoiled_grain",
	"chen_mi_fell_sick_from_spoiled_grain",
	"chen_mi_found_empty_granary",
	"chen_mi_endured_hunger",
	"chen_mi_found_other_family_tracks",
]


func audit_history_signature(signature: Dictionary) -> Dictionary:
	var flags: Array[String] = []
	var fact_days := signature.get("fact_days", {}) as Dictionary
	var dangling: Array[String] = []
	for major_type: String in MAJOR_BRANCH_CLOSURES:
		if not _signature_fact_happened(fact_days, major_type):
			continue
		var closed := false
		for closure_value: Variant in MAJOR_BRANCH_CLOSURES[major_type]:
			if _signature_fact_happened(
				fact_days,
				String(closure_value)
			):
				closed = true
				break
		if not closed:
			dangling.append(major_type)
	if not dangling.is_empty():
		flags.append("dangling_major_fact")

	var outcome := String(signature.get("outcome_class", ""))
	var reason := String(signature.get("outcome_reason", "")).strip_edges()
	var unclassified := (
		outcome == "mixed_or_unclassified"
		or (outcome == "mixed_interwoven" and reason == "")
	)
	if unclassified:
		flags.append("unclassified_without_reason")

	var final_state := signature.get("final_state", {}) as Dictionary
	var impossible_shop_state := _impossible_shop_from_values(
		final_state,
		fact_days
	)
	if impossible_shop_state:
		flags.append("impossible_shop_state")
	return {
		"seed": int(signature.get("seed", 0)),
		"quality_flags": flags,
		"dangling_major_fact": not dangling.is_empty(),
		"dangling_major_fact_types": dangling,
		"impossible_shop_state": impossible_shop_state,
		"unclassified_without_reason": unclassified,
		"branch_closure_depth": int(
			signature.get("branch_closure_depth", 0)
		),
		"consequence_depth": int(
			signature.get("consequence_depth", 0)
		),
		"contradiction_flags": [],
		"unresolved_extreme_hunger": false,
		"notes": [],
	}


func audit_state(state: Variant) -> Dictionary:
	if not state is WorldSimState:
		return {
			"seed": 0,
			"quality_flags": ["invalid_world_state"],
			"dangling_major_fact": false,
			"dangling_major_fact_types": [],
			"impossible_shop_state": false,
			"unresolved_extreme_hunger": false,
			"unclassified_without_reason": false,
			"branch_closure_depth": 0,
			"consequence_depth": 0,
			"contradiction_flags": [],
			"notes": ["state is not WorldSimState"],
		}
	var fact_types := _fact_type_set(state)
	var dangling: Array[String] = []
	for major_type: String in MAJOR_BRANCH_CLOSURES:
		if not fact_types.has(major_type):
			continue
		var closed := false
		for closure_value: Variant in MAJOR_BRANCH_CLOSURES[major_type]:
			if fact_types.has(String(closure_value)):
				closed = true
				break
		if not closed:
			dangling.append(major_type)

	var old_chen: Dictionary = state.get_npc("old_chen")
	var chen_mi: Dictionary = state.get_npc("chen_mi")
	var shop_state := (
		state.get_location("old_chen_shop").get("state", {})
		as Dictionary
	)
	var impossible_shop_state := (
		float(old_chen.get("stress", 0.0)) >= 95.0
		and float(old_chen.get("debt", 0.0)) >= 90.0
		and bool(shop_state.get("is_open", false))
		and not (
			bool(shop_state.get("partial_open", false))
			and fact_types.has("old_chen_shop_half_open_under_debt")
		)
	)
	var unresolved_extreme_hunger := (
		float(chen_mi.get("hunger", 0.0)) >= 95.0
		and not _has_any_fact(fact_types, HUNGER_FOLLOWUPS)
	)
	var contradictions: Array[String] = []
	if (
		not bool(shop_state.get("is_open", true))
		and bool(shop_state.get("partial_open", false))
	):
		contradictions.append("shop_closed_and_partial_open")
	if (
		fact_types.has("old_chen_shop_forced_abnormal_closure")
		and bool(shop_state.get("is_open", false))
		and not fact_types.has("old_chen_reopened_shop_half_day")
	):
		contradictions.append("forced_closure_but_shop_open")

	var flags: Array[String] = []
	if not dangling.is_empty():
		flags.append("dangling_major_fact")
	if impossible_shop_state:
		flags.append("impossible_shop_state")
	if unresolved_extreme_hunger:
		flags.append("unresolved_extreme_hunger")
	if not contradictions.is_empty():
		flags.append("contradiction_flags")
	var notes: Array[String] = []
	for type_name: String in dangling:
		notes.append("%s lacks a structured follow-up" % type_name)
	return {
		"seed": state.seed,
		"quality_flags": flags,
		"dangling_major_fact": not dangling.is_empty(),
		"dangling_major_fact_types": dangling,
		"impossible_shop_state": impossible_shop_state,
		"unresolved_extreme_hunger": unresolved_extreme_hunger,
		"unclassified_without_reason": false,
		"branch_closure_depth": _branch_closure_depth(state),
		"consequence_depth": _consequence_depth(state),
		"contradiction_flags": contradictions,
		"notes": notes,
	}


func audit_batch(
		signatures: Array,
		states: Array = []
	) -> Dictionary:
	var audits: Array[Dictionary] = []
	var impossible_count := 0
	var dangling_count := 0
	var hunger_count := 0
	var contradiction_count := 0
	var unclassified_count := 0
	var no_warning_count := 0
	var closure_total := 0
	for index: int in range(signatures.size()):
		var signature := signatures[index] as Dictionary
		var audit := (
			audit_state(states[index])
			if index < states.size() and states[index] is WorldSimState
			else audit_history_signature(signature)
		)
		var signature_audit := audit_history_signature(signature)
		if bool(signature_audit.get("unclassified_without_reason", false)):
			audit["unclassified_without_reason"] = true
			var flags := audit.get("quality_flags", []) as Array
			if not "unclassified_without_reason" in flags:
				flags.append("unclassified_without_reason")
			audit["quality_flags"] = flags
		audits.append(audit)
		impossible_count += (
			1 if bool(audit.get("impossible_shop_state", false)) else 0
		)
		dangling_count += (
			1 if bool(audit.get("dangling_major_fact", false)) else 0
		)
		hunger_count += (
			1
			if bool(audit.get("unresolved_extreme_hunger", false))
			else 0
		)
		contradiction_count += (
			1
			if not (
				audit.get("contradiction_flags", []) as Array
			).is_empty()
			else 0
		)
		unclassified_count += (
			1
			if bool(audit.get("unclassified_without_reason", false))
			else 0
		)
		closure_total += int(audit.get("branch_closure_depth", 0))
		if (audit.get("quality_flags", []) as Array).is_empty():
			no_warning_count += 1
	var seed_count := audits.size()
	return {
		"seed_count": seed_count,
		"audits": audits,
		"no_warning_seed_count": no_warning_count,
		"impossible_shop_state_count": impossible_count,
		"dangling_major_fact_count": dangling_count,
		"unresolved_extreme_hunger_count": hunger_count,
		"contradiction_seed_count": contradiction_count,
		"unclassified_without_reason_count": unclassified_count,
		"average_branch_closure_depth": (
			snappedf(float(closure_total) / float(seed_count), 0.01)
			if seed_count > 0
			else 0.0
		),
	}


func build_quality_report(batch_result: Dictionary) -> String:
	var lines: Array[String] = [
		"# 湖湾镇历史质量审计输出",
		"",
		"## 历史质量审计摘要",
		"",
		"- 批量 seed：%d" % int(batch_result.get("seed_count", 0)),
		"- 无质量警告 seed：%d" % int(
			batch_result.get("no_warning_seed_count", 0)
		),
		"- 存在悬空替代路径 seed：%d" % int(
			batch_result.get("dangling_major_fact_count", 0)
		),
		"- 存在极端饥饿未闭合 seed：%d" % int(
			batch_result.get("unresolved_extreme_hunger_count", 0)
		),
		"- 存在店铺状态矛盾 seed：%d" % int(
			batch_result.get("contradiction_seed_count", 0)
		),
		"- impossible_shop_state：%d" % int(
			batch_result.get("impossible_shop_state_count", 0)
		),
		"- 无理由未分类：%d" % int(
			batch_result.get("unclassified_without_reason_count", 0)
		),
		"- 平均 branch_closure_depth：%.2f" % float(
			batch_result.get("average_branch_closure_depth", 0.0)
		),
		"",
		"## 每个 seed 的审计结果",
		"",
	]
	for audit_value: Variant in batch_result.get("audits", []):
		var audit := audit_value as Dictionary
		lines.append("### Seed %d" % int(audit.get("seed", 0)))
		lines.append("")
		lines.append(
			"- quality_flags：`%s`"
			% JSON.stringify(audit.get("quality_flags", []))
		)
		lines.append(
			"- branch_closure_depth：%d"
			% int(audit.get("branch_closure_depth", 0))
		)
		lines.append(
			"- consequence_depth：%d"
			% int(audit.get("consequence_depth", 0))
		)
		lines.append(
			"- dangling_major_fact：%s"
			% str(bool(audit.get("dangling_major_fact", false)))
		)
		lines.append(
			"- impossible_shop_state：%s"
			% str(bool(audit.get("impossible_shop_state", false)))
		)
		lines.append("")
	return "\n".join(lines).strip_edges() + "\n"


func _fact_type_set(state: WorldSimState) -> Dictionary:
	var output: Dictionary = {}
	for fact in state.world_facts:
		output[fact.type] = true
	return output


func _branch_closure_depth(state: WorldSimState) -> int:
	var count := 0
	for fact in state.world_facts:
		if String(fact.data.get("branch_closure_key", "")) != "":
			count += 1
	return count


func _consequence_depth(state: WorldSimState) -> int:
	var reachable: Dictionary = {}
	for fact in state.world_facts:
		if MAJOR_BRANCH_CLOSURES.has(fact.type):
			reachable[fact.id] = true
	var count := 0
	for fact in state.world_facts:
		if reachable.has(fact.id):
			continue
		for cause_id: String in fact.cause_fact_ids:
			if reachable.has(cause_id):
				reachable[fact.id] = true
				count += 1
				break
	return count


func _signature_fact_happened(
		fact_days: Dictionary,
		type_name: String
	) -> bool:
	return int(fact_days.get(type_name, -1)) >= 0


func _impossible_shop_from_values(
		final_state: Dictionary,
		fact_days: Dictionary
	) -> bool:
	return (
		float(final_state.get("old_chen_stress", 0.0)) >= 95.0
		and float(final_state.get("old_chen_debt", 0.0)) >= 90.0
		and bool(final_state.get("shop_open", false))
		and not (
			bool(final_state.get("shop_partial_open", false))
			and _signature_fact_happened(
				fact_days,
				"old_chen_shop_half_open_under_debt"
			)
		)
	)


func _has_any_fact(
		fact_types: Dictionary,
		type_names: Array[String]
	) -> bool:
	for type_name: String in type_names:
		if fact_types.has(type_name):
			return true
	return false
