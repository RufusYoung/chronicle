extends RefCounted
class_name LakeTownSeedProfile


func build_profile(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"seed": seed_value,
		"macro_pressure": {
			"initial_scarcity_bias": _float_range(rng, -14.0, 18.0),
			"initial_food_bias": _float_range(rng, -18.0, 14.0),
			"guard_pressure_bias": _float_range(rng, 10.0, 95.0),
			"market_disruption_bias": _float_range(rng, 10.0, 90.0),
		},
		"old_chen": {
			"initial_debt": _float_range(rng, 24.0, 82.0),
			"initial_money": _float_range(rng, 0.0, 18.0),
			"family_food": _float_range(rng, 7.0, 38.0),
			"pride": _float_range(rng, 12.0, 92.0),
			"help_seeking": _float_range(rng, 10.0, 92.0),
			"risk_tolerance": _float_range(rng, 10.0, 90.0),
		},
		"chen_mi": {
			"initial_hunger": _float_range(rng, 28.0, 70.0),
			"fearfulness": _float_range(rng, 12.0, 92.0),
			"boldness": _float_range(rng, 8.0, 92.0),
			"trust_in_adults": _float_range(rng, 18.0, 92.0),
			"sickness_resistance": _float_range(rng, 15.0, 95.0),
		},
		"ma_shen": {
			"food_spare": _int_range(rng, 0, 4),
			"concern": _float_range(rng, 22.0, 92.0),
			"risk_aversion": _float_range(rng, 10.0, 90.0),
			"trust_to_old_chen": _float_range(rng, 32.0, 92.0),
		},
		"liu_zhangfang": {
			"patience": _float_range(rng, 12.0, 92.0),
			"debt_claim": _float_range(rng, 24.0, 88.0),
			"strictness": _float_range(rng, 18.0, 96.0),
		},
		"abandoned_granary": {
			"spoiled_grain_stock": _int_range(rng, 0, 4),
			"disease_risk": _float_range(rng, 0.3, 0.95),
			"visibility": _float_range(rng, 12.0, 96.0),
			"guard_watch": _float_range(rng, 8.0, 96.0),
		},
		"lake_town_market": {
			"credit_available": _float_range(rng, 8.0, 96.0),
			"neighbor_help_level": _float_range(rng, 12.0, 92.0),
			"rumor_speed": _float_range(rng, 12.0, 92.0),
			"other_family_pressure": _float_range(rng, 8.0, 96.0),
		},
	}


func apply_profile_to_state(state: Variant, profile: Dictionary) -> void:
	if not state is WorldSimState or profile.is_empty():
		return
	state.seed = int(profile.get("seed", state.seed))
	var rng := RandomNumberGenerator.new()
	rng.seed = state.seed
	state.rng_state = rng.state

	var macro := profile.get("macro_pressure", {}) as Dictionary
	var town: WorldSimState.RegionState = state.get_region("border_town")
	if town != null:
		town.scarcity = clampf(
			town.scarcity
			+ float(macro.get("initial_scarcity_bias", 0.0)),
			0.0,
			100.0
		)
		town.food = clampf(
			town.food + float(macro.get("initial_food_bias", 0.0)),
			0.0,
			100.0
		)

	_apply_npc_profile(state, "old_chen", profile.get("old_chen", {}))
	_apply_npc_profile(state, "chen_mi", profile.get("chen_mi", {}))
	_apply_npc_profile(state, "ma_shen", profile.get("ma_shen", {}))
	_apply_npc_profile(
		state,
		"liu_zhangfang",
		profile.get("liu_zhangfang", {})
	)

	var old_chen: Dictionary = state.get_npc("old_chen")
	var old_profile := profile.get("old_chen", {}) as Dictionary
	old_chen["debt"] = float(old_profile.get("initial_debt", 38.0))
	old_chen["money"] = float(old_profile.get("initial_money", 9.0))
	old_chen["family_food"] = float(old_profile.get("family_food", 24.0))
	state.npcs["old_chen"] = old_chen

	var chen_mi: Dictionary = state.get_npc("chen_mi")
	var chen_profile := profile.get("chen_mi", {}) as Dictionary
	chen_mi["hunger"] = float(
		chen_profile.get("initial_hunger", 44.0)
	)
	state.npcs["chen_mi"] = chen_mi

	var granary_profile := profile.get(
		"abandoned_granary",
		{}
	) as Dictionary
	var granary: Dictionary = state.get_location("abandoned_granary")
	var granary_state := granary.get("state", {}) as Dictionary
	for key: String in [
		"spoiled_grain_stock",
		"disease_risk",
		"visibility",
		"guard_watch",
	]:
		granary_state[key] = granary_profile.get(
			key,
			granary_state.get(key, 0.0)
		)
	granary_state["locked_by_guard"] = false
	granary["state"] = granary_state
	state.locations["abandoned_granary"] = granary

	var spoiled_grain: Dictionary = state.get_item("spoiled_grain")
	if not spoiled_grain.is_empty():
		spoiled_grain["amount"] = float(
			granary_state.get("spoiled_grain_stock", 0.0)
		)
		state.items["spoiled_grain"] = spoiled_grain

	var market_profile := profile.get(
		"lake_town_market",
		{}
	) as Dictionary
	var market: Dictionary = state.get_location("lake_town_market")
	var market_state := market.get("state", {}) as Dictionary
	for key: String in [
		"credit_available",
		"neighbor_help_level",
		"rumor_speed",
		"other_family_pressure",
	]:
		market_state[key] = market_profile.get(key, 0.0)
	market["state"] = market_state
	state.locations["lake_town_market"] = market

	var shop: Dictionary = state.get_location("old_chen_shop")
	var shop_state := shop.get("state", {}) as Dictionary
	shop_state["food_stock"] = maxf(
		0.0,
		float(shop_state.get("food_stock", 0.0))
		- float(macro.get("market_disruption_bias", 0.0)) * 0.08
	)
	shop["state"] = shop_state
	state.locations["old_chen_shop"] = shop

	state.micro_state["guard_pressure"] = float(
		macro.get("guard_pressure_bias", 0.0)
	)
	state.micro_state["market_disruption"] = float(
		macro.get("market_disruption_bias", 0.0)
	)
	state.micro_state["rumor_pressure"] = float(
		market_profile.get("rumor_speed", 0.0)
	) * 0.12
	state.micro_state["seed_profile"] = profile.duplicate(true)
	state.micro_state["seed_profile_summary"] = describe_profile(profile)
	state.micro_state["history_variation"] = {
		"path_history": [],
		"last_update_day": 0,
	}


func describe_profile(profile: Dictionary) -> Dictionary:
	var summary := profile.duplicate(true)
	_round_dictionary(summary)
	return summary


func _apply_npc_profile(
		state: WorldSimState,
		npc_id: String,
		values_value: Variant
	) -> void:
	var npc := state.get_npc(npc_id)
	if npc.is_empty() or not values_value is Dictionary:
		return
	var values := values_value as Dictionary
	for key: Variant in values:
		if String(key) in [
			"initial_debt",
			"initial_money",
			"family_food",
			"initial_hunger",
		]:
			continue
		npc[key] = values[key]
	state.npcs[npc_id] = npc


func _round_dictionary(data: Dictionary) -> void:
	for key: Variant in data.keys():
		var value: Variant = data[key]
		if value is Dictionary:
			_round_dictionary(value as Dictionary)
		elif value is float:
			data[key] = snappedf(float(value), 0.01)


func _float_range(
		rng: RandomNumberGenerator,
		minimum: float,
		maximum: float
	) -> float:
	return snappedf(rng.randf_range(minimum, maximum), 0.01)


func _int_range(
		rng: RandomNumberGenerator,
		minimum: int,
		maximum: int
	) -> int:
	return rng.randi_range(minimum, maximum)
