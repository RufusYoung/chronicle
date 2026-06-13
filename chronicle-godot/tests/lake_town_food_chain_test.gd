extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const ChainModel = preload("res://scripts/sim/lake_town_food_chain.gd")
const SEED_PATH := "res://data/world_seed_mirror_lake.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator := SimulatorModel.new()
	var chain := ChainModel.new()
	var initial := simulator.load_seed(SEED_PATH)
	var ample := simulator.load_seed(SEED_PATH)
	var baseline := simulator.load_seed(SEED_PATH)
	var repeat := simulator.load_seed(SEED_PATH)
	if initial == null or ample == null or baseline == null or repeat == null:
		push_error("[LAKE TOWN FOOD CHAIN RESULT] FAIL: seed loading failed")
		quit(1)
		return

	_check(initial.npcs.has("old_chen"), "old_chen exists after initialization")
	_check(initial.npcs.has("chen_mi"), "chen_mi exists after initialization")
	_check(initial.locations.has("old_chen_shop"), "old_chen_shop exists after initialization")
	_check(initial.locations.has("abandoned_granary"), "abandoned_granary exists after initialization")
	_check(initial.items.has("spoiled_grain"), "spoiled_grain resource exists after initialization")

	var ample_region := ample.get_region("border_town")
	ample_region.scarcity = 20.0
	ample_region.food = 90.0
	for _index: int in range(5):
		ample.day += 1
		chain.advance_one_day(ample)
	_check(
		_find_fact(ample, "chen_mi_took_spoiled_grain") == null,
		"sufficient food conditions do not create a spoiled grain fact"
	)
	_check(
		_find_scene(ample, "chen_mi_hiding_spoiled_grain_scene").is_empty(),
		"insufficient preconditions do not create the micro scene"
	)

	var initial_food := float(initial.get_npc("old_chen").get("family_food", 0.0))
	var initial_stress := float(initial.get_npc("old_chen").get("stress", 0.0))
	simulator.advance_one_day(initial)
	_check(
		_find_fact(initial, "lake_town_food_price_rising") != null,
		"food pressure creates the lake town price rise fact"
	)
	_check(
		float(initial.get_npc("old_chen").get("family_food", 0.0)) < initial_food,
		"old_chen family food falls under macro food pressure"
	)
	_check(
		float(initial.get_npc("old_chen").get("stress", 0.0)) > initial_stress,
		"old_chen stress rises under macro food pressure"
	)

	var hunger_before := float(initial.get_npc("chen_mi").get("hunger", 0.0))
	simulator.advance_one_day(initial)
	_check(
		float(initial.get_npc("chen_mi").get("hunger", 0.0)) > hunger_before,
		"chen_mi hunger rises as family food becomes insufficient"
	)

	_check_missing_precondition(
		simulator,
		chain,
		"hunger",
		"low hunger prevents taking spoiled grain"
	)
	_check_missing_precondition(
		simulator,
		chain,
		"family_food",
		"usable family food prevents taking spoiled grain"
	)
	_check_missing_precondition(
		simulator,
		chain,
		"money",
		"enough parent money prevents taking spoiled grain"
	)
	_check_missing_precondition(
		simulator,
		chain,
		"granary_stock",
		"empty granary prevents taking spoiled grain"
	)

	var triggered: WorldSimState = simulator.load_seed(SEED_PATH)
	_prepare_trigger_state(triggered)
	triggered.day = 1
	var stock_before := _granary_stock(triggered)
	chain.advance_one_day(triggered)
	var grain_fact := _find_fact(triggered, "chen_mi_took_spoiled_grain")
	var close_fact := _find_fact(
		triggered,
		"old_chen_closed_shop_due_to_family_crisis"
	)
	var scene := _find_scene(
		triggered,
		"chen_mi_hiding_spoiled_grain_scene"
	)
	_check(grain_fact != null, "all food search thresholds create the spoiled grain fact")
	_check(
		_granary_stock(triggered) == stock_before - 1.0,
		"taking spoiled grain reduces granary stock by one"
	)
	_check(
		"spoiled_grain" in (
			triggered.get_npc("chen_mi").get("inventory", []) as Array
		),
		"chen_mi inventory contains spoiled_grain"
	)
	_check(
		_has_trace_types(
			triggered,
			[
				"child_hiding_bag",
				"spoiled_grain_bag",
				"grain_dust_on_sleeve",
				"granary_missing_grain",
			]
		),
		"taking grain creates all required visible traces"
	)
	_check(close_fact != null, "family crisis and high stress close old_chen_shop")
	_check(
		_has_trace_types(triggered, ["closed_shop"]),
		"closing the shop creates the closed_shop trace"
	)
	_check(not scene.is_empty(), "the traceable micro scene is generated")
	_check(
		not (scene.get("source_fact_ids", []) as Array).is_empty(),
		"the micro scene references source_fact_ids"
	)
	_check(
		not (scene.get("trace_ids", []) as Array).is_empty(),
		"the micro scene references trace_ids"
	)

	simulator.advance_days(baseline, 30)
	simulator.advance_days(repeat, 30)
	_check(
		_micro_signature(baseline) == _micro_signature(repeat),
		"the same seed reproduces the lake town food chain"
	)

	var baseline_scene := _find_scene(
		baseline,
		"chen_mi_hiding_spoiled_grain_scene"
	)
	print(
		"[LAKE TOWN SUMMARY] facts=%s traces=%s scene_day=%d"
		% [
			", ".join(_micro_fact_types(baseline)),
			", ".join(_trace_types(baseline)),
			int(baseline_scene.get("created_day", 0)),
		]
	)
	if not baseline_scene.is_empty():
		print(
			"[LAKE TOWN SCENE] %s | sources=%s | traces=%s"
			% [
				baseline_scene.get("title", ""),
				", ".join(baseline_scene.get("source_fact_ids", [])),
				", ".join(baseline_scene.get("trace_ids", [])),
			]
		)

	if failures.is_empty():
		print("[LAKE TOWN FOOD CHAIN RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN FOOD CHAIN FAIL] " + failure)
		print("[LAKE TOWN FOOD CHAIN RESULT] FAIL: %s" % failures)
		quit(1)


func _check_missing_precondition(
		simulator,
		chain,
		missing: String,
		message: String
	) -> void:
	var state: WorldSimState = simulator.load_seed(SEED_PATH)
	_prepare_trigger_state(state)
	match missing:
		"hunger":
			state.get_npc("chen_mi")["hunger"] = 30.0
		"family_food":
			state.get_npc("old_chen")["family_food"] = 30.0
		"money":
			state.get_npc("old_chen")["money"] = 20.0
		"granary_stock":
			var granary: Dictionary = state.get_location("abandoned_granary")
			var granary_state := granary.get("state", {}) as Dictionary
			granary_state["spoiled_grain_stock"] = 0.0
			granary["state"] = granary_state
	state.day = 1
	chain.advance_one_day(state)
	_check(_find_fact(state, "chen_mi_took_spoiled_grain") == null, message)
	_check(
		_find_scene(state, "chen_mi_hiding_spoiled_grain_scene").is_empty(),
		"%s and does not create the scene" % message
	)


func _prepare_trigger_state(state: WorldSimState) -> void:
	var region := state.get_region("border_town")
	region.scarcity = 90.0
	region.food = 20.0
	var old_chen := state.get_npc("old_chen")
	old_chen["family_food"] = 0.0
	old_chen["money"] = 0.0
	old_chen["stress"] = 72.0
	var chen_mi := state.get_npc("chen_mi")
	chen_mi["hunger"] = 80.0
	var granary := state.get_location("abandoned_granary")
	var granary_state := granary.get("state", {}) as Dictionary
	granary_state["spoiled_grain_stock"] = 3.0
	granary_state["is_known_to_children"] = true
	granary["state"] = granary_state


func _find_fact(
		state: WorldSimState,
		type_name: String
	) -> WorldSimState.WorldFact:
	for fact in state.world_facts:
		if fact.type == type_name:
			return fact
	return null


func _find_scene(state: WorldSimState, scene_id: String) -> Dictionary:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == scene_id:
			return scene
	return {}


func _granary_stock(state: WorldSimState) -> float:
	var granary := state.get_location("abandoned_granary")
	var granary_state := granary.get("state", {}) as Dictionary
	return float(granary_state.get("spoiled_grain_stock", 0.0))


func _has_trace_types(state: WorldSimState, required: Array[String]) -> bool:
	var types := _trace_types(state)
	for type_name: String in required:
		if not type_name in types:
			return false
	return true


func _trace_types(state: WorldSimState) -> Array[String]:
	var output: Array[String] = []
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		output.append(String(trace.get("type", "")))
	return output


func _micro_fact_types(state: WorldSimState) -> Array[String]:
	var output: Array[String] = []
	for fact in state.world_facts:
		if String(fact.data.get("scope", "")) == "micro":
			output.append(fact.type)
	return output


func _micro_signature(state: WorldSimState) -> String:
	return JSON.stringify({
		"micro_state": state.micro_state,
		"npcs": state.npcs,
		"locations": state.locations,
		"items": state.items,
		"facts": _micro_fact_types(state),
		"traces": state.traces,
		"narratable_states": state.narratable_states,
	})


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN FOOD CHAIN PASS] " + message)
	else:
		failures.append(message)
