extends RefCounted
class_name LakeTownBranchClosureSystem

const MICRO_REGION_ID := "lake_town"
const SHOP_ID := "old_chen_shop"
const GRANARY_ID := "abandoned_granary"
const MARKET_ID := "lake_town_market"
const OLD_CHEN_ID := "old_chen"
const CHEN_MI_ID := "chen_mi"
const MA_SHEN_ID := "ma_shen"
const LIU_ZHANGFANG_ID := "liu_zhangfang"

const CLOSURE_IDS: Array[String] = [
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
]


func tick_branch_closure(state: Variant) -> Array:
	var results: Array[Dictionary] = []
	if not state is WorldSimState:
		return results
	if not state.micro_state.has("seed_profile"):
		return results
	_ensure_closure_state(state)
	for candidate_value: Variant in build_branch_closure_candidates(state):
		var candidate := candidate_value as Dictionary
		var result := apply_branch_closure(
			state,
			String(candidate.get("id", ""))
		)
		if bool(result.get("ok", false)):
			results.append(result)
	return results


func build_branch_closure_candidates(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	if not state.micro_state.has("seed_profile"):
		return output
	_ensure_closure_state(state)
	for closure_id: String in CLOSURE_IDS:
		if _can_apply_closure(state, closure_id):
			output.append({
				"id": closure_id,
				"closure_key": closure_id,
				"source": "lake_town_structured_history",
			})
	return output


func apply_branch_closure(
		state: Variant,
		closure_id: String
	) -> Dictionary:
	var result := _base_result(closure_id)
	if not state is WorldSimState:
		result["error"] = "invalid_world_state"
		return result
	if not state.micro_state.has("seed_profile"):
		result["error"] = "profiled_simulation_required"
		return result
	_ensure_closure_state(state)
	if not _can_apply_closure(state, closure_id):
		result["error"] = "missing_required_state"
		return result

	match closure_id:
		"chen_mi_blocked_by_guard_seal":
			_apply_chen_mi_blocked_by_guard_seal(state, result)
		"guard_noticed_child_near_granary":
			_apply_guard_noticed_child(state, result)
		"chen_mi_returned_empty_handed":
			_apply_chen_mi_returned_empty_handed(state, result)
		"old_chen_saw_chen_mi_empty_handed":
			_apply_old_chen_saw_empty_handed(state, result)
		"chen_mi_weakened_from_enduring_hunger":
			_apply_chen_mi_weakened(state, result)
		"neighbor_noticed_silent_hungry_child":
			_apply_neighbor_noticed_silent_child(state, result)
		"old_chen_tried_to_delay_debt":
			_apply_old_chen_tried_to_delay_debt(state, result)
		"creditor_refused_delay_request":
			_apply_creditor_refused_delay(state, result)
		"chen_mi_found_other_family_tracks":
			_apply_chen_mi_found_other_family_tracks(state, result)
		"market_rumor_about_other_hungry_family":
			_apply_market_rumor_about_other_family(state, result)
		"old_chen_shop_forced_abnormal_closure":
			_apply_forced_abnormal_closure(state, result)
		"old_chen_shop_half_open_under_debt":
			_apply_half_open_under_debt(state, result)
		"ma_shen_early_help_became_household_memory":
			_apply_early_help_household_memory(state, result)
		"old_chen_credit_purchase_raised_debt_pressure":
			_apply_credit_purchase_debt_pressure(state, result)
		"old_chen_withheld_delay_request":
			_apply_old_chen_withheld_delay_request(state, result)
		_:
			result["error"] = "unknown_branch_closure"
			return result
	result["ok"] = true
	return result


func has_branch_closure_happened(
		state: Variant,
		closure_key: String
	) -> bool:
	if not state is WorldSimState:
		return false
	var closure_state := state.micro_state.get(
		"branch_closure_state",
		{}
	) as Dictionary
	for entry_value: Variant in closure_state.get("closure_history", []):
		var entry := entry_value as Dictionary
		if String(entry.get("closure_key", "")) == closure_key:
			return true
	return _has_fact_type(state, closure_key)


func record_branch_closure(
		state: Variant,
		closure_key: String,
		fact_id: String
	) -> void:
	if (
		not state is WorldSimState
		or closure_key == ""
		or fact_id == ""
	):
		return
	_ensure_closure_state(state)
	var closure_state := state.micro_state.get(
		"branch_closure_state",
		{}
	) as Dictionary
	var history := closure_state.get("closure_history", []) as Array
	for entry_value: Variant in history:
		var entry := entry_value as Dictionary
		if String(entry.get("closure_key", "")) == closure_key:
			return
	history.append({
		"closure_key": closure_key,
		"fact_id": fact_id,
		"day": state.day,
	})
	closure_state["closure_history"] = history
	closure_state["last_closure_day"] = state.day
	state.micro_state["branch_closure_state"] = closure_state


func _ensure_closure_state(state: WorldSimState) -> void:
	var closure_state := state.micro_state.get(
		"branch_closure_state",
		{}
	) as Dictionary
	if not closure_state.has("closure_history"):
		closure_state["closure_history"] = []
	if not closure_state.has("last_closure_day"):
		closure_state["last_closure_day"] = -1
	state.micro_state["branch_closure_state"] = closure_state


func _can_apply_closure(
		state: WorldSimState,
		closure_id: String
	) -> bool:
	if has_branch_closure_happened(state, closure_id):
		return false
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var ma_shen := state.get_npc(MA_SHEN_ID)
	var creditor := state.get_npc(LIU_ZHANGFANG_ID)
	var shop_state := (
		state.get_location(SHOP_ID).get("state", {})
		as Dictionary
	)
	var market_state := (
		state.get_location(MARKET_ID).get("state", {})
		as Dictionary
	)
	match closure_id:
		"chen_mi_blocked_by_guard_seal":
			return (
				_has_fact_type(state, "guard_locked_abandoned_granary")
				and float(chen_mi.get("hunger", 0.0)) >= 75.0
				and not _has_fact_type(
					state,
					"chen_mi_took_spoiled_grain"
				)
				and not _has_fact_type(
					state,
					"chen_mi_found_empty_granary"
				)
			)
		"guard_noticed_child_near_granary":
			return (
				_days_since_fact(
					state,
					"chen_mi_blocked_by_guard_seal"
				) >= 1
				and float(
					state.micro_state.get("guard_pressure", 0.0)
				) >= 60.0
			)
		"chen_mi_returned_empty_handed":
			return (
				_days_since_fact(
					state,
					"chen_mi_found_empty_granary"
				) >= 1
				and float(chen_mi.get("hunger", 0.0)) >= 75.0
			)
		"old_chen_saw_chen_mi_empty_handed":
			return (
				_has_fact_type(state, "chen_mi_returned_empty_handed")
				and float(old_chen.get("stress", 0.0)) >= 75.0
			)
		"chen_mi_weakened_from_enduring_hunger":
			return (
				_days_since_fact(state, "chen_mi_endured_hunger") >= 1
				and float(chen_mi.get("hunger", 0.0)) >= 90.0
			)
		"neighbor_noticed_silent_hungry_child":
			return (
				_has_fact_type(
					state,
					"chen_mi_weakened_from_enduring_hunger"
				)
				and (
					float(
						state.micro_state.get(
							"neighbor_attention",
							0.0
						)
					) >= 55.0
					or float(ma_shen.get("concern", 0.0)) >= 55.0
				)
			)
		"old_chen_tried_to_delay_debt":
			return (
				_has_fact_type(state, "creditor_pressed_before_theft")
				and float(old_chen.get("debt", 0.0)) >= 70.0
				and (
					float(old_chen.get("help_seeking", 0.0)) >= 55.0
					or float(old_chen.get("pride", 100.0)) <= 45.0
				)
			)
		"creditor_refused_delay_request":
			return (
				_days_since_fact(
					state,
					"old_chen_tried_to_delay_debt"
				) >= 1
				and (
					float(creditor.get("strictness", 0.0)) >= 62.0
					or float(creditor.get("patience", 100.0)) <= 35.0
				)
			)
		"chen_mi_found_other_family_tracks":
			return (
				_has_fact_type(
					state,
					"other_family_took_granary_grain"
				)
				and (
					float(chen_mi.get("hunger", 0.0)) >= 70.0
					or _has_status(
						chen_mi,
						"hesitating_to_take_grain"
					)
					or _has_fact_type(
						state,
						"chen_mi_found_empty_granary"
					)
				)
			)
		"market_rumor_about_other_hungry_family":
			return (
				_has_fact_type(
					state,
					"other_family_took_granary_grain"
				)
				and (
					float(market_state.get("rumor_speed", 0.0)) >= 55.0
					or float(
						market_state.get(
							"neighbor_help_level",
							100.0
						)
					) <= 45.0
				)
			)
		"old_chen_shop_forced_abnormal_closure":
			return (
				float(old_chen.get("stress", 0.0)) >= 95.0
				and float(old_chen.get("debt", 0.0)) >= 90.0
				and bool(shop_state.get("is_open", false))
				and not _has_fact_type(
					state,
					"old_chen_reopened_shop_half_day"
				)
			)
		"old_chen_shop_half_open_under_debt":
			return (
				_has_fact_type(
					state,
					"old_chen_reopened_shop_half_day"
				)
				and (
					float(old_chen.get("debt", 0.0)) >= 90.0
					or float(
						state.micro_state.get("debt_pressure", 0.0)
					) >= 85.0
				)
			)
		"ma_shen_early_help_became_household_memory":
			return (
				_days_since_fact(
					state,
					"ma_shen_helped_before_theft"
				) >= 1
			)
		"old_chen_credit_purchase_raised_debt_pressure":
			return (
				_days_since_fact(
					state,
					"old_chen_bought_food_on_credit"
				) >= 1
			)
		"old_chen_withheld_delay_request":
			return (
				_days_since_fact(
					state,
					"creditor_pressed_before_theft"
				) >= 1
				and not _has_fact_type(
					state,
					"old_chen_tried_to_delay_debt"
				)
				and float(old_chen.get("help_seeking", 0.0)) < 55.0
				and float(old_chen.get("pride", 100.0)) > 45.0
			)
	return false


func _apply_chen_mi_blocked_by_guard_seal(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 12.0,
		0.0,
		100.0
	)
	_add_status(chen_mi, "blocked_by_guard_seal")
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_closure_fact(
		state,
		"chen_mi_blocked_by_guard_seal",
		[CHEN_MI_ID, "wardens"],
		GRANARY_ID,
		_source_ids(state, ["guard_locked_abandoned_granary"]),
		{"chen_mi.fear_delta": 12.0},
		["guard_seal", "child", "hunger"]
	)
	var trace := _add_trace(
		state,
		"small_footprints_near_guard_seal",
		fact.id,
		GRANARY_ID,
		CHEN_MI_ID,
		["small_footprints", "guard_seal", "turned_back"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_guard_seal",
		CHEN_MI_ID,
		fact.id,
		0.9,
		["guard", "hunger", "blocked"]
	)
	_add_scene(
		state,
		"child_stopped_by_guard_seal_scene",
		"陈米被粮仓门上的守卫封条挡了回来",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_guard_noticed_child(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 10.0,
		0.0,
		100.0
	)
	_add_status(chen_mi, "noticed_near_granary")
	state.npcs[CHEN_MI_ID] = chen_mi
	var attention := state.micro_state.get("guard_attention", {}) as Dictionary
	attention["wardens"] = clampf(
		float(attention.get("wardens", 0.0)) + 20.0,
		0.0,
		100.0
	)
	state.micro_state["guard_attention"] = attention
	var fact := _add_closure_fact(
		state,
		"guard_noticed_child_near_granary",
		["wardens", CHEN_MI_ID],
		GRANARY_ID,
		_source_ids(state, ["chen_mi_blocked_by_guard_seal"]),
		{
			"wardens.guard_attention_delta": 20.0,
			"chen_mi.fear_delta": 10.0,
		},
		["guard", "child", "attention"]
	)
	var trace := _add_trace(
		state,
		"guard_question_marks_at_granary",
		fact.id,
		GRANARY_ID,
		"wardens",
		["guard_marks", "questions", "small_footprints"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_guard_questioning",
		CHEN_MI_ID,
		fact.id,
		0.95,
		["guard", "questioning", "fear"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_chen_mi_returned_empty_handed(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 8.0,
		0.0,
		100.0
	)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 5.0
	)
	_add_status(chen_mi, "returned_empty_handed")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.micro_state["health_pressure"] = clampf(
		float(state.micro_state.get("health_pressure", 0.0)) + 12.0,
		0.0,
		100.0
	)
	var fact := _add_closure_fact(
		state,
		"chen_mi_returned_empty_handed",
		[CHEN_MI_ID],
		SHOP_ID,
		_source_ids(state, ["chen_mi_found_empty_granary"]),
		{
			"chen_mi.fear_delta": 8.0,
			"chen_mi.health_delta": -5.0,
			"health_pressure_delta": 12.0,
		},
		["empty_granary", "child", "hunger"]
	)
	var trace := _add_trace(
		state,
		"empty_hands_at_shop_step",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["empty_hands", "shop_step", "hunger"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_returning_empty_handed",
		CHEN_MI_ID,
		fact.id,
		0.9,
		["empty_granary", "hunger", "return"]
	)
	_add_scene(
		state,
		"chen_mi_empty_handed_scene",
		"陈米空着手回到老陈店门口",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_old_chen_saw_empty_handed(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 9.0,
		0.0,
		100.0
	)
	_add_status(old_chen, "helpless_parent")
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_closure_fact(
		state,
		"old_chen_saw_chen_mi_empty_handed",
		[OLD_CHEN_ID, CHEN_MI_ID],
		SHOP_ID,
		_source_ids(state, ["chen_mi_returned_empty_handed"]),
		{"old_chen.stress_delta": 9.0},
		["family", "helpless_parent", "empty_handed"]
	)
	var trace := _add_trace(
		state,
		"old_chen_waited_at_door",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["waiting_parent", "shop_door", "empty_hands"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_chen_mi_empty_handed",
		OLD_CHEN_ID,
		fact.id,
		0.95,
		["daughter", "hunger", "helplessness"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_chen_mi_weakened(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 12.0
	)
	_add_status(chen_mi, "weakened_from_hunger")
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_closure_fact(
		state,
		"chen_mi_weakened_from_enduring_hunger",
		[CHEN_MI_ID],
		SHOP_ID,
		_source_ids(state, ["chen_mi_endured_hunger"]),
		{"chen_mi.health_delta": -12.0},
		["hunger", "weakness", "child"]
	)
	var trace := _add_trace(
		state,
		"child_sitting_silent_at_shop_step",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["silent_child", "weakness", "shop_step"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_long_hunger",
		CHEN_MI_ID,
		fact.id,
		0.95,
		["long_hunger", "weakness", "silence"]
	)
	_add_scene(
		state,
		"silent_hungry_child_scene",
		"陈米虚弱地坐在店门台阶上，一直没有说话",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_neighbor_noticed_silent_child(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var ma_shen := state.get_npc(MA_SHEN_ID)
	ma_shen["concern"] = clampf(
		float(ma_shen.get("concern", 0.0)) + 15.0,
		0.0,
		100.0
	)
	_add_status(ma_shen, "noticed_silent_hungry_child")
	state.npcs[MA_SHEN_ID] = ma_shen
	state.micro_state["rumor_pressure"] = clampf(
		float(state.micro_state.get("rumor_pressure", 0.0)) + 12.0,
		0.0,
		100.0
	)
	var fact := _add_closure_fact(
		state,
		"neighbor_noticed_silent_hungry_child",
		[MA_SHEN_ID, CHEN_MI_ID],
		SHOP_ID,
		_source_ids(
			state,
			["chen_mi_weakened_from_enduring_hunger"]
		),
		{
			"ma_shen.concern_delta": 15.0,
			"rumor_pressure_delta": 12.0,
		},
		["neighbor", "hunger", "social_attention"]
	)
	var trace := _add_trace(
		state,
		"neighbor_paused_near_shop_step",
		fact.id,
		SHOP_ID,
		MA_SHEN_ID,
		["neighbor_paused", "silent_child", "concern"]
	)
	var memory := _add_memory(
		state,
		"ma_shen_remembers_silent_child",
		MA_SHEN_ID,
		fact.id,
		0.85,
		["child", "hunger", "concern"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_old_chen_tried_to_delay_debt(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var creditor := state.get_npc(LIU_ZHANGFANG_ID)
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 2.0
	)
	creditor["patience"] = maxf(
		0.0,
		float(creditor.get("patience", 0.0)) - 5.0
	)
	state.npcs[OLD_CHEN_ID] = old_chen
	state.npcs[LIU_ZHANGFANG_ID] = creditor
	var fact := _add_closure_fact(
		state,
		"old_chen_tried_to_delay_debt",
		[OLD_CHEN_ID, LIU_ZHANGFANG_ID],
		SHOP_ID,
		_source_ids(state, ["creditor_pressed_before_theft"]),
		{
			"old_chen.stress_delta": -2.0,
			"liu_zhangfang.patience_delta": -5.0,
		},
		["debt", "negotiation", "delay_request"]
	)
	var trace := _add_trace(
		state,
		"rewritten_debt_note",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["rewritten_note", "delay_request", "debt"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_debt_negotiation",
		OLD_CHEN_ID,
		fact.id,
		0.85,
		["debt", "request", "shame"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_creditor_refused_delay(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 12.0,
		0.0,
		100.0
	)
	_add_status(old_chen, "debt_delay_refused")
	state.npcs[OLD_CHEN_ID] = old_chen
	state.micro_state["debt_pressure"] = clampf(
		float(state.micro_state.get("debt_pressure", 0.0)) + 18.0,
		0.0,
		100.0
	)
	var fact := _add_closure_fact(
		state,
		"creditor_refused_delay_request",
		[LIU_ZHANGFANG_ID, OLD_CHEN_ID],
		SHOP_ID,
		_source_ids(state, ["old_chen_tried_to_delay_debt"]),
		{
			"old_chen.stress_delta": 12.0,
			"debt_pressure_delta": 18.0,
		},
		["debt", "creditor", "refused_delay"]
	)
	var trace := _add_trace(
		state,
		"stamped_debt_notice",
		fact.id,
		SHOP_ID,
		LIU_ZHANGFANG_ID,
		["stamped_notice", "refused", "due_date"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_refused_delay",
		OLD_CHEN_ID,
		fact.id,
		0.95,
		["debt", "refusal", "pressure"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_chen_mi_found_other_family_tracks(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 7.0,
		0.0,
		100.0
	)
	_add_status(chen_mi, "found_other_family_tracks")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.micro_state["rumor_pressure"] = clampf(
		float(state.micro_state.get("rumor_pressure", 0.0)) + 8.0,
		0.0,
		100.0
	)
	var fact := _add_closure_fact(
		state,
		"chen_mi_found_other_family_tracks",
		[CHEN_MI_ID],
		GRANARY_ID,
		_source_ids(state, ["other_family_took_granary_grain"]),
		{
			"chen_mi.fear_delta": 7.0,
			"rumor_pressure_delta": 8.0,
		},
		["other_family", "tracks", "granary"]
	)
	var trace := _add_trace(
		state,
		"unfamiliar_small_footprints",
		fact.id,
		GRANARY_ID,
		CHEN_MI_ID,
		["small_footprints", "unknown_family", "granary"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_unknown_granary_tracks",
		CHEN_MI_ID,
		fact.id,
		0.8,
		["unknown_family", "granary", "hunger"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_market_rumor_about_other_family(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	state.micro_state["rumor_pressure"] = clampf(
		float(state.micro_state.get("rumor_pressure", 0.0)) + 15.0,
		0.0,
		100.0
	)
	var fact := _add_closure_fact(
		state,
		"market_rumor_about_other_hungry_family",
		[MA_SHEN_ID],
		MARKET_ID,
		_source_ids(state, ["other_family_took_granary_grain"]),
		{"rumor_pressure_delta": 15.0},
		["market_rumor", "other_family", "hunger"]
	)
	var trace := _add_trace(
		state,
		"rumor_about_other_family",
		fact.id,
		MARKET_ID,
		MA_SHEN_ID,
		["low_voices", "hungry_family", "missing_grain"]
	)
	var memory := _add_memory(
		state,
		"ma_shen_remembers_other_hungry_family_rumor",
		MA_SHEN_ID,
		fact.id,
		0.6,
		["rumor", "other_family", "food_crisis"]
	)
	_add_scene(
		state,
		"other_hungry_family_rumor_scene",
		"集市上有人低声谈起另一个挨饿的家庭",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_forced_abnormal_closure(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["is_open"] = false
	shop_state["partial_open"] = false
	_add_dictionary_tag(
		shop_state,
		"status_tags",
		"forced_abnormal_closure"
	)
	shop["state"] = shop_state
	_add_dictionary_tag(shop, "tags", "forced_abnormal_closure")
	state.locations[SHOP_ID] = shop
	var old_chen := state.get_npc(OLD_CHEN_ID)
	_add_status(old_chen, "shop_forced_closed")
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_closure_fact(
		state,
		"old_chen_shop_forced_abnormal_closure",
		[OLD_CHEN_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"creditor_refused_delay_request",
				"creditor_pressed_before_theft",
				"lake_town_food_price_rising",
			]
		),
		{
			"old_chen_shop.is_open": false,
			"old_chen_shop.partial_open": false,
			"old_chen_shop.status": "forced_abnormal_closure",
		},
		["shop", "extreme_debt", "forced_closure"]
	)
	var trace := _add_trace(
		state,
		"dark_shop_in_business_hours",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["dark_shop", "business_hours", "debt"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_forced_closure",
		OLD_CHEN_ID,
		fact.id,
		0.98,
		["shop", "debt", "closure"]
	)
	_add_scene(
		state,
		"dark_old_chen_shop_scene",
		"本该营业的时辰，老陈的店里仍是一片昏暗",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_half_open_under_debt(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["is_open"] = true
	shop_state["partial_open"] = true
	_add_dictionary_tag(
		shop_state,
		"status_tags",
		"half_open_under_debt"
	)
	shop["state"] = shop_state
	_add_dictionary_tag(shop, "tags", "half_open_under_debt")
	state.locations[SHOP_ID] = shop
	var fact := _add_closure_fact(
		state,
		"old_chen_shop_half_open_under_debt",
		[OLD_CHEN_ID, LIU_ZHANGFANG_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"old_chen_reopened_shop_half_day",
				"creditor_left_debt_notice",
			]
		),
		{
			"old_chen_shop.is_open": true,
			"old_chen_shop.partial_open": true,
			"old_chen_shop.status": "half_open_under_debt",
		},
		["shop", "half_open", "debt"]
	)
	var trace := _add_trace(
		state,
		"debt_notice_beside_half_open_door",
		fact.id,
		SHOP_ID,
		LIU_ZHANGFANG_ID,
		["debt_notice", "half_open_door", "limited_trade"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_trading_under_debt",
		OLD_CHEN_ID,
		fact.id,
		0.85,
		["shop", "debt", "partial_open"]
	)
	_add_scene(
		state,
		"half_open_shop_under_debt_scene",
		"半开的店门旁仍贴着没有撤下的催债告示",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_early_help_household_memory(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var ma_shen := state.get_npc(MA_SHEN_ID)
	ma_shen["concern"] = clampf(
		float(ma_shen.get("concern", 0.0)) + 5.0,
		0.0,
		100.0
	)
	state.npcs[MA_SHEN_ID] = ma_shen
	var fact := _add_closure_fact(
		state,
		"ma_shen_early_help_became_household_memory",
		[MA_SHEN_ID, OLD_CHEN_ID, CHEN_MI_ID],
		SHOP_ID,
		_source_ids(state, ["ma_shen_helped_before_theft"]),
		{"ma_shen.concern_delta": 5.0},
		["early_help", "household_memory", "neighbor"]
	)
	var trace := _add_trace(
		state,
		"rinsed_porridge_bowl_after_early_help",
		fact.id,
		SHOP_ID,
		MA_SHEN_ID,
		["rinsed_bowl", "early_help", "neighbor"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_ma_shen_early_help",
		OLD_CHEN_ID,
		fact.id,
		0.8,
		["neighbor", "early_help", "food"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_credit_purchase_debt_pressure(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	state.micro_state["debt_pressure"] = clampf(
		float(state.micro_state.get("debt_pressure", 0.0)) + 10.0,
		0.0,
		100.0
	)
	var fact := _add_closure_fact(
		state,
		"old_chen_credit_purchase_raised_debt_pressure",
		[OLD_CHEN_ID],
		MARKET_ID,
		_source_ids(state, ["old_chen_bought_food_on_credit"]),
		{"debt_pressure_delta": 10.0},
		["credit", "debt_pressure", "delayed_cost"]
	)
	var trace := _add_trace(
		state,
		"credit_purchase_added_to_ledger",
		fact.id,
		MARKET_ID,
		OLD_CHEN_ID,
		["ledger", "credit_purchase", "new_debt"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_cost_of_credit_food",
		OLD_CHEN_ID,
		fact.id,
		0.75,
		["credit", "food", "debt"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_old_chen_withheld_delay_request(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 5.0,
		0.0,
		100.0
	)
	_add_status(old_chen, "withheld_delay_request")
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_closure_fact(
		state,
		"old_chen_withheld_delay_request",
		[OLD_CHEN_ID, LIU_ZHANGFANG_ID],
		SHOP_ID,
		_source_ids(state, ["creditor_pressed_before_theft"]),
		{"old_chen.stress_delta": 5.0},
		["debt", "pride", "withheld_request"]
	)
	var trace := _add_trace(
		state,
		"unsigned_delay_request",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["unsigned_note", "withheld_request", "debt"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_not_asking_for_delay",
		OLD_CHEN_ID,
		fact.id,
		0.9,
		["debt", "pride", "silence"]
	)
	_finish(state, result, fact, [trace], [memory])


func _add_closure_fact(
		state: WorldSimState,
		type_name: String,
		actors: Array,
		location_id: String,
		cause_ids: Array[String],
		effects: Dictionary,
		tags: Array
	) -> WorldSimState.WorldFact:
	var filtered_causes: Array[String] = []
	for cause_id: String in cause_ids:
		if cause_id != "" and not cause_id in filtered_causes:
			filtered_causes.append(cause_id)
	if filtered_causes.is_empty() and not state.world_facts.is_empty():
		filtered_causes.append(state.world_facts[-1].id)
	return state.add_fact(
		type_name,
		MICRO_REGION_ID,
		"wardens" if type_name.begins_with("guard_") else "",
		{
			"scope": "micro",
			"actors": actors.duplicate(),
			"location_id": location_id,
			"cause_fact_ids": filtered_causes,
			"effects": effects.duplicate(true),
			"tags": tags.duplicate(),
			"importance": 0.82,
			"world_cause": "lake_town_branch_closure",
			"branch_closure_key": type_name,
		}
	)


func _add_trace(
		state: WorldSimState,
		type_name: String,
		source_fact_id: String,
		location_id: String,
		npc_id: String,
		description_tags: Array
	) -> Dictionary:
	var trace := {
		"id": "trace_d%02d_%03d_%s" % [
			state.day,
			state.traces.size() + 1,
			type_name,
		],
		"type": type_name,
		"source_fact_id": source_fact_id,
		"location_id": location_id,
		"npc_id": npc_id,
		"visibility": 0.9,
		"freshness": 1.0,
		"description_tags": description_tags.duplicate(),
		"created_day": state.day,
	}
	state.traces.append(trace)
	var location := state.get_location(location_id)
	if not location.is_empty():
		var trace_ids := location.get("traces", []) as Array
		trace_ids.append(trace["id"])
		location["traces"] = trace_ids
		state.locations[location_id] = location
	return trace


func _add_memory(
		state: WorldSimState,
		type_name: String,
		owner_id: String,
		fact_id: String,
		emotional_weight: float,
		tags: Array
	) -> Dictionary:
	var memory := {
		"id": "memory_d%02d_%03d_%s" % [
			state.day,
			state.memories.size() + 1,
			type_name,
		],
		"type": type_name,
		"owner_id": owner_id,
		"fact_id": fact_id,
		"emotional_weight": clampf(emotional_weight, 0.0, 1.0),
		"decay": 0.0,
		"tags": tags.duplicate(),
		"created_day": state.day,
	}
	state.memories.append(memory)
	var owner := state.get_npc(owner_id)
	if not owner.is_empty():
		var memory_ids := owner.get("memories", []) as Array
		memory_ids.append(memory["id"])
		owner["memories"] = memory_ids
		state.npcs[owner_id] = owner
	return memory


func _add_scene(
		state: WorldSimState,
		scene_id: String,
		title: String,
		fact: WorldSimState.WorldFact,
		traces: Array,
		memories: Array
	) -> void:
	if _scene_exists(state, scene_id):
		return
	var trace_ids: Array[String] = []
	var memory_ids: Array[String] = []
	for trace_value: Variant in traces:
		trace_ids.append(
			String((trace_value as Dictionary).get("id", ""))
		)
	for memory_value: Variant in memories:
		memory_ids.append(
			String((memory_value as Dictionary).get("id", ""))
		)
	state.narratable_states.append({
		"id": scene_id,
		"type": "micro_branch_closure_scene",
		"title": title,
		"location_id": fact.location_id,
		"npc_ids": fact.actors.duplicate(),
		"trace_ids": trace_ids,
		"memory_ids": memory_ids,
		"source_fact_ids": [fact.id],
		"world_cause": "lake_town_branch_closure",
		"importance": fact.importance,
		"status": "open",
		"action_locked": false,
		"created_day": state.day,
	})


func _finish(
		state: WorldSimState,
		result: Dictionary,
		fact: WorldSimState.WorldFact,
		traces: Array,
		memories: Array
	) -> void:
	record_branch_closure(state, fact.type, fact.id)
	result["fact_id"] = fact.id
	(result["created_fact_ids"] as Array).append(fact.id)
	for trace_value: Variant in traces:
		(result["created_trace_ids"] as Array).append(
			String((trace_value as Dictionary).get("id", ""))
		)
	for memory_value: Variant in memories:
		(result["created_memory_ids"] as Array).append(
			String((memory_value as Dictionary).get("id", ""))
		)


func _source_ids(
		state: WorldSimState,
		type_names: Array
	) -> Array[String]:
	var output: Array[String] = []
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.type in type_names and not fact.id in output:
			output.append(fact.id)
	if output.is_empty() and not state.world_facts.is_empty():
		output.append(state.world_facts[-1].id)
	return output


func _days_since_fact(
		state: WorldSimState,
		type_name: String
	) -> int:
	var fact := _find_fact(state, type_name)
	if fact == null:
		return -1
	return state.day - fact.day


func _find_fact(
		state: WorldSimState,
		type_name: String
	) -> WorldSimState.WorldFact:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.type == type_name:
			return fact
	return null


func _has_fact_type(state: WorldSimState, type_name: String) -> bool:
	return _find_fact(state, type_name) != null


func _has_status(npc: Dictionary, tag: String) -> bool:
	return tag in (npc.get("status_tags", []) as Array)


func _add_status(npc: Dictionary, tag: String) -> void:
	_add_dictionary_tag(npc, "status_tags", tag)


func _add_dictionary_tag(
		target: Dictionary,
		key: String,
		tag: String
	) -> void:
	var tags := target.get(key, []) as Array
	if not tag in tags:
		tags.append(tag)
	target[key] = tags


func _scene_exists(state: WorldSimState, scene_id: String) -> bool:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == scene_id:
			return true
	return false


func _base_result(closure_id: String) -> Dictionary:
	return {
		"ok": false,
		"closure_id": closure_id,
		"fact_id": "",
		"created_fact_ids": [],
		"created_trace_ids": [],
		"created_memory_ids": [],
		"error": "",
	}
