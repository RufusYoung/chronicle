extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const ClosureModel = preload(
	"res://scripts/sim/lake_town_branch_closure_system.gd"
)
const AuditorModel = preload(
	"res://scripts/dev/lake_town_history_quality_auditor.gd"
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

var failures: Array[String] = []
var simulator := SimulatorModel.new()
var closure := ClosureModel.new()
var auditor := AuditorModel.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var closure_states: Array[WorldSimState] = []

	var guard_state := _profiled_state(2026061501)
	_add_source_fact(
		guard_state,
		"guard_locked_abandoned_granary",
		"abandoned_granary"
	)
	_set_npc_values(guard_state, "chen_mi", {"hunger": 82.0})
	var blocked := closure.apply_branch_closure(
		guard_state,
		"chen_mi_blocked_by_guard_seal"
	)
	_check(
		bool(blocked.get("ok", false))
		and _has_fact(guard_state, "chen_mi_blocked_by_guard_seal"),
		"1. guard lock plus high hunger triggers child blocked"
	)
	_check(
		not _has_fact(guard_state, "chen_mi_took_spoiled_grain"),
		"2. guard lock does not directly generate grain taking"
	)
	guard_state.day += 1
	guard_state.micro_state["guard_pressure"] = 90.0
	var noticed := closure.apply_branch_closure(
		guard_state,
		"guard_noticed_child_near_granary"
	)
	_check(
		bool(noticed.get("ok", false))
		and _has_fact(
			guard_state,
			"guard_noticed_child_near_granary"
		),
		"3. guard notices the child at least one day after blocking"
	)
	closure_states.append(guard_state)

	var empty_state := _profiled_state(2026061514)
	_add_source_fact(
		empty_state,
		"chen_mi_found_empty_granary",
		"abandoned_granary"
	)
	_set_npc_values(empty_state, "chen_mi", {"hunger": 84.0})
	empty_state.day += 1
	var returned := closure.apply_branch_closure(
		empty_state,
		"chen_mi_returned_empty_handed"
	)
	_check(
		bool(returned.get("ok", false))
		and _has_fact(empty_state, "chen_mi_returned_empty_handed"),
		"4. empty granary leads to an empty-handed return"
	)
	_set_npc_values(empty_state, "old_chen", {"stress": 82.0})
	var parent_saw := closure.apply_branch_closure(
		empty_state,
		"old_chen_saw_chen_mi_empty_handed"
	)
	_check(
		bool(parent_saw.get("ok", false))
		and _has_fact(
			empty_state,
			"old_chen_saw_chen_mi_empty_handed"
		),
		"5. Old Chen can see Chen Mi return empty-handed"
	)
	closure_states.append(empty_state)

	var hunger_state := _profiled_state(2026061506)
	_add_source_fact(
		hunger_state,
		"chen_mi_endured_hunger",
		"old_chen_shop"
	)
	_set_npc_values(hunger_state, "chen_mi", {"hunger": 96.0})
	hunger_state.day += 1
	var weakened := closure.apply_branch_closure(
		hunger_state,
		"chen_mi_weakened_from_enduring_hunger"
	)
	_check(
		bool(weakened.get("ok", false))
		and _has_fact(
			hunger_state,
			"chen_mi_weakened_from_enduring_hunger"
		),
		"6. enduring extreme hunger weakens Chen Mi"
	)
	_set_npc_values(hunger_state, "ma_shen", {"concern": 80.0})
	var neighbor := closure.apply_branch_closure(
		hunger_state,
		"neighbor_noticed_silent_hungry_child"
	)
	_check(
		bool(neighbor.get("ok", false))
		and _has_fact(
			hunger_state,
			"neighbor_noticed_silent_hungry_child"
		),
		"7. a concerned neighbor notices the weakened child"
	)
	closure_states.append(hunger_state)

	var debt_state := _profiled_state(2026061508)
	_add_source_fact(
		debt_state,
		"creditor_pressed_before_theft",
		"old_chen_shop"
	)
	_set_npc_values(
		debt_state,
		"old_chen",
		{"debt": 82.0, "help_seeking": 80.0, "pride": 25.0}
	)
	var tried := closure.apply_branch_closure(
		debt_state,
		"old_chen_tried_to_delay_debt"
	)
	_check(
		bool(tried.get("ok", false))
		and _has_fact(debt_state, "old_chen_tried_to_delay_debt"),
		"8. early creditor pressure can lead to a delay request"
	)
	debt_state.day += 1
	_set_npc_values(
		debt_state,
		"liu_zhangfang",
		{"strictness": 90.0, "patience": 20.0}
	)
	var refused := closure.apply_branch_closure(
		debt_state,
		"creditor_refused_delay_request"
	)
	_check(
		bool(refused.get("ok", false))
		and _has_fact(debt_state, "creditor_refused_delay_request"),
		"9. strict creditor conditions can reject the delay request"
	)
	closure_states.append(debt_state)

	var other_family_state := _profiled_state(2026061518)
	_add_source_fact(
		other_family_state,
		"other_family_took_granary_grain",
		"abandoned_granary"
	)
	_set_npc_values(
		other_family_state,
		"chen_mi",
		{"hunger": 80.0}
	)
	var tracks := closure.apply_branch_closure(
		other_family_state,
		"chen_mi_found_other_family_tracks"
	)
	var rumor := closure.apply_branch_closure(
		other_family_state,
		"market_rumor_about_other_hungry_family"
	)
	_check(
		bool(tracks.get("ok", false))
		or bool(rumor.get("ok", false)),
		"10. another family's grain path creates tracks or rumor"
	)
	closure_states.append(other_family_state)

	var forced_state := _profiled_state(2026061503)
	_add_source_fact(
		forced_state,
		"lake_town_food_price_rising",
		"lake_town_market"
	)
	_set_npc_values(
		forced_state,
		"old_chen",
		{"stress": 98.0, "debt": 94.0}
	)
	_set_shop_values(
		forced_state,
		{"is_open": true, "partial_open": false}
	)
	var forced := closure.apply_branch_closure(
		forced_state,
		"old_chen_shop_forced_abnormal_closure"
	)
	_check(
		bool(forced.get("ok", false))
		and not _shop_open(forced_state)
		and _has_fact(
			forced_state,
			"old_chen_shop_forced_abnormal_closure"
		),
		"11. extreme stress and debt force an abnormal closure"
	)
	closure_states.append(forced_state)

	var half_open_state := _profiled_state(2026061515)
	_add_source_fact(
		half_open_state,
		"old_chen_reopened_shop_half_day",
		"old_chen_shop"
	)
	_set_npc_values(half_open_state, "old_chen", {"debt": 95.0})
	_set_shop_values(
		half_open_state,
		{"is_open": true, "partial_open": true}
	)
	var half_open := closure.apply_branch_closure(
		half_open_state,
		"old_chen_shop_half_open_under_debt"
	)
	_check(
		bool(half_open.get("ok", false))
		and _has_fact(
			half_open_state,
			"old_chen_shop_half_open_under_debt"
		),
		"12. a reopened shop can remain half-open under high debt"
	)
	closure_states.append(half_open_state)

	_check(
		_all_closure_facts_have_causes(closure_states),
		"13. every branch-closure WorldFact has cause_fact_ids"
	)
	_check(
		_all_closure_traces_have_sources(closure_states),
		"14. every branch-closure Trace has source_fact_id"
	)
	var fact_count_before := guard_state.world_facts.size()
	var duplicate := closure.apply_branch_closure(
		guard_state,
		"chen_mi_blocked_by_guard_seal"
	)
	_check(
		not bool(duplicate.get("ok", false))
		and guard_state.world_facts.size() == fact_count_before
		and _closure_history_count(
			guard_state,
			"chen_mi_blocked_by_guard_seal"
		) == 1,
		"15. a closure key is not generated again on later days"
	)

	var impossible_state := _profiled_state(2026061591)
	_set_npc_values(
		impossible_state,
		"old_chen",
		{"stress": 100.0, "debt": 100.0}
	)
	_set_shop_values(
		impossible_state,
		{"is_open": true, "partial_open": false}
	)
	_check(
		bool(
			auditor.audit_state(impossible_state).get(
				"impossible_shop_state",
				false
			)
		),
		"16. auditor identifies an impossible extreme open-shop state"
	)

	var dangling_state := _profiled_state(2026061592)
	_add_source_fact(
		dangling_state,
		"guard_locked_abandoned_granary",
		"abandoned_granary"
	)
	_check(
		bool(
			auditor.audit_state(dangling_state).get(
				"dangling_major_fact",
				false
			)
		),
		"17. auditor identifies a major path with no follow-up"
	)

	var runner := RunnerModel.new()
	var batch := runner.run_batch()
	runner.export_markdown_report(batch, OUTPUT_PATH)
	runner.export_history_quality_report(batch, QUALITY_OUTPUT_PATH)
	var quality := batch.get("quality_audit", {}) as Dictionary
	var runs := batch.get("runs", []) as Array
	_check(
		int(quality.get("impossible_shop_state_count", -1)) == 0,
		"18. corrected 20-seed batch has no impossible shop state"
	)
	_check(
		_all_alternative_runs_have_closure(runs),
		"19. every seed with an alternative path has closure depth"
	)
	_check(
		_no_unreasoned_default_classification(runs),
		"20. mixed_or_unclassified is not an unreasoned default"
	)

	var output_text := FileAccess.get_file_as_string(OUTPUT_PATH)
	_check(
		"## 历史质量审计摘要" in output_text
		and FileAccess.file_exists(QUALITY_OUTPUT_PATH),
		"21. multi-seed output contains the quality audit summary"
	)
	_check(
		"## 替代路径闭合样例" in output_text
		and output_text.get_slice(
			"## 替代路径闭合样例",
			1
		).count("### Seed") >= 5,
		"22. multi-seed output contains at least five closure samples"
	)

	print(
		"[LAKE TOWN BRANCH CLOSURE SUMMARY] seeds=%d impossible=%d dangling=%d unresolved_hunger=%d average_depth=%.2f outcomes=%s"
		% [
			int(batch.get("seed_count", 0)),
			int(quality.get("impossible_shop_state_count", 0)),
			int(quality.get("dangling_major_fact_count", 0)),
			int(quality.get("unresolved_extreme_hunger_count", 0)),
			float(quality.get("average_branch_closure_depth", 0.0)),
			JSON.stringify(batch.get("outcome_counts", {})),
		]
	)
	if failures.is_empty():
		print("[LAKE TOWN BRANCH CLOSURE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN BRANCH CLOSURE FAIL] " + failure)
		print(
			"[LAKE TOWN BRANCH CLOSURE RESULT] FAIL: %s"
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
		type_name: String,
		location_id: String
	) -> WorldSimState.WorldFact:
	return state.add_fact(
		type_name,
		"lake_town",
		"",
		{
			"scope": "micro",
			"actors": [],
			"location_id": location_id,
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


func _shop_open(state: WorldSimState) -> bool:
	return bool(
		(
			state.get_location("old_chen_shop").get("state", {})
			as Dictionary
		).get("is_open", false)
	)


func _has_fact(state: WorldSimState, type_name: String) -> bool:
	for fact in state.world_facts:
		if fact.type == type_name:
			return true
	return false


func _all_closure_facts_have_causes(
		states: Array[WorldSimState]
	) -> bool:
	var found := 0
	for state: WorldSimState in states:
		for fact in state.world_facts:
			if String(fact.data.get("branch_closure_key", "")) == "":
				continue
			found += 1
			if fact.cause_fact_ids.is_empty():
				return false
	return found >= 12


func _all_closure_traces_have_sources(
		states: Array[WorldSimState]
	) -> bool:
	var found := 0
	for state: WorldSimState in states:
		var closure_fact_ids: Dictionary = {}
		for fact in state.world_facts:
			if String(fact.data.get("branch_closure_key", "")) != "":
				closure_fact_ids[fact.id] = true
		for trace_value: Variant in state.traces:
			var trace := trace_value as Dictionary
			var source_id := String(trace.get("source_fact_id", ""))
			if not closure_fact_ids.has(source_id):
				continue
			found += 1
			if source_id == "":
				return false
	return found >= 12


func _all_alternative_runs_have_closure(runs: Array) -> bool:
	var found := 0
	for run_value: Variant in runs:
		var signature := (
			(run_value as Dictionary).get("signature", {})
			as Dictionary
		)
		var fact_days := signature.get("fact_days", {}) as Dictionary
		var alternative := false
		for type_name: String in RunnerModel.ALTERNATIVE_PATH_TYPES:
			if int(fact_days.get(type_name, -1)) >= 0:
				alternative = true
				break
		if not alternative:
			continue
		found += 1
		if int(signature.get("branch_closure_depth", 0)) < 1:
			return false
	return found >= 3


func _no_unreasoned_default_classification(runs: Array) -> bool:
	for run_value: Variant in runs:
		var signature := (
			(run_value as Dictionary).get("signature", {})
			as Dictionary
		)
		var outcome := String(signature.get("outcome_class", ""))
		var reason := String(
			signature.get("outcome_reason", "")
		).strip_edges()
		if outcome == "mixed_or_unclassified":
			return false
		if outcome == "mixed_interwoven" and reason == "":
			return false
	return true


func _closure_history_count(
		state: WorldSimState,
		closure_key: String
	) -> int:
	var count := 0
	var closure_state := state.micro_state.get(
		"branch_closure_state",
		{}
	) as Dictionary
	for entry_value: Variant in closure_state.get("closure_history", []):
		var entry := entry_value as Dictionary
		if String(entry.get("closure_key", "")) == closure_key:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN BRANCH CLOSURE PASS] " + message)
	else:
		failures.append(message)
