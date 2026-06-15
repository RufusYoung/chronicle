extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const HungerClosureModel = preload(
	"res://scripts/sim/lake_town_hunger_closure_system.gd"
)
const RunnerModel = preload(
	"res://scripts/dev/lake_town_history_variation_runner.gd"
)

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_lake_town_history_variation_output.md"
)
const QUALITY_OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_lake_town_history_quality_output.md"
)
const PRIOR_UNRESOLVED_SEEDS: Array[int] = [
	2026061503,
	2026061507,
	2026061509,
]

var failures: Array[String] = []
var simulator := SimulatorModel.new()
var hunger_closure := HungerClosureModel.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var closure_states: Array[WorldSimState] = []

	var low_hunger := _profiled_state(2026061501)
	_set_npc_values(
		low_hunger,
		"chen_mi",
		{"hunger": 80.0, "health": 88.0}
	)
	_check(
		hunger_closure.build_hunger_closure_candidates(
			low_hunger
		).is_empty(),
		"1. non-extreme hunger does not trigger hunger closure"
	)

	var collapse_state := _profiled_state(2026061503)
	_add_source_fact(collapse_state, "lake_town_food_price_rising")
	_set_npc_values(
		collapse_state,
		"chen_mi",
		{"hunger": 99.0, "health": 84.0}
	)
	var collapsed := hunger_closure.apply_hunger_closure(
		collapse_state,
		"chen_mi_collapsed_from_hunger"
	)
	_check(
		bool(collapsed.get("ok", false))
		and _has_fact(
			collapse_state,
			"chen_mi_collapsed_from_hunger"
		),
		"2. extreme hunger and weak health trigger collapse"
	)
	_check(
		_has_trace(collapse_state, "child_collapsed_at_shop_step")
		and _has_memory(
			collapse_state,
			"chen_mi_remembers_collapse_blur"
		),
		"3. collapse creates WorldFact, Trace, and Memory"
	)
	closure_states.append(collapse_state)

	collapse_state.day += 1
	_set_npc_values(
		collapse_state,
		"ma_shen",
		{"concern": 85.0, "food_spare": 2.0}
	)
	var hunger_before_food := float(
		collapse_state.get_npc("chen_mi").get("hunger", 0.0)
	)
	var emergency_food := hunger_closure.apply_hunger_closure(
		collapse_state,
		"ma_shen_emergency_food_for_chen_mi"
	)
	_check(
		bool(emergency_food.get("ok", false))
		and _has_fact(
			collapse_state,
			"ma_shen_emergency_food_for_chen_mi"
		),
		"4. Ma Shen concern and food spare trigger emergency food"
	)
	_check(
		float(
			collapse_state.get_npc("chen_mi").get("hunger", 0.0)
		) < hunger_before_food,
		"5. emergency food lowers Chen Mi hunger"
	)

	var sold_state := _profiled_state(2026061504)
	_add_source_fact(sold_state, "lake_town_food_price_rising")
	_set_npc_values(
		sold_state,
		"old_chen",
		{"stress": 96.0, "family_food": 0.0}
	)
	_set_npc_values(sold_state, "chen_mi", {"hunger": 94.0})
	_set_shop_values(sold_state, {"food_stock": 0.0})
	var family_food_before := float(
		sold_state.get_npc("old_chen").get("family_food", 0.0)
	)
	var sold := hunger_closure.apply_hunger_closure(
		sold_state,
		"old_chen_sold_shop_goods_for_food"
	)
	_check(
		bool(sold.get("ok", false))
		and float(
			sold_state.get_npc("old_chen").get("family_food", 0.0)
		) > family_food_before
		and _has_trace(sold_state, "missing_shop_goods"),
		"6. selling shop goods raises family food and leaves a trace"
	)
	closure_states.append(sold_state)

	var seek_state := _profiled_state(2026061507)
	_add_source_fact(seek_state, "lake_town_food_price_rising")
	_set_npc_values(
		seek_state,
		"chen_mi",
		{"hunger": 99.0, "health": 84.0}
	)
	hunger_closure.apply_hunger_closure(
		seek_state,
		"chen_mi_collapsed_from_hunger"
	)
	seek_state.day += 1
	_set_npc_values(seek_state, "old_chen", {"stress": 95.0})
	_set_shop_values(seek_state, {"is_open": false})
	var sought_help := hunger_closure.apply_hunger_closure(
		seek_state,
		"old_chen_took_chen_mi_to_seek_help"
	)
	_check(
		bool(sought_help.get("ok", false))
		and (
			String(
				seek_state.get_npc("chen_mi").get("location_id", "")
			) == "lake_town_market"
			or String(
				seek_state.get_npc("old_chen").get("location_id", "")
			) == "lake_town_market"
		),
		"7. seeking help changes Chen Mi or Old Chen location"
	)

	seek_state.day += 1
	_set_market_values(
		seek_state,
		{"credit_available": 85.0, "neighbor_help_level": 70.0}
	)
	_set_npc_values(
		seek_state,
		"old_chen",
		{"family_food": 0.0, "debt": 60.0}
	)
	_set_npc_values(seek_state, "chen_mi", {"hunger": 95.0})
	var debt_before := float(
		seek_state.get_npc("old_chen").get("debt", 0.0)
	)
	var credit_before := float(
		_market_value(seek_state, "credit_available")
	)
	var emergency_credit := hunger_closure.apply_hunger_closure(
		seek_state,
		"lake_town_emergency_credit_food"
	)
	_check(
		bool(emergency_credit.get("ok", false))
		and float(
			seek_state.get_npc("old_chen").get("family_food", 0.0)
		) > 0.0
		and (
			float(
				seek_state.get_npc("old_chen").get("debt", 0.0)
			) > debt_before
			or _market_value(
				seek_state,
				"credit_available"
			) < credit_before
		),
		"8. emergency credit changes food and debt or market credit"
	)
	closure_states.append(seek_state)

	var no_crash := _profiled_state(2026061510)
	_set_npc_values(
		no_crash,
		"chen_mi",
		{"hunger": 97.0, "health": 70.0}
	)
	var rejected_crash := hunger_closure.apply_hunger_closure(
		no_crash,
		"chen_mi_health_crashed_from_hunger"
	)
	var crash_state := _profiled_state(2026061511)
	_add_source_fact(crash_state, "chen_mi_endured_hunger")
	_set_npc_values(
		crash_state,
		"chen_mi",
		{"hunger": 97.0, "health": 70.0}
	)
	_set_hunger_state(
		crash_state,
		{"extreme_hunger_days": 2, "last_extreme_hunger_day": 4}
	)
	var crashed := hunger_closure.apply_hunger_closure(
		crash_state,
		"chen_mi_health_crashed_from_hunger"
	)
	_check(
		not bool(rejected_crash.get("ok", false))
		and bool(crashed.get("ok", false)),
		"9. health crash requires sustained extreme hunger or decline"
	)
	closure_states.append(crash_state)

	collapse_state.day += 1
	_set_shop_values(collapse_state, {"is_open": false})
	_set_npc_values(collapse_state, "old_chen", {"stress": 98.0})
	var stayed := hunger_closure.apply_hunger_closure(
		collapse_state,
		"chen_mi_temporarily_stayed_with_ma_shen"
	)
	_check(
		bool(stayed.get("ok", false))
		and String(
			collapse_state.get_npc("chen_mi").get("location_id", "")
		) == "ma_shen_home_temp",
		"10. temporary Ma Shen stay requires rescue and care"
	)

	var fallback_state := _profiled_state(2026061512)
	_add_source_fact(fallback_state, "lake_town_food_price_rising")
	_set_npc_values(
		fallback_state,
		"chen_mi",
		{
			"hunger": 97.0,
			"health": 90.0,
			"location_id": "lake_town_market",
		}
	)
	_set_npc_values(
		fallback_state,
		"old_chen",
		{"stress": 20.0, "family_food": 5.0}
	)
	_set_shop_values(
		fallback_state,
		{"is_open": true, "food_stock": 10.0}
	)
	_set_hunger_state(
		fallback_state,
		{"extreme_hunger_days": 2, "last_extreme_hunger_day": 4}
	)
	var fallback := hunger_closure.apply_hunger_closure(
		fallback_state,
		"chen_mi_hunger_unresolved_but_recorded"
	)
	_check(
		bool(fallback.get("ok", false))
		and _only_hunger_closure_is(
			fallback_state,
			"chen_mi_hunger_unresolved_but_recorded"
		),
		"11. unresolved record is used only when other closures cannot fire"
	)
	closure_states.append(fallback_state)

	_check(
		_all_hunger_facts_have_causes(closure_states),
		"12. every hunger-closure WorldFact has cause_fact_ids"
	)
	_check(
		_all_hunger_traces_have_sources(closure_states),
		"13. every hunger-closure Trace has source_fact_id"
	)
	var collapse_fact_count := _fact_count(
		collapse_state,
		"chen_mi_collapsed_from_hunger"
	)
	collapse_state.day += 1
	var duplicate := hunger_closure.apply_hunger_closure(
		collapse_state,
		"chen_mi_collapsed_from_hunger"
	)
	_check(
		not bool(duplicate.get("ok", false))
		and _fact_count(
			collapse_state,
			"chen_mi_collapsed_from_hunger"
		) == collapse_fact_count,
		"14. the same hunger closure is not generated every day"
	)

	var runner := RunnerModel.new()
	var batch := runner.run_batch()
	runner.export_markdown_report(batch, OUTPUT_PATH)
	runner.export_history_quality_report(batch, QUALITY_OUTPUT_PATH)
	var quality := batch.get("quality_audit", {}) as Dictionary
	var runs := batch.get("runs", []) as Array
	_check(
		int(quality.get("unresolved_extreme_hunger_count", -1)) == 0,
		"15. 20-seed batch has zero unresolved extreme hunger"
	)
	var quality_text := FileAccess.get_file_as_string(
		QUALITY_OUTPUT_PATH
	)
	_check(
		"## 极端饥饿闭合摘要" in quality_text,
		"16. quality output contains the hunger closure summary"
	)
	var variation_text := FileAccess.get_file_as_string(OUTPUT_PATH)
	_check(
		"## 极端饥饿闭合样例" in variation_text,
		"17. variation output contains hunger closure samples"
	)
	_check(
		_prior_unresolved_seeds_have_hunger_closure(runs),
		"18. prior unresolved seeds now have hunger closure facts"
	)
	var same_left := runner.run_seed(2026061503, 30)
	var same_right := runner.run_seed(2026061503, 30)
	_check(
		same_left.get("signature", {}) == same_right.get("signature", {})
		and same_left.get("signature_hash", "")
		== same_right.get("signature_hash", ""),
		"19. same-seed reproducibility still passes"
	)
	_check(
		int(batch.get("unique_signature_count", 0)) >= 8
		and int(batch.get("outcome_class_count", 0)) >= 5,
		"20. different seeds still produce diverse histories"
	)

	print(
		"[LAKE TOWN HUNGER CLOSURE SUMMARY] seeds=%d unresolved=%d bad=%d emergency_food=%d relocation=%d health_crash=%d recorded=%d"
		% [
			int(batch.get("seed_count", 0)),
			int(
				quality.get("unresolved_extreme_hunger_count", 0)
			),
			int(quality.get("bad_hunger_outcome_count", 0)),
			int(quality.get("emergency_food_count", 0)),
			int(quality.get("temporary_relocation_count", 0)),
			int(quality.get("health_crash_count", 0)),
			int(
				quality.get(
					"hunger_unresolved_but_recorded_count",
					0
				)
			),
		]
	)
	if failures.is_empty():
		print("[LAKE TOWN HUNGER CLOSURE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN HUNGER CLOSURE FAIL] " + failure)
		print(
			"[LAKE TOWN HUNGER CLOSURE RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _profiled_state(seed_value: int) -> WorldSimState:
	var state := simulator.load_seed_with_lake_town_profile(
		SEED_PATH,
		seed_value
	)
	state.day = 5
	return state


func _add_source_fact(
		state: WorldSimState,
		type_name: String
	) -> WorldSimState.WorldFact:
	return state.add_fact(
		type_name,
		"lake_town",
		"",
		{
			"scope": "micro",
			"actors": [],
			"location_id": "old_chen_shop",
			"cause_fact_ids": ["test_root_fact"],
			"effects": {},
			"tags": ["test_setup"],
		}
	)


func _set_npc_values(
		state: WorldSimState,
		npc_id: String,
		values: Dictionary
	) -> void:
	var npc := state.get_npc(npc_id)
	for key: Variant in values:
		npc[key] = values[key]
	state.npcs[npc_id] = npc


func _set_shop_values(
		state: WorldSimState,
		values: Dictionary
	) -> void:
	var shop := state.get_location("old_chen_shop")
	var shop_state := shop.get("state", {}) as Dictionary
	for key: Variant in values:
		shop_state[key] = values[key]
	shop["state"] = shop_state
	state.locations["old_chen_shop"] = shop


func _set_market_values(
		state: WorldSimState,
		values: Dictionary
	) -> void:
	var market := state.get_location("lake_town_market")
	var market_state := market.get("state", {}) as Dictionary
	for key: Variant in values:
		market_state[key] = values[key]
	market["state"] = market_state
	state.locations["lake_town_market"] = market


func _set_hunger_state(
		state: WorldSimState,
		values: Dictionary
	) -> void:
	var hunger_state := state.micro_state.get(
		"hunger_closure_state",
		{}
	) as Dictionary
	for key: Variant in values:
		hunger_state[key] = values[key]
	state.micro_state["hunger_closure_state"] = hunger_state


func _market_value(state: WorldSimState, key: String) -> float:
	return float(
		(
			state.get_location("lake_town_market").get("state", {})
			as Dictionary
		).get(key, 0.0)
	)


func _has_fact(state: WorldSimState, type_name: String) -> bool:
	return _fact_count(state, type_name) > 0


func _fact_count(state: WorldSimState, type_name: String) -> int:
	var count := 0
	for fact in state.world_facts:
		if fact.type == type_name:
			count += 1
	return count


func _has_trace(state: WorldSimState, type_name: String) -> bool:
	for trace_value: Variant in state.traces:
		if String((trace_value as Dictionary).get("type", "")) == type_name:
			return true
	return false


func _has_memory(state: WorldSimState, type_name: String) -> bool:
	for memory_value: Variant in state.memories:
		if String((memory_value as Dictionary).get("type", "")) == type_name:
			return true
	return false


func _only_hunger_closure_is(
		state: WorldSimState,
		type_name: String
	) -> bool:
	var found: Array[String] = []
	for fact in state.world_facts:
		if String(fact.data.get("hunger_closure_key", "")) != "":
			found.append(fact.type)
	return found == [type_name]


func _all_hunger_facts_have_causes(
		states: Array[WorldSimState]
	) -> bool:
	var found := 0
	for state: WorldSimState in states:
		for fact in state.world_facts:
			if String(fact.data.get("hunger_closure_key", "")) == "":
				continue
			found += 1
			if fact.cause_fact_ids.is_empty():
				return false
	return found >= 8


func _all_hunger_traces_have_sources(
		states: Array[WorldSimState]
	) -> bool:
	var found := 0
	for state: WorldSimState in states:
		var hunger_fact_ids: Dictionary = {}
		for fact in state.world_facts:
			if String(fact.data.get("hunger_closure_key", "")) != "":
				hunger_fact_ids[fact.id] = true
		for trace_value: Variant in state.traces:
			var trace := trace_value as Dictionary
			var source_id := String(trace.get("source_fact_id", ""))
			if not hunger_fact_ids.has(source_id):
				continue
			found += 1
			if source_id == "":
				return false
	return found >= 8


func _prior_unresolved_seeds_have_hunger_closure(runs: Array) -> bool:
	for seed_value: int in PRIOR_UNRESOLVED_SEEDS:
		var found := false
		for run_value: Variant in runs:
			var run := run_value as Dictionary
			if int(run.get("seed", 0)) != seed_value:
				continue
			var signature := run.get("signature", {}) as Dictionary
			var fact_days := signature.get("fact_days", {}) as Dictionary
			for type_name: String in RunnerModel.HUNGER_CLOSURE_FACT_TYPES:
				if int(fact_days.get(type_name, -1)) >= 0:
					found = true
					break
			break
		if not found:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN HUNGER CLOSURE PASS] " + message)
	else:
		failures.append(message)
