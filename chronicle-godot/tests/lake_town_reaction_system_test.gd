extends SceneTree

const SimulatorModel = preload("res://scripts/sim/world_simulator.gd")
const ReactionModel = preload(
	"res://scripts/sim/lake_town_reaction_system.gd"
)
const ResolverModel = preload("res://scripts/sim/micro_action_resolver.gd")
const ObserverModel = preload("res://scripts/dev/world_sim_observer.gd")

const SEED_PATH := "res://data/world_seed_mirror_lake.json"
const SCENE_ID := "chen_mi_hiding_spoiled_grain_scene"
const OUTPUT_PATH := (
	"res://texts/reports/2026/2026-6/2026-6-15/"
	+ "2026-06-15_world_sim_observer_output.md"
)
const REACTION_TYPES: Array[String] = [
	"chen_mi_ate_spoiled_grain",
	"chen_mi_fell_sick_from_spoiled_grain",
	"old_chen_discovered_spoiled_grain",
	"ma_shen_noticed_closed_shop",
	"ma_shen_brought_porridge",
	"creditor_left_debt_notice",
	"guard_checked_old_chen_shop",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var simulator := SimulatorModel.new()
	var reactions := ReactionModel.new()
	var resolver := ResolverModel.new()
	var initial: WorldSimState = simulator.load_seed(SEED_PATH)
	_check(
		not initial.get_npc("ma_shen").is_empty()
		and not initial.get_npc("liu_zhangfang").is_empty(),
		"lake town seed includes Ma Shen and Liu Zhangfang"
	)
	simulator.advance_days(initial, 5)
	_check(
		not _has_fact(initial, "chen_mi_ate_spoiled_grain"),
		"Chen Mi cannot eat spoiled grain before taking it"
	)

	var baseline: WorldSimState = simulator.load_seed(SEED_PATH)
	simulator.advance_days(baseline, 6)
	_check(not _find_scene(baseline).is_empty(), "Day 6 reaches the Chen Mi scene")
	var baseline_fact_count := baseline.world_facts.size()
	simulator.advance_days(baseline, 3)
	var three_day_reactions := _reaction_fact_types_from(
		baseline,
		baseline_fact_count
	)
	_check(
		three_day_reactions.size() >= 2,
		"baseline creates at least two micro reactions within three days"
	)

	var day_six: WorldSimState = simulator.load_seed(SEED_PATH)
	simulator.advance_days(day_six, 6)
	var low_hunger := day_six.duplicate_state()
	var low_hunger_chen := low_hunger.get_npc("chen_mi")
	low_hunger_chen["hunger"] = 84.0
	low_hunger.npcs["chen_mi"] = low_hunger_chen
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(low_hunger),
			"chen_mi_ate_spoiled_grain"
		),
		"spoiled grain eating requires the hunger threshold"
	)
	var no_grain := day_six.duplicate_state()
	var no_grain_chen := no_grain.get_npc("chen_mi")
	no_grain_chen["hunger"] = 90.0
	no_grain_chen["inventory"] = []
	no_grain.npcs["chen_mi"] = no_grain_chen
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(no_grain),
			"chen_mi_ate_spoiled_grain"
		),
		"spoiled grain eating requires Chen Mi to hold spoiled grain"
	)

	var eat_state := day_six.duplicate_state()
	var eat_chen := eat_state.get_npc("chen_mi")
	eat_chen["hunger"] = 90.0
	eat_state.npcs["chen_mi"] = eat_chen
	var hunger_before := float(eat_chen.get("hunger", 0.0))
	var health_before := float(eat_chen.get("health", 0.0))
	var eat_result: Dictionary = reactions.apply_reaction(
		eat_state,
		"chen_mi_ate_spoiled_grain"
	)
	var eaten_chen := eat_state.get_npc("chen_mi")
	_check(bool(eat_result.get("ok", false)), "Chen Mi eating reaction resolves")
	_check(
		float(eaten_chen.get("hunger", 0.0)) < hunger_before,
		"eating spoiled grain lowers hunger"
	)
	_check(
		float(eaten_chen.get("health", 0.0)) < health_before,
		"eating spoiled grain worsens health"
	)
	_check(
		not (eat_result.get("created_fact_ids", []) as Array).is_empty()
		and (eat_result.get("created_trace_ids", []) as Array).size() >= 2
		and not (
			eat_result.get("created_memory_ids", []) as Array
		).is_empty(),
		"eating spoiled grain creates fact, traces, and memory"
	)

	var sick_without_eating := day_six.duplicate_state()
	var vulnerable_chen := sick_without_eating.get_npc("chen_mi")
	vulnerable_chen["health"] = 70.0
	sick_without_eating.npcs["chen_mi"] = vulnerable_chen
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(sick_without_eating),
			"chen_mi_fell_sick_from_spoiled_grain"
		),
		"sickness cannot occur without the spoiled grain eating reaction"
	)
	eat_state.day += 1
	_check(
		_candidate_exists(
			reactions.build_reaction_candidates(eat_state),
			"chen_mi_fell_sick_from_spoiled_grain"
		),
		"sickness becomes available at least one day after eating"
	)

	var discover_missing_trace := day_six.duplicate_state()
	discover_missing_trace.day += 1
	_remove_trace(discover_missing_trace, "child_hiding_bag")
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(discover_missing_trace),
			"old_chen_discovered_spoiled_grain"
		),
		"Old Chen discovery requires the hiding trace"
	)
	var discover_ready := day_six.duplicate_state()
	discover_ready.day += 1
	_check(
		_candidate_exists(
			reactions.build_reaction_candidates(discover_ready),
			"old_chen_discovered_spoiled_grain"
		),
		"Old Chen discovery uses traces, shop closure, and stress"
	)

	var notice_early := day_six.duplicate_state()
	notice_early.micro_state["closed_shop_days"] = 1
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(notice_early),
			"ma_shen_noticed_closed_shop"
		),
		"Ma Shen does not notice before two closed-shop days"
	)
	var notice_ready := day_six.duplicate_state()
	notice_ready.micro_state["closed_shop_days"] = 2
	_check(
		_candidate_exists(
			reactions.build_reaction_candidates(notice_ready),
			"ma_shen_noticed_closed_shop"
		),
		"Ma Shen noticing requires closure duration and closed-shop trace"
	)
	reactions.apply_reaction(notice_ready, "ma_shen_noticed_closed_shop")
	var hungry_after_notice := notice_ready.get_npc("chen_mi")
	hungry_after_notice["hunger"] = 90.0
	notice_ready.npcs["chen_mi"] = hungry_after_notice
	_check(
		_candidate_exists(
			reactions.build_reaction_candidates(notice_ready),
			"ma_shen_brought_porridge"
		),
		"porridge requires prior notice, spare food, trust, and need"
	)
	var no_spare := notice_ready.duplicate_state()
	var no_spare_ma := no_spare.get_npc("ma_shen")
	no_spare_ma["food_spare"] = 0.0
	no_spare.npcs["ma_shen"] = no_spare_ma
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(no_spare),
			"ma_shen_brought_porridge"
		),
		"Ma Shen cannot bring porridge without spare food"
	)

	var creditor_early := day_six.duplicate_state()
	creditor_early.micro_state["closed_shop_days"] = 3
	var creditor_old := creditor_early.get_npc("old_chen")
	creditor_old["debt"] = 70.0
	creditor_early.npcs["old_chen"] = creditor_old
	var patient_creditor := creditor_early.get_npc("liu_zhangfang")
	patient_creditor["patience"] = 26.0
	creditor_early.npcs["liu_zhangfang"] = patient_creditor
	_check(
		not _candidate_exists(
			reactions.build_reaction_candidates(creditor_early),
			"creditor_left_debt_notice"
		),
		"creditor notice waits until patience reaches its threshold"
	)
	patient_creditor["patience"] = 25.0
	creditor_early.npcs["liu_zhangfang"] = patient_creditor
	_check(
		_candidate_exists(
			reactions.build_reaction_candidates(creditor_early),
			"creditor_left_debt_notice"
		),
		"creditor notice requires debt, closure duration, and patience"
	)

	_check(
		not _has_fact(day_six, "guard_checked_old_chen_shop"),
		"guard visit does not appear without a report fact"
	)
	var report_branch := day_six.duplicate_state()
	var report_actor := _test_actor()
	resolver.resolve_micro_action(
		report_branch,
		report_actor,
		"report_to_guard",
		SCENE_ID
	)
	simulator.advance_one_day(report_branch)
	_check(
		_has_fact(report_branch, "guard_checked_old_chen_shop"),
		"report branch can produce a guard visit on a later day"
	)

	var give_branch := day_six.duplicate_state()
	resolver.resolve_micro_action(
		give_branch,
		_test_actor(),
		"give_food_to_chen_mi",
		SCENE_ID
	)
	simulator.advance_days(give_branch, 3)
	_check(
		not _has_fact(give_branch, "chen_mi_ate_spoiled_grain"),
		"give-food branch prevents immediate spoiled grain eating"
	)

	var ignore_branch := day_six.duplicate_state()
	resolver.resolve_micro_action(
		ignore_branch,
		_test_actor(),
		"ignore_chen_mi",
		SCENE_ID
	)
	simulator.advance_days(ignore_branch, 3)
	_check(
		_has_fact(ignore_branch, "chen_mi_ate_spoiled_grain")
		or (
			float(ignore_branch.get_npc("chen_mi").get("health", 100.0))
			< float(give_branch.get_npc("chen_mi").get("health", 100.0))
		),
		"ignore branch has greater food or health risk than give-food branch"
	)

	var buy_branch := day_six.duplicate_state()
	var buy_start_hunger := float(
		buy_branch.get_npc("chen_mi").get("hunger", 0.0)
	)
	var buy_start_fear := float(
		buy_branch.get_npc("chen_mi").get("fear", 0.0)
	)
	resolver.resolve_micro_action(
		buy_branch,
		_test_actor(),
		"buy_spoiled_grain_low",
		SCENE_ID
	)
	simulator.advance_days(buy_branch, 3)
	var buy_chen := buy_branch.get_npc("chen_mi")
	_check(
		not "spoiled_grain" in (
			buy_chen.get("inventory", []) as Array
		),
		"low-price purchase branch removes spoiled grain from Chen Mi"
	)
	_check(
		float(buy_chen.get("hunger", 0.0)) >= buy_start_hunger
		or float(buy_chen.get("fear", 0.0)) > buy_start_fear,
		"low-price purchase branch keeps hunger or fear pressure high"
	)

	var source_state: WorldSimState = simulator.load_seed(SEED_PATH)
	simulator.advance_days(source_state, 15)
	_check(
		_all_reaction_facts_have_causes(source_state),
		"every reaction WorldFact has cause_fact_ids"
	)
	_check(
		_all_reaction_traces_have_sources(source_state),
		"every reaction Trace has source_fact_id"
	)
	_check(
		_reaction_keys_are_unique(source_state),
		"reaction facts do not repeat every day"
	)

	var reproducible_left: WorldSimState = simulator.load_seed(SEED_PATH)
	var reproducible_right: WorldSimState = simulator.load_seed(SEED_PATH)
	simulator.advance_days(reproducible_left, 15)
	simulator.advance_days(reproducible_right, 15)
	_check(
		_reaction_signature(reproducible_left)
		== _reaction_signature(reproducible_right),
		"same seed reproduces the reaction timeline"
	)

	var observer := ObserverModel.new()
	var observed_baseline := observer.run_baseline(30)
	var observed_injection := observer.run_with_test_injection(30, 3)
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
		"## 湖湾镇微观后续反应时间线" in output_text
		and "## 外部模拟行动后三日后续分支" in output_text,
		"observer output contains reaction timeline and three-day branches"
	)

	print(
		"[LAKE TOWN REACTION SUMMARY] baseline=%s give=%s ignore=%s report=%s buy=%s"
		% [
			", ".join(three_day_reactions),
			_reaction_signature(give_branch),
			_reaction_signature(ignore_branch),
			_reaction_signature(report_branch),
			_reaction_signature(buy_branch),
		]
	)
	if failures.is_empty():
		print("[LAKE TOWN REACTION SYSTEM RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[LAKE TOWN REACTION SYSTEM FAIL] " + failure)
		print("[LAKE TOWN REACTION SYSTEM RESULT] FAIL: %s" % failures)
		quit(1)


func _candidate_exists(candidates: Array, reaction_id: String) -> bool:
	for candidate_value: Variant in candidates:
		var candidate := candidate_value as Dictionary
		if String(candidate.get("id", "")) == reaction_id:
			return true
	return false


func _reaction_fact_types_from(
		state: WorldSimState,
		start_index: int
	) -> Array[String]:
	var output: Array[String] = []
	for index: int in range(start_index, state.world_facts.size()):
		var fact := state.world_facts[index]
		if fact.type in REACTION_TYPES:
			output.append(fact.type)
	return output


func _has_fact(state: WorldSimState, fact_type: String) -> bool:
	for fact in state.world_facts:
		if fact.type == fact_type:
			return true
	return false


func _find_scene(state: WorldSimState) -> Dictionary:
	for scene_value: Variant in state.narratable_states:
		var scene := scene_value as Dictionary
		if String(scene.get("id", "")) == SCENE_ID:
			return scene
	return {}


func _remove_trace(state: WorldSimState, trace_type: String) -> void:
	for index: int in range(state.traces.size() - 1, -1, -1):
		if String(state.traces[index].get("type", "")) == trace_type:
			state.traces.remove_at(index)


func _all_reaction_facts_have_causes(state: WorldSimState) -> bool:
	var found := 0
	for fact in state.world_facts:
		if fact.type not in REACTION_TYPES:
			continue
		found += 1
		if fact.cause_fact_ids.is_empty():
			return false
	return found >= 5


func _all_reaction_traces_have_sources(state: WorldSimState) -> bool:
	var reaction_fact_ids: Array[String] = []
	for fact in state.world_facts:
		if fact.type in REACTION_TYPES:
			reaction_fact_ids.append(fact.id)
	var found := 0
	for trace_value: Variant in state.traces:
		var trace := trace_value as Dictionary
		if String(trace.get("source_fact_id", "")) not in reaction_fact_ids:
			continue
		found += 1
		if String(trace.get("source_fact_id", "")) == "":
			return false
	return found >= 5


func _reaction_keys_are_unique(state: WorldSimState) -> bool:
	var seen: Dictionary = {}
	for entry_value: Variant in state.micro_state.get("reaction_history", []):
		var entry := entry_value as Dictionary
		var key := String(entry.get("reaction_key", ""))
		if key == "" or seen.has(key):
			return false
		seen[key] = true
	return seen.size() >= 5


func _reaction_signature(state: WorldSimState) -> String:
	var entries: Array[String] = []
	for entry_value: Variant in state.micro_state.get("reaction_history", []):
		var entry := entry_value as Dictionary
		entries.append(
			"%d:%s"
			% [
				int(entry.get("day", 0)),
				entry.get("reaction_key", ""),
			]
		)
	return "|".join(entries)


func _test_actor() -> Dictionary:
	return {
		"id": "test_actor",
		"inventory": {"food": 1, "spoiled_grain": 0},
		"money": 10.0,
		"traits": [],
		"perception": 5,
		"status_tags": [],
	}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[LAKE TOWN REACTION SYSTEM PASS] " + message)
	else:
		failures.append(message)
