extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")
const EntityStoreModel = preload("res://scripts/sim/entity/entity_store.gd")
const ItemStoreModel = preload("res://scripts/sim/item/item_store.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const RELATIONSHIP_AXIS_DEFS_PATH := "res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
const ITEM_DEFS_PATH := "res://data/sim/raw/item_defs/basic_item_defs.json"
const LAKE_TOWN_FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"
const LAKE_TOWN_SCENARIO_PATH := "res://data/sim/fixtures/scenarios/lake_town_food_crisis_sequence.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_rule_paths := [BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	var registry = SimRegistryModel.new()
	registry.load_action_rules(raw_rule_paths)
	registry.load_raw_definition_files([ITEM_DEFS_PATH])
	var rules: Array = registry.get_action_rules()
	var builder = SimSnapshotBuilderModel.new()
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()

	var lake_context = SimContextModel.new(registry.load_json(LAKE_TOWN_FIXTURE_PATH))
	var lake_stores := _make_stores(lake_context, registry)
	var lake_snapshot = builder.build_snapshot(lake_context, lake_stores)
	_check(
		lake_snapshot.fixture_id == "lake_town_food_crisis"
		and lake_snapshot.get_entity("chen_mi").get("id", "") == "chen_mi",
		"1. SimSnapshotBuilder 能从 context + stores 构建 snapshot"
	)

	var lake_candidates: Array = affordance_system.generate_candidates(lake_snapshot, rules)
	var give_food_candidate = _find_candidate(lake_candidates, "give_food_to_hungry_person", "chen_mi")
	var give_food_result = resolver.resolve_action(give_food_candidate, lake_context)
	writer.apply_result(give_food_result, lake_stores)
	_check(
		lake_stores["state_store"].get_state("chen_mi", "hunger") == "medium",
		"2. 给陈米食物后，StateStore 中 chen_mi.hunger 为 medium"
	)

	var lake_after_snapshot = builder.build_snapshot(lake_context, lake_stores)
	var lake_after_candidates: Array = affordance_system.generate_candidates(lake_after_snapshot, rules)
	_check(
		not _candidate_exists(lake_after_candidates, "give_food_to_hungry_person", "chen_mi"),
		"3. 基于新 snapshot 生成候选时，不再为 chen_mi 生成 give_food_to_hungry_person"
	)

	var report_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var report_stores := _make_stores(report_context, registry)
	var report_snapshot = builder.build_snapshot(report_context, report_stores)
	var report_candidates: Array = affordance_system.generate_candidates(report_snapshot, rules)
	var report_candidate = _find_candidate(
		report_candidates,
		"report_discipline_violation_to_superior",
		"recruit_elai"
	)
	var report_result = resolver.resolve_action(report_candidate, report_context)
	writer.apply_result(report_result, report_stores)
	_check(
		not report_stores["trace_store"].find_traces_by_type("institutional_record_mark").is_empty(),
		"4. 报告伊莱后，TraceStore 中存在 institutional_record_mark"
	)

	var report_after_snapshot = builder.build_snapshot(report_context, report_stores)
	var report_after_candidates: Array = affordance_system.generate_candidates(report_after_snapshot, rules)
	_check(
		_candidate_exists(report_after_candidates, "inspect_visible_trace", "ration_record_marked_for_review"),
		"5. 基于新 snapshot 生成候选时，可以从 trace store 生成 inspect_visible_trace 候选"
	)
	_check(
		not report_stores["rumor_store"].find_rumors_by_source_fact("actor_reported_discipline_violation").is_empty(),
		"6. 报告伊莱后，RumorStore 中存在 outpost_discipline_report_seed"
	)
	_check(
		_candidate_exists(report_after_candidates, "hear_rumor_seed", "outpost_discipline_report_seed"),
		"7. 基于新 snapshot 生成候选时，可以生成 hear_rumor_seed 候选"
	)

	var conceal_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var conceal_stores := _make_stores(conceal_context, registry)
	var conceal_snapshot = builder.build_snapshot(conceal_context, conceal_stores)
	var conceal_candidates: Array = affordance_system.generate_candidates(conceal_snapshot, rules)
	var conceal_candidate = _find_candidate(
		conceal_candidates,
		"conceal_discipline_violation_once",
		"recruit_elai"
	)
	var conceal_result = resolver.resolve_action(conceal_candidate, conceal_context)
	writer.apply_result(conceal_result, conceal_stores)
	_check(
		int(conceal_stores["relationship_store"].get_relation("recruit_elai", "player", "debt")) >= 10,
		"8. 替伊莱隐瞒后，RelationshipStore 中 recruit_elai -> player debt >= 10"
	)

	var conceal_after_snapshot = builder.build_snapshot(conceal_context, conceal_stores)
	var conceal_after_candidates: Array = affordance_system.generate_candidates(conceal_after_snapshot, rules)
	_check(
		_candidate_exists(conceal_after_candidates, "request_favor_from_indebted_person", "recruit_elai"),
		"9. 基于新 snapshot 生成候选时，可以生成 request_favor_from_indebted_person 候选"
	)
	_check(
		not conceal_after_snapshot.get_memories("recruit_elai").is_empty(),
		"10. MemoryStore 能被 snapshot 读取"
	)

	var runner = SimRunnerModel.new()
	var runner_result: Dictionary = runner.run_sequence(
		LAKE_TOWN_FIXTURE_PATH,
		LAKE_TOWN_SCENARIO_PATH,
		raw_rule_paths
	)
	var probe: Dictionary = runner_result.get("snapshot_summary", {}).get("final_candidate_probe", {})
	_check(
		bool(runner_result.get("success", false))
		and str(runner_result.get("candidate_context_source", "")) == "SimSnapshot"
		and _world_log_uses_snapshot(runner_result)
		and "give_food_to_hungry_person:chen_mi" not in (probe.get("action_ids", []) as Array),
		"11. SimRunner 每一步候选生成使用 snapshot"
	)

	_finish()


func _make_stores(context: Variant, registry: Variant) -> Dictionary:
	var entity_store = EntityStoreModel.new()
	entity_store.load_from_context(context)
	var fact_store = FactStoreModel.new()
	var item_store = ItemStoreModel.new()
	item_store.configure(
		registry.list_definitions("item"),
		entity_store,
		context.locations,
		fact_store
	)
	var fixture_path := (
		LAKE_TOWN_FIXTURE_PATH
		if str(context.fixture_id) == "lake_town_food_crisis"
		else SEVENTH_OUTPOST_FIXTURE_PATH
	)
	item_store.load_initial_items(
		(registry.load_json(fixture_path).get("initial_items", []) as Array)
	)
	var state_store = StateStoreModel.new()
	state_store.load_from_context(context)
	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	return {
		"entity_store": entity_store,
		"fact_store": fact_store,
		"state_store": state_store,
		"item_store": item_store,
		"relationship_store": relationship_store,
		"memory_store": MemoryStoreModel.new(),
		"trace_store": TraceStoreModel.new(),
		"rumor_store": RumorStoreModel.new(),
	}


func _find_candidate(candidates: Array, rule_id: String, target_id: String = "") -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) != rule_id:
			continue
		if target_id != "" and str(candidate.target_id) != target_id:
			continue
		return candidate
	return null


func _candidate_exists(candidates: Array, rule_id: String, target_id: String = "") -> bool:
	return _find_candidate(candidates, rule_id, target_id) != null


func _world_log_uses_snapshot(result: Dictionary) -> bool:
	for entry: Dictionary in result.get("world_log", []):
		if str(entry.get("candidate_context_source", "")) != "SimSnapshot":
			return false
	return true


func _finish() -> void:
	if failures.is_empty():
		print("[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 SIM SNAPSHOT CANDIDATE CONTEXT FAIL] " + failure)
		print("[V5 SIM SNAPSHOT CANDIDATE CONTEXT RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 SIM SNAPSHOT CANDIDATE CONTEXT PASS] " + message)
	else:
		failures.append(message)
