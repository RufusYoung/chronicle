extends RefCounted
class_name LakeTownReactionSystem

const RecoverySystemModel = preload(
	"res://scripts/sim/lake_town_recovery_system.gd"
)

const MICRO_REGION_ID := "lake_town"
const SHOP_ID := "old_chen_shop"
const GRANARY_ID := "abandoned_granary"
const SCENE_ID := "chen_mi_hiding_spoiled_grain_scene"
const OLD_CHEN_ID := "old_chen"
const CHEN_MI_ID := "chen_mi"
const MA_SHEN_ID := "ma_shen"
const LIU_ZHANGFANG_ID := "liu_zhangfang"

const REACTION_IDS: Array[String] = [
	"chen_mi_ate_spoiled_grain",
	"chen_mi_fell_sick_from_spoiled_grain",
	"old_chen_discovered_spoiled_grain",
	"ma_shen_noticed_closed_shop",
	"ma_shen_brought_porridge",
	"creditor_left_debt_notice",
	"guard_checked_old_chen_shop",
]

var recovery_system := RecoverySystemModel.new()


func tick_reactions(state: Variant) -> Array:
	var results: Array[Dictionary] = []
	if not state is WorldSimState:
		return results
	_ensure_reaction_state(state)
	_update_daily_pressures(state)
	var candidates := build_reaction_candidates(state)
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		var result := apply_reaction(
			state,
			String(candidate.get("id", ""))
		)
		if bool(result.get("ok", false)):
			results.append(result)
	return results


func build_reaction_candidates(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	_ensure_reaction_state(state)
	for reaction_id: String in REACTION_IDS:
		if _can_apply_reaction(state, reaction_id):
			output.append({
				"id": reaction_id,
				"reaction_key": reaction_id,
				"source": "lake_town_state",
			})
	return output


func apply_reaction(state: Variant, reaction_id: String) -> Dictionary:
	var result := _base_result(reaction_id)
	if not state is WorldSimState:
		result["error"] = "invalid_world_state"
		return result
	_ensure_reaction_state(state)
	if not _can_apply_reaction(state, reaction_id):
		result["error"] = "missing_required_state"
		return result

	match reaction_id:
		"chen_mi_ate_spoiled_grain":
			_apply_chen_mi_ate_spoiled_grain(state, result)
		"chen_mi_fell_sick_from_spoiled_grain":
			_apply_chen_mi_fell_sick(state, result)
		"old_chen_discovered_spoiled_grain":
			_apply_old_chen_discovered_grain(state, result)
		"ma_shen_noticed_closed_shop":
			_apply_ma_shen_noticed_shop(state, result)
		"ma_shen_brought_porridge":
			_apply_ma_shen_brought_porridge(state, result)
		"creditor_left_debt_notice":
			_apply_creditor_left_notice(state, result)
		"guard_checked_old_chen_shop":
			_apply_guard_checked_shop(state, result)
		_:
			result["error"] = "unknown_reaction"
			return result
	result["ok"] = true
	return result


func has_reaction_happened(state: Variant, reaction_key: String) -> bool:
	if not state is WorldSimState:
		return false
	for entry_value: Variant in state.micro_state.get("reaction_history", []):
		var entry := entry_value as Dictionary
		if String(entry.get("reaction_key", "")) == reaction_key:
			return true
	return false


func record_reaction(
		state: Variant,
		reaction_key: String,
		fact_id: String
	) -> void:
	if not state is WorldSimState or reaction_key == "" or fact_id == "":
		return
	if has_reaction_happened(state, reaction_key):
		return
	var history := state.micro_state.get("reaction_history", []) as Array
	history.append({
		"reaction_key": reaction_key,
		"fact_id": fact_id,
		"day": state.day,
	})
	state.micro_state["reaction_history"] = history
	state.micro_state["last_reaction_day"] = state.day


func _ensure_reaction_state(state: WorldSimState) -> void:
	if not state.micro_state.has("reaction_history"):
		state.micro_state["reaction_history"] = []
	if not state.micro_state.has("scene_followup"):
		state.micro_state["scene_followup"] = {}
	if not state.micro_state.has("closed_shop_days"):
		state.micro_state["closed_shop_days"] = 0
	if not state.micro_state.has("unresolved_scene_days"):
		state.micro_state["unresolved_scene_days"] = 0
	if not state.micro_state.has("neighbor_attention"):
		state.micro_state["neighbor_attention"] = 0.0
	if not state.micro_state.has("debt_pressure"):
		state.micro_state["debt_pressure"] = 0.0
	if not state.micro_state.has("health_pressure"):
		state.micro_state["health_pressure"] = 0.0
	if not state.micro_state.has("rumor_pressure"):
		state.micro_state["rumor_pressure"] = 0.0
	if not state.micro_state.has("last_reaction_day"):
		state.micro_state["last_reaction_day"] = 0
	if not state.micro_state.has("reaction_state_update_day"):
		state.micro_state["reaction_state_update_day"] = 0

	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	for key: String in [
		"chen_mi_scene_started_day",
		"last_reaction_day",
		"chen_mi_ate_spoiled_grain_day",
	]:
		if not followup.has(key):
			followup[key] = 0
	for key: String in [
		"chen_mi_scene_resolved",
		"chen_mi_ate_spoiled_grain",
		"old_chen_discovered_grain",
		"neighbor_noticed_closed_shop",
		"creditor_visited",
		"ma_shen_helped",
		"guard_checked_shop",
	]:
		if not followup.has(key):
			followup[key] = false
	var scene := _find_scene(state)
	if not scene.is_empty():
		followup["chen_mi_scene_started_day"] = int(
			scene.get("created_day", state.day)
		)
		followup["chen_mi_scene_resolved"] = bool(
			scene.get("action_locked", false)
		)
	state.micro_state["scene_followup"] = followup
	_ensure_social_npcs(state)


func _ensure_social_npcs(state: WorldSimState) -> void:
	if not state.npcs.has(MA_SHEN_ID):
		state.npcs[MA_SHEN_ID] = {
			"id": MA_SHEN_ID,
			"name": "玛婶",
			"tier": "A",
			"role": "neighbor",
			"location_id": "lake_town_market",
			"concern": 45.0,
			"food_spare": 2.0,
			"trust_to_old_chen": 68.0,
			"memories": [],
			"status_tags": [],
		}
	if not state.npcs.has(LIU_ZHANGFANG_ID):
		state.npcs[LIU_ZHANGFANG_ID] = {
			"id": LIU_ZHANGFANG_ID,
			"name": "刘账房",
			"tier": "A",
			"role": "creditor",
			"location_id": "lake_town_market",
			"patience": 75.0,
			"debt_claim": 38.0,
			"memories": [],
			"status_tags": [],
		}


func _update_daily_pressures(state: WorldSimState) -> void:
	if int(state.micro_state.get("reaction_state_update_day", 0)) == state.day:
		return
	state.micro_state["reaction_state_update_day"] = state.day
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	var closed := not bool(shop_state.get("is_open", true))
	var closed_days := int(state.micro_state.get("closed_shop_days", 0))
	state.micro_state["closed_shop_days"] = closed_days + 1 if closed else 0
	var unresolved_days := int(
		state.micro_state.get("unresolved_scene_days", 0)
	)
	state.micro_state["unresolved_scene_days"] = (
		unresolved_days + 1 if _food_crisis_unresolved(state) else 0
	)

	var ma_shen := state.get_npc(MA_SHEN_ID)
	if closed:
		var concern_gain := 3.0
		if bool(shop_state.get("family_crisis", false)):
			concern_gain += 2.0
		if _has_trace_type(state, "closed_shop"):
			concern_gain += 1.0
		ma_shen["concern"] = clampf(
			float(ma_shen.get("concern", 0.0)) + concern_gain,
			0.0,
			100.0
		)
	state.npcs[MA_SHEN_ID] = ma_shen

	var liu := state.get_npc(LIU_ZHANGFANG_ID)
	if closed and float(old_chen.get("debt", 0.0)) >= 50.0:
		liu["patience"] = maxf(
			0.0,
			float(liu.get("patience", 0.0)) - 15.0
		)
	state.npcs[LIU_ZHANGFANG_ID] = liu

	var disease_bonus := 18.0 if _has_status(chen_mi, "disease_risk") else 0.0
	state.micro_state["neighbor_attention"] = clampf(
		float(ma_shen.get("concern", 0.0))
		+ float(state.micro_state.get("closed_shop_days", 0)) * 4.0
		+ float(state.micro_state.get("rumor_pressure", 0.0)) * 0.25,
		0.0,
		100.0
	)
	state.micro_state["debt_pressure"] = clampf(
		float(old_chen.get("debt", 0.0))
		+ float(state.micro_state.get("closed_shop_days", 0)) * 2.0,
		0.0,
		100.0
	)
	state.micro_state["health_pressure"] = clampf(
		float(chen_mi.get("hunger", 0.0)) * 0.55
		+ (100.0 - float(chen_mi.get("health", 100.0))) * 0.8
		+ disease_bonus,
		0.0,
		100.0
	)
	if closed and _has_trace_type(state, "closed_shop"):
		state.micro_state["rumor_pressure"] = clampf(
			float(state.micro_state.get("rumor_pressure", 0.0)) + 2.0,
			0.0,
			100.0
		)


func _can_apply_reaction(
		state: WorldSimState,
		reaction_id: String
	) -> bool:
	if has_reaction_happened(state, reaction_id):
		return false
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	var chen_inventory := chen_mi.get("inventory", []) as Array
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	match reaction_id:
		"chen_mi_ate_spoiled_grain":
			return (
				_has_fact_type(state, "chen_mi_took_spoiled_grain")
				and "spoiled_grain" in chen_inventory
				and float(chen_mi.get("hunger", 0.0)) >= 85.0
				and _food_crisis_unresolved(state)
				and not _has_memory_type(
					state,
					"chen_mi_remembers_actor_gave_food"
				)
				and not _has_fact_type(
					state,
					"actor_bought_spoiled_grain_low"
				)
			)
		"chen_mi_fell_sick_from_spoiled_grain":
			return (
				bool(followup.get("chen_mi_ate_spoiled_grain", false))
				and state.day > int(
					followup.get("chen_mi_ate_spoiled_grain_day", 0)
				)
				and _sickness_pressure_ready(state, chen_mi)
			)
		"old_chen_discovered_spoiled_grain":
			var scene := _find_scene(state)
			return (
				not scene.is_empty()
				and state.day > int(scene.get("created_day", state.day))
				and _has_trace_type(state, "child_hiding_bag")
				and _has_trace_type(state, "spoiled_grain_bag")
				and not bool(shop_state.get("is_open", true))
				and float(old_chen.get("stress", 0.0)) >= 80.0
				and _food_crisis_unresolved(state)
				and not _has_fact_type(
					state,
					"actor_bought_spoiled_grain_low"
				)
			)
		"ma_shen_noticed_closed_shop":
			var ma_shen := state.get_npc(MA_SHEN_ID)
			return (
				not bool(shop_state.get("is_open", true))
				and int(state.micro_state.get("closed_shop_days", 0)) >= 2
				and _has_trace_type(state, "closed_shop")
				and (
					float(ma_shen.get("concern", 0.0)) >= 50.0
					or bool(shop_state.get("family_crisis", false))
				)
			)
		"ma_shen_brought_porridge":
			var helper := state.get_npc(MA_SHEN_ID)
			return (
				has_reaction_happened(
					state,
					"ma_shen_noticed_closed_shop"
				)
				and float(helper.get("food_spare", 0.0)) > 0.0
				and (
					float(chen_mi.get("hunger", 0.0)) >= 85.0
					or _has_status(
						chen_mi,
						"sick_from_spoiled_grain"
					)
				)
				and float(
					helper.get("trust_to_old_chen", 0.0)
				) >= 50.0
			)
		"creditor_left_debt_notice":
			var creditor := state.get_npc(LIU_ZHANGFANG_ID)
			return (
				float(old_chen.get("debt", 0.0)) >= 70.0
				and not bool(shop_state.get("is_open", true))
				and int(state.micro_state.get("closed_shop_days", 0)) >= 3
				and float(creditor.get("patience", 100.0)) <= 25.0
			)
		"guard_checked_old_chen_shop":
			var report_fact := _find_fact(
				state,
				"actor_reported_chen_mi_to_guard"
			)
			return (
				report_fact != null
				and state.day > report_fact.day
				and _has_trace_type(
					state,
					"guard_attention_at_old_chen_shop"
				)
			)
	return false


func _apply_chen_mi_ate_spoiled_grain(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 20.0
	)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 12.0
	)
	chen_mi["fear"] = maxf(
		0.0,
		float(chen_mi.get("fear", 0.0)) - 1.0
	)
	_add_status(chen_mi, "ate_spoiled_grain")
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_reaction_fact(
		state,
		"chen_mi_ate_spoiled_grain",
		[CHEN_MI_ID],
		[_fact_id(state, "chen_mi_took_spoiled_grain")],
		{
			"chen_mi.hunger_delta": -20.0,
			"chen_mi.health_delta": -12.0,
		},
		["food_crisis", "spoiled_food", "health_risk"]
	)
	_record_fact(result, fact)
	_record_trace(
		result,
		_add_trace(
			state,
			"spoiled_grain_crumbs",
			fact.id,
			SHOP_ID,
			CHEN_MI_ID,
			["moldy_crumbs", "shop_step", "spoiled_food"]
		)
	)
	_record_trace(
		result,
		_add_trace(
			state,
			"stomach_pain_sign",
			fact.id,
			SHOP_ID,
			CHEN_MI_ID,
			["child_cough", "stomach_pain", "weakness"]
		)
	)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_remembers_eating_spoiled_grain",
			CHEN_MI_ID,
			fact.id,
			0.8,
			["spoiled_food", "hunger", "illness_risk"]
		)
	)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["chen_mi_ate_spoiled_grain"] = true
	followup["chen_mi_ate_spoiled_grain_day"] = state.day
	state.micro_state["scene_followup"] = followup
	_finish_reaction(state, result, fact)


func _apply_chen_mi_fell_sick(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 14.0
	)
	_add_status(chen_mi, "sick_from_spoiled_grain")
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 12.0,
		0.0,
		100.0
	)
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_reaction_fact(
		state,
		"chen_mi_fell_sick_from_spoiled_grain",
		[CHEN_MI_ID, OLD_CHEN_ID],
		[_fact_id(state, "chen_mi_ate_spoiled_grain")],
		{
			"chen_mi.health_delta": -14.0,
			"old_chen.stress_delta": 12.0,
		},
		["food_crisis", "illness", "family"]
	)
	_record_fact(result, fact)
	var trace := _add_trace(
		state,
		"sick_child_at_shop_door",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["sick_child", "closed_shop", "cough"]
	)
	_record_trace(result, trace)
	_record_memory(
		result,
		_add_memory(
			state,
			"old_chen_remembers_chen_mi_sick",
			OLD_CHEN_ID,
			fact.id,
			0.95,
			["daughter", "illness", "spoiled_food"]
		)
	)
	_add_narratable_state(
		state,
		"sick_child_after_spoiled_grain_scene",
		"陈米吃过发霉麦子后病倒了",
		fact,
		[trace]
	)
	_finish_reaction(state, result, fact)


func _apply_old_chen_discovered_grain(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 6.0,
		0.0,
		100.0
	)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 12.0,
		0.0,
		100.0
	)
	_add_status(old_chen, "found_spoiled_grain")
	_add_status(chen_mi, "grain_secret_discovered")
	state.npcs[OLD_CHEN_ID] = old_chen
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_reaction_fact(
		state,
		"old_chen_discovered_spoiled_grain",
		[OLD_CHEN_ID, CHEN_MI_ID],
		[
			_fact_id(state, "chen_mi_took_spoiled_grain"),
			_fact_id(
				state,
				"old_chen_closed_shop_due_to_family_crisis"
			),
		],
		{
			"old_chen.stress_delta": 6.0,
			"chen_mi.fear_delta": 12.0,
		},
		["food_crisis", "family", "discovery"]
	)
	_record_fact(result, fact)
	var trace := _add_trace(
		state,
		"overturned_grain_bag",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["opened_bag", "moldy_grain", "family_discovery"]
	)
	_record_trace(result, trace)
	_record_memory(
		result,
		_add_memory(
			state,
			"old_chen_found_spoiled_grain",
			OLD_CHEN_ID,
			fact.id,
			0.9,
			["daughter", "spoiled_food", "guilt"]
		)
	)
	_add_narratable_state(
		state,
		"old_chen_found_spoiled_grain_scene",
		"老陈发现了陈米藏着的发霉麦子",
		fact,
		[trace]
	)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["old_chen_discovered_grain"] = true
	state.micro_state["scene_followup"] = followup
	_finish_reaction(state, result, fact)


func _apply_ma_shen_noticed_shop(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var ma_shen := state.get_npc(MA_SHEN_ID)
	ma_shen["concern"] = clampf(
		float(ma_shen.get("concern", 0.0)) + 10.0,
		0.0,
		100.0
	)
	_add_status(ma_shen, "watching_old_chen_shop")
	state.npcs[MA_SHEN_ID] = ma_shen
	var fact := _add_reaction_fact(
		state,
		"ma_shen_noticed_closed_shop",
		[MA_SHEN_ID, OLD_CHEN_ID],
		[
			_fact_id(
				state,
				"old_chen_closed_shop_due_to_family_crisis"
			),
		],
		{
			"ma_shen.concern_delta": 10.0,
			"rumor_pressure_delta": 15.0,
		},
		["neighbor", "closed_shop", "social_attention"]
	)
	_record_fact(result, fact)
	_record_trace(
		result,
		_add_trace(
			state,
			"neighbor_footprints_at_shop",
			fact.id,
			SHOP_ID,
			MA_SHEN_ID,
			["neighbor", "repeated_visits", "closed_door"]
		)
	)
	_record_trace(
		result,
		_add_trace(
			state,
			"whispered_market_rumor",
			fact.id,
			"lake_town_market",
			MA_SHEN_ID,
			["market_whispers", "closed_shop", "family_crisis"]
		)
	)
	_record_memory(
		result,
		_add_memory(
			state,
			"noticed_old_chen_shop_closed",
			MA_SHEN_ID,
			fact.id,
			0.65,
			["neighbor", "closed_shop", "concern"]
		)
	)
	state.micro_state["rumor_pressure"] = clampf(
		float(state.micro_state.get("rumor_pressure", 0.0)) + 15.0,
		0.0,
		100.0
	)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["neighbor_noticed_closed_shop"] = true
	state.micro_state["scene_followup"] = followup
	_finish_reaction(state, result, fact)


func _apply_ma_shen_brought_porridge(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var ma_shen := state.get_npc(MA_SHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	ma_shen["food_spare"] = maxf(
		0.0,
		float(ma_shen.get("food_spare", 0.0)) - 1.0
	)
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 28.0
	)
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 10.0
	)
	_add_status(ma_shen, "shared_food_with_old_chen")
	_add_status(chen_mi, "received_neighbor_porridge")
	state.npcs[MA_SHEN_ID] = ma_shen
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_reaction_fact(
		state,
		"ma_shen_brought_porridge",
		[MA_SHEN_ID, OLD_CHEN_ID, CHEN_MI_ID],
		[_fact_id(state, "ma_shen_noticed_closed_shop")],
		{
			"ma_shen.food_spare_delta": -1.0,
			"chen_mi.hunger_delta": -28.0,
			"old_chen.stress_delta": -10.0,
		},
		["neighbor", "aid", "food_crisis"]
	)
	_record_fact(result, fact)
	recovery_system.adjust_micro_relationship(
		state,
		MA_SHEN_ID,
		OLD_CHEN_ID,
		{"trust": 12.0, "familiarity": 8.0},
		fact.id
	)
	recovery_system.adjust_micro_relationship(
		state,
		OLD_CHEN_ID,
		MA_SHEN_ID,
		{"trust": 8.0, "gratitude": 10.0, "familiarity": 8.0},
		fact.id
	)
	var trace := _add_trace(
		state,
		"empty_porridge_bowl_at_door",
		fact.id,
		SHOP_ID,
		MA_SHEN_ID,
		["empty_bowl", "neighbor_help", "porridge"]
	)
	_record_trace(result, trace)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_remembers_ma_shen_porridge",
			CHEN_MI_ID,
			fact.id,
			0.8,
			["neighbor", "food", "aid"]
		)
	)
	_add_narratable_state(
		state,
		"neighbor_helped_during_food_crisis_scene",
		"玛婶把一碗粥留在了关着的店门口",
		fact,
		[trace]
	)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["ma_shen_helped"] = true
	state.micro_state["scene_followup"] = followup
	_finish_reaction(state, result, fact)


func _apply_creditor_left_notice(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var liu := state.get_npc(LIU_ZHANGFANG_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	liu["debt_claim"] = clampf(
		maxf(
			float(liu.get("debt_claim", 0.0)),
			float(old_chen.get("debt", 0.0))
		) + 8.0,
		0.0,
		120.0
	)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 10.0,
		0.0,
		100.0
	)
	_add_status(liu, "left_debt_notice")
	_add_status(old_chen, "creditor_pressure")
	state.npcs[LIU_ZHANGFANG_ID] = liu
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_reaction_fact(
		state,
		"creditor_left_debt_notice",
		[LIU_ZHANGFANG_ID, OLD_CHEN_ID],
		[
			_fact_id(
				state,
				"old_chen_closed_shop_due_to_family_crisis"
			),
			_fact_id(state, "lake_town_food_price_rising"),
		],
		{
			"liu_zhangfang.debt_claim": liu["debt_claim"],
			"old_chen.stress_delta": 10.0,
		},
		["debt", "closed_shop", "creditor"]
	)
	_record_fact(result, fact)
	var trace := _add_trace(
		state,
		"debt_notice_on_shop_door",
		fact.id,
		SHOP_ID,
		LIU_ZHANGFANG_ID,
		["debt_notice", "red_ink", "closed_shop"]
	)
	_record_trace(result, trace)
	_record_memory(
		result,
		_add_memory(
			state,
			"old_chen_remembers_debt_notice",
			OLD_CHEN_ID,
			fact.id,
			0.9,
			["debt", "shame", "creditor"]
		)
	)
	_add_narratable_state(
		state,
		"debt_notice_at_closed_shop_scene",
		"刘账房在关着的店门上留下了催债告示",
		fact,
		[trace]
	)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["creditor_visited"] = true
	state.micro_state["scene_followup"] = followup
	_finish_reaction(state, result, fact)


func _apply_guard_checked_shop(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 10.0,
		0.0,
		100.0
	)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 8.0,
		0.0,
		100.0
	)
	_add_status(chen_mi, "questioned_by_guard")
	_add_status(old_chen, "guard_visit")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	var attention := state.micro_state.get("guard_attention", {}) as Dictionary
	attention["wardens"] = clampf(
		float(attention.get("wardens", 0.0)) + 15.0,
		0.0,
		100.0
	)
	state.micro_state["guard_attention"] = attention
	var fact := _add_reaction_fact(
		state,
		"guard_checked_old_chen_shop",
		["wardens", OLD_CHEN_ID, CHEN_MI_ID],
		[_fact_id(state, "actor_reported_chen_mi_to_guard")],
		{
			"wardens.attention_delta": 15.0,
			"chen_mi.fear_delta": 10.0,
			"old_chen.stress_delta": 8.0,
		},
		["guard", "report_followup", "closed_shop"]
	)
	_record_fact(result, fact)
	var trace := _add_trace(
		state,
		"guard_boot_marks_at_shop",
		fact.id,
		SHOP_ID,
		"wardens",
		["guard_boots", "doorstep", "questions"]
	)
	_record_trace(result, trace)
	_record_memory(
		result,
		_add_memory(
			state,
			"chen_mi_remembers_guard_visit",
			CHEN_MI_ID,
			fact.id,
			0.95,
			["guard", "fear", "reported"]
		)
	)
	_add_narratable_state(
		state,
		"guard_visit_after_report_scene",
		"守卫来到老陈店门口盘问偷粮的事",
		fact,
		[trace]
	)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["guard_checked_shop"] = true
	state.micro_state["scene_followup"] = followup
	_finish_reaction(state, result, fact)


func _add_reaction_fact(
		state: WorldSimState,
		type_name: String,
		actors: Array,
		cause_ids: Array,
		effects: Dictionary,
		tags: Array
	) -> WorldSimState.WorldFact:
	var filtered_causes: Array[String] = []
	for cause_value: Variant in cause_ids:
		var cause_id := String(cause_value)
		if cause_id != "" and not cause_id in filtered_causes:
			filtered_causes.append(cause_id)
	return state.add_fact(
		type_name,
		MICRO_REGION_ID,
		"wardens" if type_name == "guard_checked_old_chen_shop" else "",
		{
			"scope": "micro",
			"actors": actors.duplicate(),
			"location_id": SHOP_ID,
			"cause_fact_ids": filtered_causes,
			"effects": effects.duplicate(true),
			"tags": tags.duplicate(),
			"importance": 0.75,
			"world_cause": "lake_town_micro_reaction",
			"reaction_key": type_name,
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


func _add_narratable_state(
		state: WorldSimState,
		scene_id: String,
		title: String,
		fact: WorldSimState.WorldFact,
		traces: Array
	) -> void:
	if _narratable_exists(state, scene_id):
		return
	var trace_ids: Array[String] = []
	for trace_value: Variant in traces:
		var trace := trace_value as Dictionary
		trace_ids.append(String(trace.get("id", "")))
	state.narratable_states.append({
		"id": scene_id,
		"type": "micro_followup_scene",
		"title": title,
		"location_id": SHOP_ID,
		"npc_ids": fact.actors.duplicate(),
		"trace_ids": trace_ids,
		"source_fact_ids": [fact.id],
		"world_cause": "lake_town_micro_reaction",
		"importance": fact.importance,
		"status": "open",
		"action_locked": false,
		"created_day": state.day,
	})


func _finish_reaction(
		state: WorldSimState,
		result: Dictionary,
		fact: WorldSimState.WorldFact
	) -> void:
	record_reaction(state, fact.type, fact.id)
	var followup := state.micro_state.get("scene_followup", {}) as Dictionary
	followup["last_reaction_day"] = state.day
	state.micro_state["scene_followup"] = followup
	result["fact_id"] = fact.id
	result["created_fact_ids"] = [fact.id]


func _food_crisis_unresolved(state: WorldSimState) -> bool:
	var scene := _find_scene(state)
	if scene.is_empty():
		return false
	var status := String(scene.get("status", "open"))
	return status not in ["resolved_with_food", "grain_bought_low"]


func _find_scene(state: WorldSimState) -> Dictionary:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == SCENE_ID:
			return scene
	return {}


func _find_fact(
		state: WorldSimState,
		type_name: String
	) -> WorldSimState.WorldFact:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.type == type_name:
			return fact
	return null


func _fact_id(state: WorldSimState, type_name: String) -> String:
	var fact := _find_fact(state, type_name)
	return fact.id if fact != null else ""


func _has_fact_type(state: WorldSimState, type_name: String) -> bool:
	return _find_fact(state, type_name) != null


func _has_trace_type(state: WorldSimState, type_name: String) -> bool:
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		if String(trace.get("type", "")) == type_name:
			return true
	return false


func _has_memory_type(state: WorldSimState, type_name: String) -> bool:
	for memory_value: Variant in state.memories:
		var memory := memory_value as Dictionary
		if String(memory.get("type", "")) == type_name:
			return true
	return false


func _has_status(npc: Dictionary, tag: String) -> bool:
	return tag in (npc.get("status_tags", []) as Array)


func _sickness_pressure_ready(
		state: WorldSimState,
		chen_mi: Dictionary
	) -> bool:
	if not state.micro_state.has("seed_profile"):
		return (
			float(chen_mi.get("health", 100.0)) <= 80.0
			or _has_status(chen_mi, "disease_risk")
		)
	var granary_state := (
		state.get_location(GRANARY_ID).get("state", {})
		as Dictionary
	)
	var resistance := float(
		chen_mi.get("sickness_resistance", 50.0)
	)
	var disease_risk := float(
		granary_state.get("disease_risk", 0.65)
	)
	var sickness_pressure := (
		(100.0 - resistance) * 0.55
		+ disease_risk * 50.0
		+ (100.0 - float(chen_mi.get("health", 100.0))) * 0.4
	)
	return sickness_pressure >= 68.0


func _add_status(npc: Dictionary, tag: String) -> void:
	var tags := npc.get("status_tags", []) as Array
	if not tag in tags:
		tags.append(tag)
	npc["status_tags"] = tags


func _narratable_exists(state: WorldSimState, scene_id: String) -> bool:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == scene_id:
			return true
	return false


func _base_result(reaction_id: String) -> Dictionary:
	return {
		"ok": false,
		"reaction_id": reaction_id,
		"fact_id": "",
		"created_fact_ids": [],
		"created_trace_ids": [],
		"created_memory_ids": [],
		"error": "",
	}


func _record_fact(
		result: Dictionary,
		fact: WorldSimState.WorldFact
	) -> void:
	(result["created_fact_ids"] as Array).append(fact.id)


func _record_trace(result: Dictionary, trace: Dictionary) -> void:
	(result["created_trace_ids"] as Array).append(
		String(trace.get("id", ""))
	)


func _record_memory(result: Dictionary, memory: Dictionary) -> void:
	(result["created_memory_ids"] as Array).append(
		String(memory.get("id", ""))
	)
