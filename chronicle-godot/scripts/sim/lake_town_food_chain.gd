extends RefCounted
class_name LakeTownFoodChain

const MICRO_REGION_ID := "lake_town"
const MACRO_REGION_ID := "border_town"
const SHOP_ID := "old_chen_shop"
const GRANARY_ID := "abandoned_granary"
const OLD_CHEN_ID := "old_chen"
const CHEN_MI_ID := "chen_mi"

const FOOD_PRESSURE_SCARCITY := 70.0
const FOOD_PRESSURE_FOOD := 50.0
const CHILD_HUNGER_THRESHOLD := 70.0
const FAMILY_FOOD_THRESHOLD := 20.0
const USABLE_FAMILY_FOOD := 5.0
const PARENT_MONEY_THRESHOLD := 8.0
const SHOP_CLOSE_STRESS := 70.0
const VARIATION_FACT_TYPES: Array[String] = [
	"ma_shen_helped_before_theft",
	"old_chen_bought_food_on_credit",
	"chen_mi_found_empty_granary",
	"guard_locked_abandoned_granary",
	"creditor_pressed_before_theft",
	"chen_mi_endured_hunger",
	"other_family_took_granary_grain",
]


func initialize_from_seed(state: WorldSimState, data: Dictionary) -> void:
	if data.is_empty():
		return
	state.micro_state = (
		data.get("state", {}) as Dictionary
	).duplicate(true)
	for npc_value: Variant in data.get("npcs", []):
		var npc := (npc_value as Dictionary).duplicate(true)
		state.npcs[String(npc.get("id", ""))] = npc
	for location_value: Variant in data.get("locations", []):
		var location := (location_value as Dictionary).duplicate(true)
		state.locations[String(location.get("id", ""))] = location
	for item_value: Variant in data.get("items", []):
		var item := (item_value as Dictionary).duplicate(true)
		state.items[String(item.get("id", ""))] = item


func advance_one_day(state: WorldSimState) -> void:
	if not is_initialized(state):
		return
	var macro_region_id := String(
		state.micro_state.get("macro_region_id", MACRO_REGION_ID)
	)
	var macro_region := state.get_region(macro_region_id)
	if macro_region == null:
		return

	var price_fact := _update_food_price(state, macro_region)
	_update_household_pressure(state, macro_region)
	_update_chen_mi_needs(state)
	var variation_fact := _advance_profile_variation(
		state,
		macro_region,
		price_fact
	)
	var grain_fact := _resolve_chen_mi_food_search(state, price_fact)
	var closed_fact := _maybe_close_shop(
		state,
		price_fact,
		grain_fact,
		variation_fact
	)
	_maybe_create_narratable_state(
		state,
		price_fact,
		grain_fact,
		closed_fact
	)
	state.micro_state["last_update_day"] = state.day


func is_initialized(state: WorldSimState) -> bool:
	return (
		state.npcs.has(OLD_CHEN_ID)
		and state.npcs.has(CHEN_MI_ID)
		and state.locations.has(SHOP_ID)
		and state.locations.has(GRANARY_ID)
	)


func _update_food_price(
		state: WorldSimState,
		macro_region: WorldSimState.RegionState
	) -> WorldSimState.WorldFact:
	var existing := _fact_from_micro_key(state, "food_price_fact_id")
	var pressure_active := (
		macro_region.scarcity >= FOOD_PRESSURE_SCARCITY
		or macro_region.food <= FOOD_PRESSURE_FOOD
	)
	if not pressure_active:
		return existing

	var scarcity_pressure := maxf(
		0.0,
		macro_region.scarcity - 60.0
	) * 0.012
	var food_pressure := maxf(
		0.0,
		FOOD_PRESSURE_FOOD - macro_region.food
	) * 0.008
	var increase := clampf(
		scarcity_pressure + food_pressure,
		0.12,
		0.65
	)
	var price_index := clampf(
		float(state.micro_state.get("food_price_index", 1.0)) + increase,
		1.0,
		5.0
	)
	state.micro_state["food_price_index"] = snappedf(price_index, 0.01)

	var market := state.get_location("lake_town_market")
	var market_state := market.get("state", {}) as Dictionary
	market_state["food_price_index"] = state.micro_state["food_price_index"]
	market["state"] = market_state
	state.locations["lake_town_market"] = market

	if existing != null:
		return existing

	var macro_fact_id := _latest_fact_id(
		state,
		String(state.micro_state.get("macro_region_id", MACRO_REGION_ID)),
		["raid_supplies", "region_daily_shift", "escort_supplies"]
	)
	var cause_fact_ids: Array[String] = []
	if macro_fact_id != "":
		cause_fact_ids.append(macro_fact_id)
	var fact := state.add_fact(
		"lake_town_food_price_rising",
		MICRO_REGION_ID,
		"",
		{
			"scope": "micro",
			"actors": [],
			"location_id": "lake_town_market",
			"cause_fact_ids": cause_fact_ids,
			"effects": {
				"food_price_index": state.micro_state["food_price_index"],
				"price_notice": true,
			},
			"tags": ["food_crisis", "price_rise"],
			"importance": 0.7,
			"macro_scarcity": macro_region.scarcity,
			"macro_food": macro_region.food,
		}
	)
	state.micro_state["food_price_fact_id"] = fact.id

	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["price_notice"] = true
	shop["state"] = shop_state
	state.locations[SHOP_ID] = shop
	_activate_item(state, "price_notice", fact.id)
	_add_trace(
		state,
		"price_rise_notice",
		fact.id,
		SHOP_ID,
		"",
		0.95,
		["wet_paper", "higher_food_price", "shop_notice"]
	)
	return fact


func _update_household_pressure(
		state: WorldSimState,
		macro_region: WorldSimState.RegionState
	) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	var price_index := float(
		state.micro_state.get("food_price_index", 1.0)
	)
	var pressure_active := (
		macro_region.scarcity >= FOOD_PRESSURE_SCARCITY
		or macro_region.food <= FOOD_PRESSURE_FOOD
	)

	var household_consumption := 2.0
	if pressure_active:
		household_consumption += minf(price_index * 0.8, 2.0)
		shop_state["food_stock"] = maxf(
			0.0,
			float(shop_state.get("food_stock", 0.0))
			- 1.0
			- minf(price_index * 0.45, 1.5)
		)
		old_chen["debt"] = clampf(
			float(old_chen.get("debt", 0.0))
			+ 0.8
			+ price_index * 0.65,
			0.0,
			100.0
		)
		old_chen["money"] = maxf(
			0.0,
			float(old_chen.get("money", 0.0))
			- 0.6
			- price_index * 0.25
		)

	old_chen["family_food"] = maxf(
		0.0,
		float(old_chen.get("family_food", 0.0)) - household_consumption
	)
	var family_shortage := maxf(
		0.0,
		FAMILY_FOOD_THRESHOLD - float(old_chen.get("family_food", 0.0))
	)
	var stress_delta := (
		1.5
		+ price_index * 0.9
		+ float(old_chen.get("debt", 0.0)) * 0.025
		+ family_shortage * 0.18
	)
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + stress_delta,
		0.0,
		100.0
	)
	var needs := old_chen.get("needs", {}) as Dictionary
	needs["food"] = clampf(
		100.0 - float(old_chen.get("family_food", 0.0)) * 2.5,
		0.0,
		100.0
	)
	needs["money"] = clampf(
		float(old_chen.get("debt", 0.0))
		+ (PARENT_MONEY_THRESHOLD - float(old_chen.get("money", 0.0))) * 4.0,
		0.0,
		100.0
	)
	old_chen["needs"] = needs
	state.npcs[OLD_CHEN_ID] = old_chen
	shop["state"] = shop_state
	state.locations[SHOP_ID] = shop


func _update_chen_mi_needs(state: WorldSimState) -> void:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var family_food := float(old_chen.get("family_food", 0.0))
	var hunger_delta := 1.0
	if family_food <= FAMILY_FOOD_THRESHOLD:
		hunger_delta = 5.0
	if family_food < USABLE_FAMILY_FOOD:
		hunger_delta = 9.0
	if family_food <= 0.0:
		hunger_delta = 11.0
	chen_mi["hunger"] = clampf(
		float(chen_mi.get("hunger", 0.0)) + hunger_delta,
		0.0,
		100.0
	)
	if float(chen_mi.get("hunger", 0.0)) >= CHILD_HUNGER_THRESHOLD:
		chen_mi["fear"] = clampf(
			float(chen_mi.get("fear", 0.0)) + 1.5,
			0.0,
			100.0
		)
	var needs := chen_mi.get("needs", {}) as Dictionary
	needs["food"] = float(chen_mi.get("hunger", 0.0))
	needs["safety"] = float(chen_mi.get("fear", 0.0))
	chen_mi["needs"] = needs
	state.npcs[CHEN_MI_ID] = chen_mi


func _advance_profile_variation(
		state: WorldSimState,
		macro_region: WorldSimState.RegionState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	if not state.micro_state.has("seed_profile"):
		return null
	var variation_state := state.micro_state.get(
		"history_variation",
		{}
	) as Dictionary
	if int(variation_state.get("last_update_day", 0)) == state.day:
		return null
	variation_state["last_update_day"] = state.day
	state.micro_state["history_variation"] = variation_state
	if _fact_exists(state, "chen_mi_took_spoiled_grain"):
		return null

	var latest: WorldSimState.WorldFact = null
	if _can_other_family_take_grain(state, macro_region):
		latest = _apply_other_family_took_grain(state, price_fact)
	elif _can_guard_lock_granary(state, macro_region):
		latest = _apply_guard_locked_granary(state, price_fact)

	if _can_creditor_press_early(state):
		latest = _apply_creditor_pressed_early(state, price_fact)

	var ma_score := _ma_shen_early_help_score(state)
	var credit_score := _old_chen_credit_score(state)
	if ma_score >= 0.0 or credit_score >= 0.0:
		if ma_score >= credit_score:
			latest = _apply_ma_shen_helped_early(state, price_fact)
		else:
			latest = _apply_old_chen_credit_purchase(state, price_fact)
	return latest


func _can_other_family_take_grain(
		state: WorldSimState,
		macro_region: WorldSimState.RegionState
	) -> bool:
	if _variation_has_happened(state, "other_family_took_granary_grain"):
		return false
	var market_state := (
		state.get_location("lake_town_market").get("state", {})
		as Dictionary
	)
	var granary_state := (
		state.get_location(GRANARY_ID).get("state", {})
		as Dictionary
	)
	return (
		macro_region.scarcity >= 68.0
		and float(market_state.get("neighbor_help_level", 100.0)) <= 55.0
		and float(market_state.get("other_family_pressure", 0.0)) >= 62.0
		and float(granary_state.get("spoiled_grain_stock", 0.0)) > 0.0
		and not bool(granary_state.get("locked_by_guard", false))
	)


func _can_guard_lock_granary(
		state: WorldSimState,
		macro_region: WorldSimState.RegionState
	) -> bool:
	if _variation_has_happened(state, "guard_locked_abandoned_granary"):
		return false
	var granary_state := (
		state.get_location(GRANARY_ID).get("state", {})
		as Dictionary
	)
	if bool(granary_state.get("locked_by_guard", false)):
		return false
	var pressure_score := (
		float(state.micro_state.get("guard_pressure", 0.0))
		+ float(granary_state.get("guard_watch", 0.0)) * 0.55
		+ float(granary_state.get("visibility", 0.0)) * 0.45
		+ maxf(0.0, macro_region.scarcity - 60.0) * 0.8
	)
	return macro_region.scarcity >= 66.0 and pressure_score >= 145.0


func _can_creditor_press_early(state: WorldSimState) -> bool:
	if _variation_has_happened(state, "creditor_pressed_before_theft"):
		return false
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var creditor := state.get_npc("liu_zhangfang")
	return (
		float(old_chen.get("debt", 0.0)) >= 58.0
		and float(creditor.get("strictness", 0.0)) >= 62.0
		and float(creditor.get("patience", 100.0)) <= 48.0
	)


func _ma_shen_early_help_score(state: WorldSimState) -> float:
	if _variation_has_happened(state, "ma_shen_helped_before_theft"):
		return -1.0
	var ma_shen := state.get_npc("ma_shen")
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var market_state := (
		state.get_location("lake_town_market").get("state", {})
		as Dictionary
	)
	if (
		float(chen_mi.get("hunger", 0.0)) < 60.0
		or float(old_chen.get("family_food", 100.0)) > 20.0
		or float(ma_shen.get("food_spare", 0.0)) <= 0.0
		or float(ma_shen.get("concern", 0.0)) < 58.0
		or float(ma_shen.get("trust_to_old_chen", 0.0)) < 45.0
	):
		return -1.0
	var score := (
		float(ma_shen.get("concern", 0.0))
		+ float(ma_shen.get("trust_to_old_chen", 0.0))
		+ float(market_state.get("neighbor_help_level", 0.0)) * 0.4
		- float(ma_shen.get("risk_aversion", 0.0)) * 0.25
		+ float(chen_mi.get("hunger", 0.0)) * 0.3
	)
	return score if score >= 135.0 else -1.0


func _old_chen_credit_score(state: WorldSimState) -> float:
	if _variation_has_happened(state, "old_chen_bought_food_on_credit"):
		return -1.0
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var market_state := (
		state.get_location("lake_town_market").get("state", {})
		as Dictionary
	)
	var family_food := float(old_chen.get("family_food", 0.0))
	var debt := float(old_chen.get("debt", 0.0))
	var pride := float(old_chen.get("pride", 50.0))
	var help_seeking := float(old_chen.get("help_seeking", 50.0))
	var credit_available := float(
		market_state.get("credit_available", 0.0)
	)
	if (
		family_food > 18.0
		or debt >= 82.0
		or credit_available < 55.0
		or (help_seeking < 55.0 and pride > 42.0)
	):
		return -1.0
	var score := (
		credit_available
		+ help_seeking * 0.55
		+ (100.0 - pride) * 0.35
		- float(state.micro_state.get("market_disruption", 0.0)) * 0.25
	)
	return score if score >= 105.0 else -1.0


func _apply_other_family_took_grain(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var market_state := (
		state.get_location("lake_town_market").get("state", {})
		as Dictionary
	)
	var pressure := float(market_state.get("other_family_pressure", 0.0))
	var granary := state.get_location(GRANARY_ID)
	var granary_state := granary.get("state", {}) as Dictionary
	var stock_before := float(
		granary_state.get("spoiled_grain_stock", 0.0)
	)
	var amount := minf(
		stock_before,
		1.0 + floorf(maxf(0.0, pressure - 62.0) / 18.0)
	)
	granary_state["spoiled_grain_stock"] = maxf(
		0.0,
		stock_before - amount
	)
	granary["state"] = granary_state
	state.locations[GRANARY_ID] = granary
	_sync_spoiled_grain_item(state)
	var fact := _add_variation_fact(
		state,
		"other_family_took_granary_grain",
		[],
		GRANARY_ID,
		_variation_causes(state, price_fact),
		{
			"abandoned_granary.spoiled_grain_stock_delta": -amount,
			"other_family_pressure": pressure,
		},
		["food_crisis", "other_family", "shared_resource"]
	)
	_add_trace(
		state,
		"unfamiliar_footprints_at_granary",
		fact.id,
		GRANARY_ID,
		"",
		0.75,
		["unfamiliar_footprints", "hungry_family", "missing_grain"]
	)
	_record_variation(state, fact)
	return fact


func _apply_guard_locked_granary(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var granary := state.get_location(GRANARY_ID)
	var granary_state := granary.get("state", {}) as Dictionary
	granary_state["locked_by_guard"] = true
	granary["state"] = granary_state
	var tags := granary.get("tags", []) as Array
	if not "locked_by_guard" in tags:
		tags.append("locked_by_guard")
	granary["tags"] = tags
	state.locations[GRANARY_ID] = granary
	var fact := _add_variation_fact(
		state,
		"guard_locked_abandoned_granary",
		["wardens"],
		GRANARY_ID,
		_variation_causes(state, price_fact),
		{
			"abandoned_granary.locked_by_guard": true,
			"guard_pressure": state.micro_state.get(
				"guard_pressure",
				0.0
			),
		},
		["guard", "granary", "scarcity"]
	)
	_add_trace(
		state,
		"guard_seal_on_granary",
		fact.id,
		GRANARY_ID,
		"wardens",
		0.95,
		["guard_seal", "locked_door", "scarcity_control"]
	)
	_record_variation(state, fact)
	return fact


func _apply_creditor_pressed_early(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var stress_delta := 12.0 + float(old_chen.get("debt", 0.0)) * 0.05
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + stress_delta,
		0.0,
		100.0
	)
	_add_status_tag(old_chen, "early_creditor_pressure")
	state.npcs[OLD_CHEN_ID] = old_chen
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["family_crisis"] = true
	shop["state"] = shop_state
	state.locations[SHOP_ID] = shop
	var fact := _add_variation_fact(
		state,
		"creditor_pressed_before_theft",
		["liu_zhangfang", OLD_CHEN_ID],
		SHOP_ID,
		_variation_causes(state, price_fact),
		{
			"old_chen.stress_delta": stress_delta,
			"old_chen_shop.family_crisis": true,
		},
		["debt", "creditor", "early_pressure"]
	)
	_add_trace(
		state,
		"early_debt_mark_on_shop",
		fact.id,
		SHOP_ID,
		"liu_zhangfang",
		0.9,
		["debt_mark", "red_ink", "early_collection"]
	)
	_add_variation_memory(
		state,
		"old_chen_remembers_early_debt_pressure",
		OLD_CHEN_ID,
		fact.id,
		0.9,
		["debt", "pressure", "liu_zhangfang"]
	)
	_record_variation(state, fact)
	return fact


func _apply_ma_shen_helped_early(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var ma_shen := state.get_npc("ma_shen")
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var old_chen := state.get_npc(OLD_CHEN_ID)
	ma_shen["food_spare"] = maxf(
		0.0,
		float(ma_shen.get("food_spare", 0.0)) - 1.0
	)
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 34.0
	)
	old_chen["family_food"] = float(
		old_chen.get("family_food", 0.0)
	) + 2.0
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 7.0
	)
	state.npcs["ma_shen"] = ma_shen
	state.npcs[CHEN_MI_ID] = chen_mi
	state.npcs[OLD_CHEN_ID] = old_chen
	var fact := _add_variation_fact(
		state,
		"ma_shen_helped_before_theft",
		["ma_shen", CHEN_MI_ID, OLD_CHEN_ID],
		SHOP_ID,
		_variation_causes(state, price_fact),
		{
			"ma_shen.food_spare_delta": -1.0,
			"chen_mi.hunger_delta": -34.0,
			"old_chen.family_food_delta": 2.0,
			"old_chen.stress_delta": -7.0,
		},
		["neighbor", "early_help", "food_crisis"]
	)
	_add_trace(
		state,
		"porridge_bowl_before_crisis",
		fact.id,
		SHOP_ID,
		"ma_shen",
		0.9,
		["porridge_bowl", "neighbor_help", "before_theft"]
	)
	_add_variation_memory(
		state,
		"chen_mi_remembers_ma_shen_help_before_theft",
		CHEN_MI_ID,
		fact.id,
		0.85,
		["ma_shen", "food_help", "before_theft"]
	)
	_record_variation(state, fact)
	return fact


func _apply_old_chen_credit_purchase(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	old_chen["family_food"] = float(
		old_chen.get("family_food", 0.0)
	) + 16.0
	old_chen["debt"] = clampf(
		float(old_chen.get("debt", 0.0)) + 12.0,
		0.0,
		100.0
	)
	old_chen["stress"] = maxf(
		0.0,
		float(old_chen.get("stress", 0.0)) - 3.0
	)
	chen_mi["hunger"] = maxf(
		0.0,
		float(chen_mi.get("hunger", 0.0)) - 8.0
	)
	state.npcs[OLD_CHEN_ID] = old_chen
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_variation_fact(
		state,
		"old_chen_bought_food_on_credit",
		[OLD_CHEN_ID],
		"lake_town_market",
		_variation_causes(state, price_fact),
		{
			"old_chen.family_food_delta": 16.0,
			"old_chen.debt_delta": 12.0,
			"old_chen.stress_delta": -3.0,
			"chen_mi.hunger_delta": -8.0,
		},
		["credit", "food_purchase", "delayed_crisis"]
	)
	_add_trace(
		state,
		"market_credit_mark",
		fact.id,
		"lake_town_market",
		OLD_CHEN_ID,
		0.75,
		["credit_mark", "food_purchase", "debt"]
	)
	_add_variation_memory(
		state,
		"old_chen_remembers_credit_purchase",
		OLD_CHEN_ID,
		fact.id,
		0.75,
		["credit", "food", "debt"]
	)
	_record_variation(state, fact)
	return fact


func _resolve_chen_mi_food_search(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var existing := _fact_from_micro_key(state, "spoiled_grain_fact_id")
	if existing != null:
		return existing

	var old_chen := state.get_npc(OLD_CHEN_ID)
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var hunger := float(chen_mi.get("hunger", 0.0))
	if hunger < CHILD_HUNGER_THRESHOLD:
		return null

	var family_food := float(old_chen.get("family_food", 0.0))
	if family_food >= USABLE_FAMILY_FOOD:
		old_chen["family_food"] = maxf(
			0.0,
			family_food - USABLE_FAMILY_FOOD
		)
		chen_mi["hunger"] = maxf(0.0, hunger - 22.0)
		state.npcs[OLD_CHEN_ID] = old_chen
		state.npcs[CHEN_MI_ID] = chen_mi
		return null

	var parent_money := float(old_chen.get("money", 0.0))
	if parent_money >= PARENT_MONEY_THRESHOLD:
		old_chen["money"] = parent_money - PARENT_MONEY_THRESHOLD
		old_chen["family_food"] = family_food + 6.0
		chen_mi["hunger"] = maxf(0.0, hunger - 16.0)
		state.npcs[OLD_CHEN_ID] = old_chen
		state.npcs[CHEN_MI_ID] = chen_mi
		return null

	var granary := state.get_location(GRANARY_ID)
	var granary_state := granary.get("state", {}) as Dictionary
	var spoiled_stock := float(
		granary_state.get("spoiled_grain_stock", 0.0)
	)
	if state.micro_state.has("seed_profile"):
		if spoiled_stock < 1.0:
			return _apply_empty_granary_path(state, price_fact)
		if bool(granary_state.get("locked_by_guard", false)):
			_add_status_tag(chen_mi, "granary_locked")
			state.npcs[CHEN_MI_ID] = chen_mi
			return null
		if _should_endure_hunger(state, old_chen, chen_mi):
			return _apply_endured_hunger_path(state, price_fact)
		if not _chen_mi_will_take_grain(state, old_chen, chen_mi):
			_add_status_tag(chen_mi, "hesitating_to_take_grain")
			state.npcs[CHEN_MI_ID] = chen_mi
			return null
	if (
		family_food > FAMILY_FOOD_THRESHOLD
		or parent_money >= PARENT_MONEY_THRESHOLD
		or spoiled_stock < 1.0
		or not bool(granary_state.get("is_known_to_children", false))
	):
		_add_status_tag(chen_mi, "enduring_hunger")
		state.npcs[CHEN_MI_ID] = chen_mi
		return null

	granary_state["spoiled_grain_stock"] = spoiled_stock - 1.0
	granary["state"] = granary_state
	state.locations[GRANARY_ID] = granary
	var spoiled_item := state.get_item("spoiled_grain")
	spoiled_item["amount"] = maxf(
		0.0,
		float(spoiled_item.get("amount", 0.0)) - 1.0
	)
	state.items["spoiled_grain"] = spoiled_item

	var inventory := chen_mi.get("inventory", []) as Array
	inventory.append("spoiled_grain")
	chen_mi["inventory"] = inventory
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 20.0,
		0.0,
		100.0
	)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 0.0)) - 4.0
	)
	chen_mi["location_id"] = SHOP_ID
	_add_status_tag(chen_mi, "hiding_spoiled_grain")
	_add_status_tag(chen_mi, "disease_risk")

	var cause_fact_ids: Array[String] = []
	if price_fact != null:
		cause_fact_ids.append(price_fact.id)
	var fact := state.add_fact(
		"chen_mi_took_spoiled_grain",
		MICRO_REGION_ID,
		"",
		{
			"scope": "micro",
			"actors": [CHEN_MI_ID],
			"location_id": GRANARY_ID,
			"cause_fact_ids": cause_fact_ids,
			"effects": {
				"chen_mi.inventory": "spoiled_grain",
				"chen_mi.fear_delta": 20.0,
				"chen_mi.health_delta": -4.0,
				"abandoned_granary.spoiled_grain_stock_delta": -1.0,
				"old_chen_shop.family_crisis": true,
			},
			"tags": ["food_crisis", "child", "spoiled_food", "secret"],
			"importance": 0.9,
		}
	)
	state.micro_state["spoiled_grain_fact_id"] = fact.id
	var memories := chen_mi.get("memories", []) as Array
	memories.append(fact.id)
	chen_mi["memories"] = memories
	state.npcs[CHEN_MI_ID] = chen_mi

	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["family_crisis"] = true
	shop["state"] = shop_state
	state.locations[SHOP_ID] = shop
	old_chen["stress"] = clampf(
		float(old_chen.get("stress", 0.0)) + 15.0,
		0.0,
		100.0
	)
	_add_status_tag(old_chen, "family_crisis")
	state.npcs[OLD_CHEN_ID] = old_chen

	_activate_item(state, "hidden_bag", fact.id)
	_activate_item(state, "grain_dust", fact.id)
	_add_trace(
		state,
		"child_hiding_bag",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		0.9,
		["child", "hidden_bag", "fear"]
	)
	_add_trace(
		state,
		"spoiled_grain_bag",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		0.95,
		["spoiled_grain", "mold", "food_crisis"]
	)
	_add_trace(
		state,
		"grain_dust_on_sleeve",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		0.65,
		["grain_dust", "sleeve", "granary"]
	)
	_add_trace(
		state,
		"granary_missing_grain",
		fact.id,
		GRANARY_ID,
		CHEN_MI_ID,
		0.55,
		["missing_grain", "small_footprints", "spoiled_stock"]
	)
	return fact


func _apply_empty_granary_path(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	if _variation_has_happened(state, "chen_mi_found_empty_granary"):
		return null
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 12.0,
		0.0,
		100.0
	)
	_add_status_tag(chen_mi, "returned_from_empty_granary")
	state.npcs[CHEN_MI_ID] = chen_mi
	var causes := _variation_causes(
		state,
		price_fact,
		["other_family_took_granary_grain"]
	)
	var fact := _add_variation_fact(
		state,
		"chen_mi_found_empty_granary",
		[CHEN_MI_ID],
		GRANARY_ID,
		causes,
		{"chen_mi.fear_delta": 12.0},
		["child", "empty_granary", "food_crisis"]
	)
	var trace_id := "empty_granary_shelf"
	_add_trace(
		state,
		trace_id,
		fact.id,
		GRANARY_ID,
		CHEN_MI_ID,
		0.9,
		["empty_shelf", "grain_dust", "no_food"]
	)
	var memory := _add_variation_memory(
		state,
		"chen_mi_remembers_empty_granary",
		CHEN_MI_ID,
		fact.id,
		0.9,
		["empty_granary", "hunger", "fear"]
	)
	_add_variation_scene(
		state,
		"chen_mi_returned_empty_handed_scene",
		"陈米从空粮仓里空手回来了",
		fact,
		[_trace_id_for_type(state, trace_id)],
		[String(memory.get("id", ""))]
	)
	_record_variation(state, fact)
	return fact


func _should_endure_hunger(
		state: WorldSimState,
		old_chen: Dictionary,
		chen_mi: Dictionary
	) -> bool:
	if _variation_has_happened(state, "chen_mi_endured_hunger"):
		return false
	var market_state := (
		state.get_location("lake_town_market").get("state", {})
		as Dictionary
	)
	var reliable_food := (
		float(old_chen.get("family_food", 0.0)) >= USABLE_FAMILY_FOOD
		or float(old_chen.get("money", 0.0)) >= PARENT_MONEY_THRESHOLD
		or float(market_state.get("credit_available", 0.0)) >= 70.0
	)
	return (
		not reliable_food
		and float(chen_mi.get("fearfulness", 0.0)) >= 64.0
		and float(chen_mi.get("boldness", 100.0)) <= 46.0
	)


func _chen_mi_will_take_grain(
		state: WorldSimState,
		old_chen: Dictionary,
		chen_mi: Dictionary
	) -> bool:
	if "avoids_granary" in (chen_mi.get("status_tags", []) as Array):
		return false
	var granary_state := (
		state.get_location(GRANARY_ID).get("state", {})
		as Dictionary
	)
	var willingness := (
		float(chen_mi.get("boldness", 50.0))
		+ float(old_chen.get("risk_tolerance", 50.0)) * 0.35
		- float(chen_mi.get("fearfulness", 50.0)) * 0.4
		- float(granary_state.get("guard_watch", 0.0)) * 0.15
	)
	return willingness >= 28.0


func _apply_endured_hunger_path(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact
	) -> WorldSimState.WorldFact:
	var chen_mi := state.get_npc(CHEN_MI_ID)
	chen_mi["health"] = maxf(
		0.0,
		float(chen_mi.get("health", 100.0)) - 8.0
	)
	chen_mi["fear"] = clampf(
		float(chen_mi.get("fear", 0.0)) + 10.0,
		0.0,
		100.0
	)
	_add_status_tag(chen_mi, "enduring_hunger")
	_add_status_tag(chen_mi, "avoids_granary")
	state.npcs[CHEN_MI_ID] = chen_mi
	var fact := _add_variation_fact(
		state,
		"chen_mi_endured_hunger",
		[CHEN_MI_ID],
		SHOP_ID,
		_variation_causes(state, price_fact),
		{
			"chen_mi.health_delta": -8.0,
			"chen_mi.fear_delta": 10.0,
		},
		["child", "hunger", "fear"]
	)
	_add_trace(
		state,
		"child_waited_on_shop_step",
		fact.id,
		SHOP_ID,
		CHEN_MI_ID,
		0.8,
		["waiting_child", "hunger", "fear"]
	)
	_add_variation_memory(
		state,
		"chen_mi_remembers_enduring_hunger",
		CHEN_MI_ID,
		fact.id,
		0.9,
		["hunger", "fear", "waiting"]
	)
	_record_variation(state, fact)
	return fact


func _maybe_close_shop(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact,
		grain_fact: WorldSimState.WorldFact,
		variation_fact: WorldSimState.WorldFact = null
	) -> WorldSimState.WorldFact:
	var existing := _fact_from_micro_key(state, "closed_shop_fact_id")
	if existing != null:
		return existing
	var old_chen := state.get_npc(OLD_CHEN_ID)
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	if (
		float(old_chen.get("stress", 0.0)) < SHOP_CLOSE_STRESS
		or not bool(shop_state.get("family_crisis", false))
		or not bool(shop_state.get("is_open", false))
	):
		return null

	shop_state["is_open"] = false
	shop["state"] = shop_state
	state.locations[SHOP_ID] = shop
	_add_status_tag(old_chen, "shop_closed")
	var cause_fact_ids: Array[String] = []
	if price_fact != null:
		cause_fact_ids.append(price_fact.id)
	if grain_fact != null:
		cause_fact_ids.append(grain_fact.id)
	if (
		variation_fact != null
		and not variation_fact.id in cause_fact_ids
	):
		cause_fact_ids.append(variation_fact.id)
	for fact in state.world_facts:
		if (
			fact.day == state.day
			and fact.type in VARIATION_FACT_TYPES
			and not fact.id in cause_fact_ids
		):
			cause_fact_ids.append(fact.id)
	var fact := state.add_fact(
		"old_chen_closed_shop_due_to_family_crisis",
		MICRO_REGION_ID,
		"",
		{
			"scope": "micro",
			"actors": [OLD_CHEN_ID],
			"location_id": SHOP_ID,
			"cause_fact_ids": cause_fact_ids,
			"effects": {
				"old_chen_shop.is_open": false,
				"old_chen.status": "shop_closed",
			},
			"tags": ["food_crisis", "closed_shop", "family"],
			"importance": 0.85,
		}
	)
	state.micro_state["closed_shop_fact_id"] = fact.id
	var memories := old_chen.get("memories", []) as Array
	memories.append(fact.id)
	old_chen["memories"] = memories
	state.npcs[OLD_CHEN_ID] = old_chen
	_activate_item(state, "closed_shop", fact.id)
	_add_trace(
		state,
		"closed_shop",
		fact.id,
		SHOP_ID,
		OLD_CHEN_ID,
		1.0,
		["locked_door", "family_crisis", "no_trade"]
	)
	return fact


func _maybe_create_narratable_state(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact,
		grain_fact: WorldSimState.WorldFact,
		closed_fact: WorldSimState.WorldFact
	) -> void:
	if _narratable_exists(state, "chen_mi_hiding_spoiled_grain_scene"):
		return
	if price_fact == null or grain_fact == null or closed_fact == null:
		return
	var shop := state.get_location(SHOP_ID)
	var shop_state := shop.get("state", {}) as Dictionary
	var chen_mi := state.get_npc(CHEN_MI_ID)
	var inventory := chen_mi.get("inventory", []) as Array
	if (
		bool(shop_state.get("is_open", true))
		or not bool(shop_state.get("price_notice", false))
		or String(chen_mi.get("location_id", "")) != SHOP_ID
		or not "spoiled_grain" in inventory
	):
		return
	var required_trace_types: Array[String] = [
		"closed_shop",
		"price_rise_notice",
		"child_hiding_bag",
		"spoiled_grain_bag",
	]
	var trace_ids: Array[String] = []
	for trace_type: String in required_trace_types:
		var trace_id := _trace_id_for_type(state, trace_type)
		if trace_id == "":
			return
		trace_ids.append(trace_id)
	state.narratable_states.append({
		"id": "chen_mi_hiding_spoiled_grain_scene",
		"type": "micro_scene",
		"title": "陈米藏着一袋发霉麦子",
		"location_id": SHOP_ID,
		"npc_ids": [OLD_CHEN_ID, CHEN_MI_ID],
		"trace_ids": trace_ids,
		"source_fact_ids": [
			price_fact.id,
			grain_fact.id,
			closed_fact.id,
		],
		"world_cause": "lake_town_food_crisis_chain",
		"importance": 0.95,
		"available_actions_hint": [
			"give_food_to_chen_mi",
			"ask_grain_origin",
			"report_to_guard",
			"ignore_chen_mi",
			"buy_spoiled_grain_low",
		],
		"status": "open",
		"action_locked": false,
		"created_day": state.day,
	})


func _add_variation_fact(
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
	return state.add_fact(
		type_name,
		MICRO_REGION_ID,
		"wardens" if type_name == "guard_locked_abandoned_granary" else "",
		{
			"scope": "micro",
			"actors": actors.duplicate(),
			"location_id": location_id,
			"cause_fact_ids": filtered_causes,
			"effects": effects.duplicate(true),
			"tags": tags.duplicate(),
			"importance": 0.78,
			"world_cause": "lake_town_history_variation",
			"history_variation_key": type_name,
		}
	)


func _variation_causes(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact,
		preferred_types: Array[String] = []
	) -> Array[String]:
	var causes: Array[String] = []
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.type in preferred_types and not fact.id in causes:
			causes.append(fact.id)
	if price_fact != null and not price_fact.id in causes:
		causes.append(price_fact.id)
	var macro_fact_id := _latest_fact_id(
		state,
		String(state.micro_state.get("macro_region_id", MACRO_REGION_ID)),
		["raid_supplies", "region_daily_shift", "escort_supplies"]
	)
	if macro_fact_id != "" and not macro_fact_id in causes:
		causes.append(macro_fact_id)
	if causes.is_empty() and not state.world_facts.is_empty():
		causes.append(state.world_facts[-1].id)
	return causes


func _record_variation(
		state: WorldSimState,
		fact: WorldSimState.WorldFact
	) -> void:
	var variation_state := state.micro_state.get(
		"history_variation",
		{}
	) as Dictionary
	var history := variation_state.get("path_history", []) as Array
	history.append({
		"path_id": fact.type,
		"fact_id": fact.id,
		"day": fact.day,
	})
	variation_state["path_history"] = history
	variation_state["last_path_day"] = fact.day
	state.micro_state["history_variation"] = variation_state


func _variation_has_happened(
		state: WorldSimState,
		path_id: String
	) -> bool:
	var variation_state := state.micro_state.get(
		"history_variation",
		{}
	) as Dictionary
	for entry_value: Variant in variation_state.get("path_history", []):
		var entry := entry_value as Dictionary
		if String(entry.get("path_id", "")) == path_id:
			return true
	return _fact_exists(state, path_id)


func _add_variation_memory(
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


func _add_variation_scene(
		state: WorldSimState,
		scene_id: String,
		title: String,
		fact: WorldSimState.WorldFact,
		trace_ids: Array,
		memory_ids: Array
	) -> void:
	if _narratable_exists(state, scene_id):
		return
	state.narratable_states.append({
		"id": scene_id,
		"type": "micro_history_variation_scene",
		"title": title,
		"location_id": fact.location_id,
		"npc_ids": fact.actors.duplicate(),
		"trace_ids": trace_ids.duplicate(),
		"memory_ids": memory_ids.duplicate(),
		"source_fact_ids": [fact.id],
		"world_cause": "lake_town_history_variation",
		"importance": fact.importance,
		"status": "open",
		"action_locked": false,
		"created_day": state.day,
	})


func _sync_spoiled_grain_item(state: WorldSimState) -> void:
	var granary_state := (
		state.get_location(GRANARY_ID).get("state", {})
		as Dictionary
	)
	var item := state.get_item("spoiled_grain")
	if item.is_empty():
		return
	item["amount"] = float(
		granary_state.get("spoiled_grain_stock", 0.0)
	)
	state.items["spoiled_grain"] = item


func _add_trace(
		state: WorldSimState,
		type_name: String,
		source_fact_id: String,
		location_id: String,
		npc_id: String,
		visibility: float,
		description_tags: Array[String]
	) -> void:
	if source_fact_id == "" or _trace_id_for_type(state, type_name) != "":
		return
	var trace_id := "trace_%s" % type_name
	state.traces.append({
		"id": trace_id,
		"type": type_name,
		"source_fact_id": source_fact_id,
		"location_id": location_id,
		"npc_id": npc_id,
		"visibility": clampf(visibility, 0.0, 1.0),
		"freshness": 1.0,
		"description_tags": description_tags.duplicate(),
		"created_day": state.day,
	})
	var location := state.get_location(location_id)
	if not location.is_empty():
		var trace_ids := location.get("traces", []) as Array
		trace_ids.append(trace_id)
		location["traces"] = trace_ids
		state.locations[location_id] = location


func _activate_item(
		state: WorldSimState,
		item_id: String,
		source_fact_id: String
	) -> void:
	var item := state.get_item(item_id)
	if item.is_empty():
		return
	item["active"] = true
	item["source_fact_id"] = source_fact_id
	state.items[item_id] = item


func _add_status_tag(npc: Dictionary, tag: String) -> void:
	var tags := npc.get("status_tags", []) as Array
	if not tag in tags:
		tags.append(tag)
	npc["status_tags"] = tags


func _fact_from_micro_key(
		state: WorldSimState,
		key: String
	) -> WorldSimState.WorldFact:
	var fact_id := String(state.micro_state.get(key, ""))
	if fact_id == "":
		return null
	for fact in state.world_facts:
		if fact.id == fact_id:
			return fact
	return null


func _latest_fact_id(
		state: WorldSimState,
		region_id: String,
		preferred_types: Array[String]
	) -> String:
	for index: int in range(state.world_facts.size() - 1, -1, -1):
		var fact := state.world_facts[index]
		if fact.region_id == region_id and fact.type in preferred_types:
			return fact.id
	return ""


func _trace_id_for_type(state: WorldSimState, type_name: String) -> String:
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		if String(trace.get("type", "")) == type_name:
			return String(trace.get("id", ""))
	return ""


func _narratable_exists(state: WorldSimState, id: String) -> bool:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == id:
			return true
	return false


func _fact_exists(state: WorldSimState, type_name: String) -> bool:
	for fact in state.world_facts:
		if fact.type == type_name:
			return true
	return false
