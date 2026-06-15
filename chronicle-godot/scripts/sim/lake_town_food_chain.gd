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
	var grain_fact := _resolve_chen_mi_food_search(state, price_fact)
	var closed_fact := _maybe_close_shop(state, price_fact, grain_fact)
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


func _maybe_close_shop(
		state: WorldSimState,
		price_fact: WorldSimState.WorldFact,
		grain_fact: WorldSimState.WorldFact
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
