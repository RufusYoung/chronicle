extends RefCounted
class_name LakeTownHungerClosureSystem

const RecoverySystemModel = preload(
	"res://scripts/sim/lake_town_recovery_system.gd"
)

const MICRO_REGION_ID := "lake_town"
const SHOP_ID := "old_chen_shop"
const MARKET_ID := "lake_town_market"
const MA_SHEN_HOME_ID := "ma_shen_home_temp"
const OLD_CHEN_ID := "old_chen"
const CHEN_MI_ID := "chen_mi"
const MA_SHEN_ID := "ma_shen"

const CLOSURE_IDS: Array[String] = [
	"ma_shen_emergency_food_for_chen_mi",
	"chen_mi_temporarily_stayed_with_ma_shen",
	"lake_town_emergency_credit_food",
	"old_chen_took_chen_mi_to_seek_help",
	"chen_mi_collapsed_from_hunger",
	"old_chen_sold_shop_goods_for_food",
	"chen_mi_health_crashed_from_hunger",
	"chen_mi_hunger_unresolved_but_recorded",
]

const RECENT_FOOD_HELP_TYPES: Array[String] = [
	"actor_gave_food_to_chen_mi",
	"ma_shen_brought_porridge",
	"ma_shen_helped_before_theft",
	"ma_shen_emergency_food_for_chen_mi",
	"lake_town_emergency_credit_food",
]

var recovery_system := RecoverySystemModel.new()


func tick_hunger_closure(state: Variant) -> Array:
	var results: Array[Dictionary] = []
	if not state is WorldSimState:
		return results
	if not state.micro_state.has("seed_profile"):
		return results
	_ensure_hunger_state(state)
	_update_hunger_pressure(state)
	if _awaiting_extreme_hunger_confirmation(state):
		return results
	for closure_id: String in CLOSURE_IDS:
		if not _can_apply_closure(state, closure_id):
			continue
		var result := apply_hunger_closure(state, closure_id)
		if bool(result.get("ok", false)):
			results.append(result)
			break
	return results


func build_hunger_closure_candidates(state: Variant) -> Array:
	var output: Array[Dictionary] = []
	if not state is WorldSimState:
		return output
	if not state.micro_state.has("seed_profile"):
		return output
	_ensure_hunger_state(state)
	_update_hunger_pressure(state)
	if _awaiting_extreme_hunger_confirmation(state):
		return output
	for closure_id: String in CLOSURE_IDS:
		if _can_apply_closure(state, closure_id):
			output.append({
				"id": closure_id,
				"closure_key": closure_id,
				"source": "lake_town_structured_hunger_state",
			})
	return output


func apply_hunger_closure(
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
	_ensure_hunger_state(state)
	_update_hunger_pressure(state)
	if not _can_apply_closure(state, closure_id):
		result["error"] = "missing_required_state"
		return result

	match closure_id:
		"chen_mi_collapsed_from_hunger":
			_apply_chen_mi_collapsed(state, result)
		"ma_shen_emergency_food_for_chen_mi":
			_apply_ma_shen_emergency_food(state, result)
		"old_chen_sold_shop_goods_for_food":
			_apply_old_chen_sold_goods(state, result)
		"old_chen_took_chen_mi_to_seek_help":
			_apply_old_chen_sought_help(state, result)
		"lake_town_emergency_credit_food":
			_apply_emergency_credit_food(state, result)
		"chen_mi_health_crashed_from_hunger":
			_apply_health_crash(state, result)
		"chen_mi_temporarily_stayed_with_ma_shen":
			_apply_temporary_ma_shen_stay(state, result)
		"chen_mi_hunger_unresolved_but_recorded":
			_apply_unresolved_record(state, result)
		_:
			result["error"] = "unknown_hunger_closure"
			return result
	result["ok"] = true
	return result


func has_hunger_closure_happened(
		state: Variant,
		closure_key: String
	) -> bool:
	if not state is WorldSimState:
		return false
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	for entry_value: Variant in hunger_state.get(
		"hunger_closure_history",
		[]
	):
		var entry := entry_value as Dictionary
		if String(entry.get("closure_key", "")) == closure_key:
			return true
	return _has_fact_type(state, closure_key)


func record_hunger_closure(
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
	_ensure_hunger_state(state)
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	var history := hunger_state.get(
		"hunger_closure_history",
		[]
	) as Array
	for entry_value: Variant in history:
		var entry := entry_value as Dictionary
		if String(entry.get("closure_key", "")) == closure_key:
			return
	history.append({
		"closure_key": closure_key,
		"fact_id": fact_id,
		"day": state.day,
	})
	hunger_state["hunger_closure_history"] = history
	hunger_state["last_hunger_closure_day"] = state.day
	hunger_state["last_hunger_closure_fact_day"] = state.day
	state.micro_state["hunger_closure_state"] = hunger_state


func _ensure_hunger_state(state: WorldSimState) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	var defaults := {
		"extreme_hunger_days": 0,
		"last_extreme_hunger_day": -1,
		"last_hunger_closure_day": -1,
		"hunger_closure_history": [],
		"chen_mi_temporarily_relocated": false,
		"chen_mi_collapsed": false,
		"emergency_food_received": false,
		"critical_health_decline_recorded": false,
		"last_hunger_relief_day": -1,
		"last_hunger_closure_fact_day": -1,
		"last_hunger_value": float(chen_mi.get("hunger", 0.0)),
		"last_health_value": float(chen_mi.get("health", 100.0)),
		"health_declining": false,
		"last_state_update_day": -1,
	}
	for key: String in defaults:
		if not hunger_state.has(key):
			hunger_state[key] = defaults[key]
	state.micro_state["hunger_closure_state"] = hunger_state


func _update_hunger_pressure(state: WorldSimState) -> void:
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	if int(hunger_state.get("last_state_update_day", -1)) == state.day:
		return
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var hunger := float(chen_mi.get("hunger", 0.0))
	var health := float(chen_mi.get("health", 100.0))
	var previous_hunger := float(
		hunger_state.get("last_hunger_value", hunger)
	)
	var previous_health := float(
		hunger_state.get("last_health_value", health)
	)
	if hunger < previous_hunger - 0.5:
		hunger_state["last_hunger_relief_day"] = state.day
	if hunger >= 95.0:
		var last_extreme := int(
			hunger_state.get("last_extreme_hunger_day", -1)
		)
		hunger_state["extreme_hunger_days"] = (
			int(hunger_state.get("extreme_hunger_days", 0)) + 1
			if last_extreme == state.day - 1
			else 1
		)
		hunger_state["last_extreme_hunger_day"] = state.day
	else:
		hunger_state["extreme_hunger_days"] = 0
	hunger_state["health_declining"] = health < previous_health - 0.5
	hunger_state["last_hunger_value"] = hunger
	hunger_state["last_health_value"] = health
	hunger_state["last_state_update_day"] = state.day
	state.micro_state["hunger_closure_state"] = hunger_state


func _awaiting_extreme_hunger_confirmation(state: WorldSimState) -> bool:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	return (
		float(chen_mi.get("hunger", 0.0)) >= 98.0
		and float(chen_mi.get("health", 100.0)) > 85.0
		and int(hunger_state.get("extreme_hunger_days", 0)) < 2
		and not _has_any_hunger_closure(state)
	)


func _can_apply_closure(
		state: WorldSimState,
		closure_id: String
	) -> bool:
	if has_hunger_closure_happened(state, closure_id):
		return false
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var ma_shen := state.get_npc(MA_SHEN_ID)
	var shop_state := (
		state.get_location(SHOP_ID).get("state", {})
		as Dictionary
	)
	var market_state := (
		state.get_location(MARKET_ID).get("state", {})
		as Dictionary
	)
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	var extreme_days := int(
		hunger_state.get("extreme_hunger_days", 0)
	)
	match closure_id:
		"chen_mi_collapsed_from_hunger":
			return (
				float(chen_mi.get("hunger", 0.0)) >= 98.0
				and (
					float(chen_mi.get("health", 100.0)) <= 85.0
					or extreme_days >= 2
				)
				and not _recent_food_help(state)
				and not bool(
					hunger_state.get(
						"chen_mi_temporarily_relocated",
						false
					)
				)
				and String(
					chen_mi.get("location_id", SHOP_ID)
				) == SHOP_ID
			)
		"ma_shen_emergency_food_for_chen_mi":
			return (
				(
					_has_fact_type(
						state,
						"chen_mi_collapsed_from_hunger"
					)
					or _has_fact_type(
						state,
						"neighbor_noticed_silent_hungry_child"
					)
				)
				and float(ma_shen.get("concern", 0.0)) >= 60.0
				and (
					float(ma_shen.get("food_spare", 0.0)) > 0.0
					or float(
						market_state.get(
							"neighbor_help_level",
							0.0
						)
					) >= 65.0
				)
				and float(chen_mi.get("hunger", 0.0)) >= 75.0
			)
		"old_chen_sold_shop_goods_for_food":
			var recovery_state := state.micro_state.get(
				"recovery_state",
				{}
			) as Dictionary
			return (
				float(old_chen.get("stress", 0.0)) >= 90.0
				and float(old_chen.get("family_food", 0.0)) <= 0.0
				and float(chen_mi.get("hunger", 0.0)) >= 90.0
				and (
					float(shop_state.get("food_stock", 0.0)) <= 0.0
					or float(
						recovery_state.get(
							"shop_recovery_level",
							0.0
						)
					) < 20.0
				)
			)
		"old_chen_took_chen_mi_to_seek_help":
			return (
				(
					_has_fact_type(
						state,
						"chen_mi_collapsed_from_hunger"
					)
					or float(
						chen_mi.get("health", 100.0)
					) <= 70.0
				)
				and float(old_chen.get("stress", 0.0)) >= 85.0
				and (
					not bool(shop_state.get("is_open", true))
					or _has_fact_type(
						state,
						"old_chen_shop_forced_abnormal_closure"
					)
				)
				and not bool(
					hunger_state.get(
						"chen_mi_temporarily_relocated",
						false
					)
				)
			)
		"lake_town_emergency_credit_food":
			return (
				_has_fact_type(
					state,
					"old_chen_took_chen_mi_to_seek_help"
				)
				and (
					float(
						market_state.get("credit_available", 0.0)
					) >= 60.0
					or float(
						market_state.get(
							"neighbor_help_level",
							0.0
						)
					) >= 68.0
				)
				and not _has_status(
					old_chen,
					"emergency_credit_refused"
				)
				and float(chen_mi.get("hunger", 0.0)) >= 70.0
			)
		"chen_mi_health_crashed_from_hunger":
			return (
				extreme_days >= 3
				and not bool(
					hunger_state.get(
						"emergency_food_received",
						false
					)
				)
				and not bool(
					hunger_state.get(
						"chen_mi_temporarily_relocated",
						false
					)
				)
				and (
					float(
						chen_mi.get("health", 100.0)
					) <= 75.0
					or bool(
						hunger_state.get(
							"health_declining",
							false
						)
					)
				)
			)
		"chen_mi_temporarily_stayed_with_ma_shen":
			return (
				_has_fact_type(
					state,
					"ma_shen_emergency_food_for_chen_mi"
				)
				and float(ma_shen.get("concern", 0.0)) >= 65.0
				and (
					_has_fact_type(
						state,
						"old_chen_shop_forced_abnormal_closure"
					)
					or float(old_chen.get("stress", 0.0)) >= 95.0
					or not bool(shop_state.get("is_open", true))
				)
			)
		"chen_mi_hunger_unresolved_but_recorded":
			return _can_record_unresolved_hunger(state)
	return false


func _can_record_unresolved_hunger(state: WorldSimState) -> bool:
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	if (
		int(hunger_state.get("extreme_hunger_days", 0)) < 3
		or _has_any_hunger_closure(state)
	):
		return false
	for closure_id: String in CLOSURE_IDS:
		if closure_id == "chen_mi_hunger_unresolved_but_recorded":
			continue
		if _can_apply_closure(state, closure_id):
			return false
	return true


func _apply_chen_mi_collapsed(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 12.0
	)
	chen_mi["fear"] = maxf(
		0.0,
		float(chen_mi.get("fear", 0.0)) - 4.0
	)
	_add_status(chen_mi, "collapsed_from_hunger")
	state.npcs[CHEN_MI_ID] = chen_mi
	_set_hunger_flag(state, "chen_mi_collapsed", true)
	var fact := _add_hunger_fact(
		state,
		"chen_mi_collapsed_from_hunger",
		[CHEN_MI_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"chen_mi_endured_hunger",
				"chen_mi_weakened_from_enduring_hunger",
				"old_chen_shop_forced_abnormal_closure",
				"lake_town_food_price_rising",
			]
		),
		{
			"chen_mi.health_delta": -12.0,
			"chen_mi.fear_delta": -4.0,
		},
		["extreme_hunger", "collapse", "child"]
	)
	var trace := _add_trace(
		state,
		"child_collapsed_at_shop_step",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["collapsed_child", "shop_step", "extreme_hunger"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_collapse_blur",
		CHEN_MI_ID,
		fact.id,
		0.98,
		["collapse", "hunger", "blurred_memory"]
	)
	_add_scene(
		state,
		"collapsed_child_at_shop_step_scene",
		"陈米倒在老陈店门口的台阶上",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_ma_shen_emergency_food(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var ma_shen := state.get_npc(MA_SHEN_ID)
	var market := state.get_location(MARKET_ID)
	var market_state := market.get("state", {}) as Dictionary
	var used_spare := float(ma_shen.get("food_spare", 0.0)) > 0.0
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 32.0
	)
	chen_mi["health"] = minf(
		100.0,
		float(chen_mi.get("health", 100.0)) + 6.0
	)
	_add_status(chen_mi, "received_emergency_food")
	if used_spare:
		ma_shen["food_spare"] = maxf(
			0.0,
			float(ma_shen.get("food_spare", 0.0)) - 1.0
		)
	else:
		market_state["neighbor_help_level"] = maxf(
			0.0,
			float(
				market_state.get("neighbor_help_level", 0.0)
			) - 12.0
		)
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[MA_SHEN_ID] = ma_shen
	market["state"] = market_state
	state.locations[MARKET_ID] = market
	_set_hunger_flag(state, "emergency_food_received", true)
	_set_hunger_value(state, "last_hunger_relief_day", state.day)
	var fact := _add_hunger_fact(
		state,
		"ma_shen_emergency_food_for_chen_mi",
		[MA_SHEN_ID, CHEN_MI_ID, OLD_CHEN_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"chen_mi_collapsed_from_hunger",
				"neighbor_noticed_silent_hungry_child",
			]
		),
		{
			"chen_mi.hunger_delta": -32.0,
			"chen_mi.health_delta": 6.0,
			"food_source": (
				"ma_shen_food_spare"
				if used_spare
				else "neighbor_help_level"
			),
		},
		["emergency_food", "neighbor", "child"]
	)
	recovery_system.adjust_micro_relationship(
		state,
		MA_SHEN_ID,
		OLD_CHEN_ID,
		{"trust": 6.0, "familiarity": 10.0},
		fact.id
	)
	recovery_system.add_relationship_tag(
		state,
		MA_SHEN_ID,
		OLD_CHEN_ID,
		"shared_emergency_food",
		fact.id
	)
	var trace := _add_trace(
		state,
		"emergency_food_bowl",
		fact.id,
		SHOP_ID,
		MA_SHEN_ID,
		["warm_bowl", "emergency_food", "neighbor_help"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_emergency_food",
		CHEN_MI_ID,
		fact.id,
		0.95,
		["ma_shen", "food", "emergency"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_old_chen_sold_goods(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	old_chen["family_food"] = (
		float(old_chen.get("family_food", 0.0)) + 7.0
	)
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 6.0
	)
	_add_status(old_chen, "sold_goods_for_food")
	state.npcs[OLD_CHEN_ID] = old_chen
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	_add_dictionary_tag(
		shop_state,
		"status_tags",
		"sold_goods_for_food"
	)
	shop["state"] = shop_state
	_add_dictionary_tag(shop, "tags", "sold_goods_for_food")
	state.locations[SHOP_ID] = shop
	var fact := _add_hunger_fact(
		state,
		"old_chen_sold_shop_goods_for_food",
		[OLD_CHEN_ID, CHEN_MI_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"old_chen_shop_forced_abnormal_closure",
				"creditor_left_debt_notice",
				"lake_town_food_price_rising",
			]
		),
		{
			"old_chen.family_food_delta": 7.0,
			"old_chen.stress_delta": -6.0,
			"old_chen_shop.asset_loss": true,
		},
		["sold_goods", "food", "asset_loss"]
	)
	var trace := _add_trace(
		state,
		"missing_shop_goods",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["empty_shelf_space", "sold_goods", "short_term_food"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_selling_goods_for_food",
		OLD_CHEN_ID,
		fact.id,
		0.9,
		["shop_goods", "family_food", "sacrifice"]
	)
	_add_scene(
		state,
		"old_chen_sold_goods_scene",
		"店里的几样旧货不见了，老陈换回了一点食物",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_old_chen_sought_help(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	chen_mi["location_id"] = MARKET_ID
	old_chen["location_id"] = MARKET_ID
	_add_status(chen_mi, "temporarily_relocated_for_help")
	_add_status(old_chen, "seeking_help_for_chen_mi")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	_set_hunger_flag(
		state,
		"chen_mi_temporarily_relocated",
		true
	)
	var fact := _add_hunger_fact(
		state,
		"old_chen_took_chen_mi_to_seek_help",
		[OLD_CHEN_ID, CHEN_MI_ID],
		MARKET_ID,
		_source_ids(
			state,
			[
				"chen_mi_collapsed_from_hunger",
				"chen_mi_health_crashed_from_hunger",
				"old_chen_shop_forced_abnormal_closure",
			]
		),
		{
			"chen_mi.location_id": MARKET_ID,
			"old_chen.location_id": MARKET_ID,
		},
		["relocation", "seek_help", "closed_shop"]
	)
	var trace := _add_trace(
		state,
		"shop_left_unattended",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		["unattended_shop", "closed_door", "left_for_help"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_carrying_chen_mi_for_help",
		OLD_CHEN_ID,
		fact.id,
		0.98,
		["daughter", "seek_help", "left_shop"]
	)
	_add_scene(
		state,
		"old_chen_left_shop_to_seek_help_scene",
		"老陈带着陈米离开店铺，往集市寻找帮助",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_emergency_credit_food(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var market := state.get_location(MARKET_ID)
	var market_state := market.get("state", {}) as Dictionary
	old_chen["family_food"] = (
		float(old_chen.get("family_food", 0.0)) + 12.0
	)
	old_chen["debt"] = clampf(
		float(old_chen.get("debt", 0.0)) + 8.0,
		0.0,
		100.0
	)
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 26.0
	)
	market_state["credit_available"] = maxf(
		0.0,
		float(market_state.get("credit_available", 0.0)) - 16.0
	)
	state.npcs[OLD_CHEN_ID] = old_chen
	state.npcs[CHEN_MI_ID] = chen_mi
	market["state"] = market_state
	state.locations[MARKET_ID] = market
	_set_hunger_flag(state, "emergency_food_received", true)
	_set_hunger_value(state, "last_hunger_relief_day", state.day)
	var fact := _add_hunger_fact(
		state,
		"lake_town_emergency_credit_food",
		[OLD_CHEN_ID, CHEN_MI_ID],
		MARKET_ID,
		_source_ids(
			state,
			["old_chen_took_chen_mi_to_seek_help"]
		),
		{
			"old_chen.family_food_delta": 12.0,
			"old_chen.debt_delta": 8.0,
			"chen_mi.hunger_delta": -26.0,
			"market.credit_available_delta": -16.0,
		},
		["emergency_credit", "food", "debt"]
	)
	var trace := _add_trace(
		state,
		"emergency_credit_mark",
		fact.id,
		MARKET_ID,
		OLD_CHEN_ID,
		["credit_mark", "emergency_food", "new_debt"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_emergency_credit_food",
		OLD_CHEN_ID,
		fact.id,
		0.9,
		["credit", "food", "debt_pressure"]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_health_crash(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 20.0
	)
	_add_status(chen_mi, "critical_hunger_health")
	state.npcs[CHEN_MI_ID] = chen_mi
	_set_hunger_flag(
		state,
		"critical_health_decline_recorded",
		true
	)
	var fact := _add_hunger_fact(
		state,
		"chen_mi_health_crashed_from_hunger",
		[CHEN_MI_ID, OLD_CHEN_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"chen_mi_collapsed_from_hunger",
				"chen_mi_weakened_from_enduring_hunger",
				"chen_mi_endured_hunger",
			]
		),
		{"chen_mi.health_delta": -20.0},
		["bad_hunger_outcome", "health_crash", "child"]
	)
	var trace := _add_trace(
		state,
		"feverish_child_breath",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["feverish_breath", "weakness", "critical_hunger"]
	)
	var memory := _add_memory(
		state,
		"old_chen_remembers_hunger_crash",
		OLD_CHEN_ID,
		fact.id,
		1.0,
		["daughter", "health_crash", "hunger"]
	)
	_add_scene(
		state,
		"critical_hunger_child_scene",
		"陈米的呼吸变得灼热而微弱",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_temporary_ma_shen_stay(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var ma_shen := state.get_npc(MA_SHEN_ID)
	chen_mi["location_id"] = MA_SHEN_HOME_ID
	_add_status(chen_mi, "temporarily_staying_with_ma_shen")
	_add_status(ma_shen, "caring_for_chen_mi")
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[MA_SHEN_ID] = ma_shen
	_set_hunger_flag(
		state,
		"chen_mi_temporarily_relocated",
		true
	)
	var fact := _add_hunger_fact(
		state,
		"chen_mi_temporarily_stayed_with_ma_shen",
		[CHEN_MI_ID, MA_SHEN_ID, OLD_CHEN_ID],
		MA_SHEN_HOME_ID,
		_source_ids(
			state,
			["ma_shen_emergency_food_for_chen_mi"]
		),
		{"chen_mi.location_id": MA_SHEN_HOME_ID},
		["temporary_stay", "neighbor_care", "relocation"]
	)
	var trace := _add_trace(
		state,
		"small_blanket_at_ma_shen_door",
		fact.id,
		MA_SHEN_HOME_ID,
		CHEN_MI_ID,
		["small_blanket", "temporary_stay", "neighbor_home"]
	)
	var memory := _add_memory(
		state,
		"chen_mi_remembers_staying_with_ma_shen",
		CHEN_MI_ID,
		fact.id,
		0.9,
		["ma_shen", "temporary_home", "care"]
	)
	_add_scene(
		state,
		"chen_mi_stays_with_ma_shen_scene",
		"玛婶在门边铺好小毯子，让陈米暂时住下",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _apply_unresolved_record(
		state: WorldSimState,
		result: Dictionary
	) -> void:
	_set_hunger_flag(
		state,
		"critical_health_decline_recorded",
		true
	)
	var fact := _add_hunger_fact(
		state,
		"chen_mi_hunger_unresolved_but_recorded",
		[CHEN_MI_ID, OLD_CHEN_ID],
		SHOP_ID,
		_source_ids(
			state,
			[
				"lake_town_food_price_rising",
				"chen_mi_endured_hunger",
				"old_chen_shop_forced_abnormal_closure",
			]
		),
		{"hunger_pressure_recorded": true},
		["bad_hunger_outcome", "unresolved", "recorded"]
	)
	var trace := _add_trace(
		state,
		"unchanged_empty_bowl",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		["empty_bowl", "unchanged", "no_help_arrived"]
	)
	var memory := _add_memory(
		state,
		"system_recorded_unresolved_hunger_pressure",
		OLD_CHEN_ID,
		fact.id,
		0.95,
		["unresolved_hunger", "no_help", "recorded"]
	)
	_add_scene(
		state,
		"unresolved_hunger_pressure_scene",
		"空碗仍放在原处，没有人处理持续恶化的饥饿",
		fact,
		[trace],
		[memory]
	)
	_finish(state, result, fact, [trace], [memory])


func _add_hunger_fact(
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
		"",
		{
			"scope": "micro",
			"actors": actors.duplicate(),
			"location_id": location_id,
			"cause_fact_ids": filtered_causes,
			"effects": effects.duplicate(true),
			"tags": tags.duplicate(),
			"importance": 0.9,
			"world_cause": "lake_town_hunger_closure",
			"hunger_closure_key": type_name,
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
		"visibility": 0.95,
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
		"type": "micro_hunger_closure_scene",
		"title": title,
		"location_id": fact.location_id,
		"npc_ids": fact.actors.duplicate(),
		"trace_ids": trace_ids,
		"memory_ids": memory_ids,
		"source_fact_ids": [fact.id],
		"world_cause": "lake_town_hunger_closure",
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
	record_hunger_closure(state, fact.type, fact.id)
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


func _recent_food_help(state: WorldSimState) -> bool:
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	if int(hunger_state.get("last_hunger_relief_day", -10)) >= state.day - 2:
		return true
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.day < state.day - 2:
			break
		if fact.type in RECENT_FOOD_HELP_TYPES:
			return true
	return false


func _has_any_hunger_closure(state: WorldSimState) -> bool:
	for fact in state.world_facts:
		if String(fact.data.get("hunger_closure_key", "")) != "":
			return true
	return false


func _has_fact_type(state: WorldSimState, type_name: String) -> bool:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		if state.world_facts[index].type == type_name:
			return true
	return false


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


func _set_hunger_flag(
		state: WorldSimState,
		key: String,
		value: bool
	) -> void:
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	hunger_state[key] = value
	state.micro_state["hunger_closure_state"] = hunger_state


func _set_hunger_value(
		state: WorldSimState,
		key: String,
		value: Variant
	) -> void:
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	hunger_state[key] = value
	state.micro_state["hunger_closure_state"] = hunger_state


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
