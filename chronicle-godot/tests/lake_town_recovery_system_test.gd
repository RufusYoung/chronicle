extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const ResolverModel = preload("res://scripts/sim/micro_action_resolver.gd")
const RecoveryModel = preload("res://scripts/sim/lake_town_recovery_system.gd")
const ObserverModel = preload("res://scripts/dev/world_sim_observer.gd")

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const SCENE_ID := "chen_mi_hiding_spoiled_grain_scene"
const OUTPUT_PATH := "user://tests/lake_town_recovery_system_output.md"
const RELATIONSHIP_FIELDS: Array[String] = [
	"trust",
	"fear",
	"gratitude",
	"resentment",
	"debt",
	"familiarity",
	"last_interaction_day",
	"tags",
]

var failures: Array[String] = []
var simulator := SimulatorModel.new()
var resolver := ResolverModel.new()
var recovery := RecoveryModel.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var empty_state: WorldSimState = simulator.load_seed(SEED_PATH)
	_check(
		recovery.build_recovery_candidates(empty_state).is_empty()
		and recovery.build_relationship_echoes(empty_state).is_empty(),
		"1. no source fact or memory means no recovery or echo"
	)

	var give := _run_branch("give_food_to_chen_mi")
	var give_state := give["state"] as WorldSimState
	var give_actor := give["actor"] as Dictionary
	var give_relation := recovery.get_micro_relationship(
		give_state,
		"chen_mi",
		"test_actor"
	)
	_check(
		_has_fact(give_state, "chen_mi_stabilized_after_food_help"),
		"2. give-food branch stabilizes Chen Mi within five days"
	)
	_check(
		not _has_fact(give_state, "chen_mi_ate_spoiled_grain"),
		"3. give-food branch prevents immediate spoiled-grain eating"
	)
	_check(
		float(give_relation.get("trust", 0.0)) > 0.0
		and float(give_relation.get("gratitude", 0.0)) > 0.0
		and _has_relationship_fields(give_relation),
		"4. give-food raises a complete structured relationship"
	)
	_check(
		_has_memory(give_state, "chen_mi_remembers_food_help_after_crisis")
		and _has_memory(give_state, "chen_mi_recalls_actor_kindness"),
		"5. give-food branch creates positive memories"
	)

	var no_soften: WorldSimState = simulator.load_seed(SEED_PATH)
	recovery.adjust_micro_relationship(
		no_soften,
		"old_chen",
		"test_actor",
		{"trust": 20.0},
		"missing_fact"
	)
	_check(
		not _candidate_exists(
			recovery.build_recovery_candidates(no_soften),
			"old_chen_softened_after_actor_help"
		)
		and _fact_has_cause(
			give_state,
			"old_chen_softened_after_actor_help",
			"actor_gave_food_to_chen_mi"
		),
		"6. Old Chen softening depends on the positive action fact"
	)

	var no_reopen: WorldSimState = simulator.load_seed(SEED_PATH)
	_set_shop_state(no_reopen, {"is_open": false})
	var reopen_ready: WorldSimState = simulator.load_seed(SEED_PATH)
	_set_shop_state(reopen_ready, {"is_open": false})
	var recovery_state := reopen_ready.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	recovery_state["old_chen_recovery_level"] = 30.0
	reopen_ready.micro_state["recovery_state"] = recovery_state
	var old_chen := reopen_ready.get_npc("old_chen")
	old_chen["family_food"] = 2.0
	old_chen["stress"] = 60.0
	reopen_ready.npcs["old_chen"] = old_chen
	_add_source_fact(reopen_ready, "old_chen_softened_after_actor_help")
	_check(
		not _candidate_exists(
			recovery.build_recovery_candidates(no_reopen),
			"old_chen_reopened_shop_half_day"
		)
		and _candidate_exists(
			recovery.build_recovery_candidates(reopen_ready),
			"old_chen_reopened_shop_half_day"
		),
		"7. half-day reopening requires recovery, food, and lower stress"
	)

	var ma_ready: WorldSimState = simulator.load_seed(SEED_PATH)
	var ma := ma_ready.get_npc("ma_shen")
	ma["concern"] = 60.0
	ma_ready.npcs["ma_shen"] = ma
	var chen := ma_ready.get_npc("chen_mi")
	chen["hunger"] = 65.0
	ma_ready.npcs["chen_mi"] = chen
	var ma_without_fact := recovery.build_recovery_candidates(ma_ready)
	_add_source_fact(ma_ready, "ma_shen_brought_porridge")
	_check(
		not _candidate_exists(
			ma_without_fact,
			"ma_shen_kept_checking_on_chen_mi"
		)
		and _candidate_exists(
			recovery.build_recovery_candidates(ma_ready),
			"ma_shen_kept_checking_on_chen_mi"
		),
		"8. continued neighbor care depends on porridge and concern"
	)

	var creditor_ready: WorldSimState = simulator.load_seed(SEED_PATH)
	_add_source_fact(creditor_ready, "creditor_left_debt_notice")
	_add_source_fact(
		creditor_ready,
		"ma_shen_kept_checking_on_chen_mi"
	)
	var creditor_recovery := creditor_ready.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	creditor_recovery["community_support"] = 30.0
	creditor_ready.micro_state["recovery_state"] = creditor_recovery
	_set_shop_state(creditor_ready, {"partial_open": true})
	_check(
		_candidate_exists(
			recovery.build_recovery_candidates(creditor_ready),
			"creditor_delayed_collection_after_support"
		),
		"9. delayed collection requires notice and recovery support"
	)

	var trust_without_memory: WorldSimState = simulator.load_seed(SEED_PATH)
	trust_without_memory.day = 2
	_add_source_fact(trust_without_memory, "actor_gave_food_to_chen_mi")
	recovery.adjust_micro_relationship(
		trust_without_memory,
		"chen_mi",
		"test_actor",
		{"gratitude": 30.0},
		_latest_fact_id(trust_without_memory)
	)
	_check(
		not _candidate_exists(
			recovery.build_relationship_echoes(trust_without_memory),
			"chen_mi_trust_echo_for_actor"
		)
		and _has_fact(give_state, "chen_mi_trust_echo_for_actor"),
		"10. trust echo requires positive memory and relationship"
	)

	var no_harm: WorldSimState = simulator.load_seed(SEED_PATH)
	_check(
		not _candidate_exists(
			recovery.build_relationship_echoes(no_harm),
			"chen_mi_avoidance_echo_for_actor"
		),
		"11. avoidance echo requires a harmful action fact"
	)

	var close_without_low_trust: WorldSimState = simulator.load_seed(SEED_PATH)
	close_without_low_trust.day = 2
	_add_source_fact(
		close_without_low_trust,
		"actor_reported_chen_mi_to_guard"
	)
	_check(
		not _candidate_exists(
			recovery.build_relationship_echoes(close_without_low_trust),
			"old_chen_closes_door_to_actor"
		),
		"12. Old Chen refusal also requires low trust"
	)

	var report := _run_branch("report_to_guard")
	var report_state := report["state"] as WorldSimState
	_check(
		_has_fact(report_state, "chen_mi_avoidance_echo_for_actor")
		and _has_fact(report_state, "old_chen_closes_door_to_actor"),
		"13. report branch creates negative relationship echoes"
	)

	var buy := _run_branch("buy_spoiled_grain_low")
	var buy_state := buy["state"] as WorldSimState
	_check(
		_has_fact(buy_state, "chen_mi_avoidance_echo_for_actor")
		and _has_fact(buy_state, "old_chen_closes_door_to_actor"),
		"14. low-price purchase creates negative relationship echoes"
	)

	var ignore := _run_branch("ignore_chen_mi")
	var ignore_state := ignore["state"] as WorldSimState
	_check(
		not _has_fact(ignore_state, "chen_mi_trust_echo_for_actor")
		and not _has_fact(
			ignore_state,
			"old_chen_softened_after_actor_help"
		),
		"15. ignore branch does not invent a positive actor echo"
	)

	var give_candidates := resolver.build_all_action_candidates(
		give_state,
		give_actor
	)
	var comfort_state := give_state.duplicate_state()
	var comfort_result := resolver.resolve_micro_action(
		comfort_state,
		give_actor.duplicate(true),
		"comfort_chen_mi",
		"chen_mi_recognizes_actor_scene"
	)
	_check(
		_candidate_exists(give_candidates, "comfort_chen_mi")
		and bool(comfort_result.get("ok", false))
		and _has_fact(comfort_state, "actor_comforted_chen_mi")
		and _has_trace(comfort_state, "quiet_talk_at_shop_step")
		and _has_memory(
			comfort_state,
			"chen_mi_remembers_being_comforted"
		),
		"16. positive echo adds and resolves the comfort action"
	)

	var blocked_result := resolver.resolve_micro_action(
		report_state,
		report["actor"] as Dictionary,
		"ask_grain_origin",
		SCENE_ID
	)
	_check(
		not resolver.can_resolve_action(
			report_state,
			report["actor"] as Dictionary,
			"ask_grain_origin",
			SCENE_ID
		)
		and String(blocked_result.get("error", ""))
		== "relationship_blocked",
		"17. relationship blocking returns the required error"
	)

	var branch_states: Array[WorldSimState] = [
		give_state,
		report_state,
		buy_state,
		ignore_state,
	]
	_check(
		_all_recovery_facts_have_causes(branch_states),
		"18. every recovery or echo fact has cause_fact_ids"
	)
	_check(
		_all_recovery_traces_have_sources(branch_states),
		"19. every recovery or echo trace has source_fact_id"
	)
	_check(
		_all_recovery_keys_unique(branch_states),
		"20. recovery and echo facts do not repeat daily"
	)

	var left := _run_branch("give_food_to_chen_mi")["state"] as WorldSimState
	var right := _run_branch("give_food_to_chen_mi")["state"] as WorldSimState
	_check(
		_recovery_signature(left) == _recovery_signature(right),
		"21. same seed reproduces the recovery branch"
	)

	var observer := ObserverModel.new()
	var observed_baseline := observer.run_baseline(15)
	var observed_injection := observer.run_with_test_injection(15, 3)
	observer.export_markdown_report(
		{
			"baseline": observed_baseline,
			"test_injection": observed_injection,
			"comparison": observer.compare_runs(
				observed_baseline,
				observed_injection
			),
		},
		OUTPUT_PATH
	)
	var output_text := FileAccess.get_file_as_string(OUTPUT_PATH)
	_check(
		"## 湖湾镇恢复与关系回声时间线" in output_text
		and "## 外部模拟行动后五日恢复分支" in output_text,
		"22. observer contains recovery timeline and five-day branches"
	)

	if failures.is_empty():
		print("[LAKE TOWN RECOVERY SYSTEM RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN RECOVERY SYSTEM FAIL] " + failure)
		print(
			"[LAKE TOWN RECOVERY SYSTEM RESULT] FAIL: %s"
			% JSON.stringify(failures)
		)
		quit(1)


func _run_branch(action_id: String) -> Dictionary:
	var state: WorldSimState = simulator.load_seed(SEED_PATH)
	simulator.advance_days(state, 6)
	var actor := _test_actor()
	var result := resolver.resolve_micro_action(
		state,
		actor,
		action_id,
		SCENE_ID
	)
	simulator.advance_days(state, 5)
	return {"state": state, "actor": actor, "result": result}


func _test_actor() -> Dictionary:
	return {
		"id": "test_actor",
		"inventory": {"food": 1, "spoiled_grain": 0},
		"money": 10.0,
		"traits": [],
		"perception": 5,
		"status_tags": [],
	}


func _candidate_exists(candidates: Array, id: String) -> bool:
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		if String(candidate.get("id", "")) == id:
			return true
	return false


func _has_fact(state: WorldSimState, type_name: String) -> bool:
	for fact in state.world_facts:
		if fact.type == type_name:
			return true
	return false


func _has_memory(state: WorldSimState, type_name: String) -> bool:
	for memory_value: Variant in state.memories:
		var memory := memory_value as Dictionary
		if String(memory.get("type", "")) == type_name:
			return true
	return false


func _has_trace(state: WorldSimState, type_name: String) -> bool:
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		if String(trace.get("type", "")) == type_name:
			return true
	return false


func _fact_has_cause(
		state: WorldSimState,
		type_name: String,
		cause_type: String
	) -> bool:
	var cause_id := ""
	for fact in state.world_facts:
		if fact.type == cause_type:
			cause_id = fact.id
			break
	for fact in state.world_facts:
		if fact.type == type_name:
			return cause_id != "" and cause_id in fact.cause_fact_ids
	return false


func _has_relationship_fields(relationship: Dictionary) -> bool:
	for field: String in RELATIONSHIP_FIELDS:
		if not relationship.has(field):
			return false
	return true


func _set_shop_state(state: WorldSimState, changes: Dictionary) -> void:
	var shop := state.get_location("old_chen_shop")
	var shop_state := shop.get("state", {}) as Dictionary
	for key: Variant in changes:
		shop_state[key] = changes[key]
	shop["state"] = shop_state
	state.locations["old_chen_shop"] = shop


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
			"cause_fact_ids": ["test_source"],
			"effects": {},
			"tags": ["test_setup"],
		}
	)


func _latest_fact_id(state: WorldSimState) -> String:
	if state.world_facts.is_empty():
		return ""
	return state.world_facts[-1].id


func _all_recovery_facts_have_causes(
		states: Array[WorldSimState]
	) -> bool:
	var found := 0
	for state: WorldSimState in states:
		for fact in state.world_facts:
			if (
				String(fact.data.get("recovery_key", "")) == ""
				and String(
					fact.data.get("relationship_echo_key", "")
				) == ""
			):
				continue
			found += 1
			if fact.cause_fact_ids.is_empty():
				return false
	return found >= 6


func _all_recovery_traces_have_sources(
		states: Array[WorldSimState]
	) -> bool:
	var found := 0
	for state: WorldSimState in states:
		var fact_ids: Array[String] = []
		for fact in state.world_facts:
			if (
				String(fact.data.get("recovery_key", "")) != ""
				or String(
					fact.data.get("relationship_echo_key", "")
				) != ""
			):
				fact_ids.append(fact.id)
		for trace_value: Variant in state.traces:
			var trace := trace_value as Dictionary
			var source_id := String(trace.get("source_fact_id", ""))
			if source_id not in fact_ids:
				continue
			found += 1
			if source_id == "":
				return false
	return found >= 6


func _all_recovery_keys_unique(states: Array[WorldSimState]) -> bool:
	for state: WorldSimState in states:
		var recovery_state := state.micro_state.get(
			"recovery_state",
			{}
		) as Dictionary
		var seen: Dictionary = {}
		for entry_value: Variant in recovery_state.get(
			"recovery_history",
			[]
		):
			var entry := entry_value as Dictionary
			var key := String(entry.get("recovery_key", ""))
			if key == "" or seen.has(key):
				return false
			seen[key] = true
	return true


func _recovery_signature(state: WorldSimState) -> String:
	var recovery_state := state.micro_state.get(
		"recovery_state",
		{}
	) as Dictionary
	var entries: Array[String] = []
	for entry_value: Variant in recovery_state.get(
		"recovery_history",
		[]
	):
		var entry := entry_value as Dictionary
		entries.append(
			"%d:%s"
			% [
				int(entry.get("day", 0)),
				entry.get("recovery_key", ""),
			]
		)
	return "|".join(entries)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN RECOVERY SYSTEM PASS] " + message)
	else:
		failures.append(message)
