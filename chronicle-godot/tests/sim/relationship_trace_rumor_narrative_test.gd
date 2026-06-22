extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")
const NarrativeSurfaceAdapterModel = preload("res://scripts/sim/narrative/narrative_surface_adapter.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const RELATIONSHIP_AXIS_DEFS_PATH := "res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
const LAKE_TOWN_FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	registry.load_action_rules([BASIC_RULES_PATH, DOMAIN_RULES_PATH])
	var rules: Array = registry.get_action_rules()
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()

	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	_check(
		relationship_store.get_axis_def("trust").get("axis_id", "") == "trust"
		and relationship_store.get_axis_def("debt").get("axis_id", "") == "debt",
		"1. RelationshipStore 能加载 relationship_axis_defs"
	)

	relationship_store.set_relation("a", "b", "gratitude", 150)
	_check(
		int(relationship_store.get_relation("a", "b", "gratitude")) == 100
		and relationship_store.get_relation_tier("a", "b", "gratitude") == "extreme",
		"2. gratitude 被 clamp 在 0 到 100"
	)

	relationship_store.set_relation("a", "b", "trust", -150)
	_check(
		int(relationship_store.get_relation("a", "b", "trust")) == -100
		and relationship_store.get_relation_tier("a", "b", "trust") == "hostile",
		"3. trust 支持 -100 到 100"
	)

	var lake_context = SimContextModel.new(registry.load_json(LAKE_TOWN_FIXTURE_PATH))
	var lake_candidates: Array = affordance_system.generate_candidates(lake_context, rules)
	var give_food_result = resolver.resolve_action(
		_find_candidate_by_rule(lake_candidates, "give_food_to_hungry_person"),
		lake_context
	)
	_check(
		_relationship_delta_exists(give_food_result, "chen_mi", "player", "gratitude", 15)
		and _relationship_delta_exists(give_food_result, "chen_mi", "player", "trust", 5)
		and _relationship_delta_exists(give_food_result, "chen_mi", "player", "fear", -5),
		"4. 给陈米食物后 gratitude +15，trust +5，fear -5"
	)

	var outpost_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var outpost_candidates: Array = affordance_system.generate_candidates(outpost_context, rules)
	var report_result = resolver.resolve_action(
		_find_candidate_by_rule(outpost_candidates, "report_discipline_violation_to_superior"),
		outpost_context
	)
	_check(
		_relationship_delta_exists(report_result, "recruit_elai", "player", "resentment", 25)
		and _relationship_delta_exists(report_result, "recruit_elai", "player", "trust", -20)
		and _relationship_delta_exists(report_result, "captain_ron", "player", "discipline_respect", 15),
		"5. 报告伊莱后 resentment +25，trust -20，discipline_respect +15"
	)

	var conceal_result = resolver.resolve_action(
		_find_candidate_by_rule(outpost_candidates, "conceal_discipline_violation_once"),
		outpost_context
	)
	_check(
		_relationship_delta_exists(conceal_result, "recruit_elai", "player", "gratitude", 15)
		and _relationship_delta_exists(conceal_result, "recruit_elai", "player", "trust", 15)
		and _relationship_delta_exists(conceal_result, "recruit_elai", "player", "debt", 10),
		"6. 替伊莱隐瞒后 gratitude +15，trust +15，debt +10"
	)

	var trace_store = TraceStoreModel.new()
	trace_store.add_trace({
		"trace_id": "manual_trace",
		"trace_type": "test_trace",
		"location_id": "outpost_kitchen",
		"source_fact_type": "actor_reported_discipline_violation",
	})
	_check(
		not trace_store.find_traces_by_type("test_trace").is_empty()
		and not trace_store.list_traces_by_location("outpost_kitchen").is_empty(),
		"7. TraceStore 能保存 trace"
	)

	var rumor_store = RumorStoreModel.new()
	rumor_store.add_rumor_seed({
		"rumor_id": "manual_rumor",
		"source_fact_type": "actor_reported_discipline_violation",
		"origin_location": "outpost_kitchen",
	})
	_check(
		not rumor_store.find_rumors_by_source_fact("actor_reported_discipline_violation").is_empty()
		and not rumor_store.list_rumors_by_location("outpost_kitchen").is_empty(),
		"8. RumorStore 能保存 rumor seed"
	)

	var narrative_adapter = NarrativeSurfaceAdapterModel.new()
	var give_food_summary: Dictionary = narrative_adapter.build_transaction_summary(give_food_result, lake_context)
	_check(
		not give_food_summary.is_empty()
		and "actor_gave_food_to_target" in (give_food_summary.get("fact_types", []) as Array),
		"9. NarrativeSurfaceAdapter 能为给食物生成 summary"
	)

	_check(
		not report_result.traces_added.is_empty()
		and str(report_result.traces_added[0].get("trace_type", "")) == "institutional_record_mark",
		"10. 报告伊莱后，TransactionResult 包含 trace"
	)
	_check(
		not report_result.rumors_added.is_empty()
		and str(report_result.rumors_added[0].get("spread_scope", "")) == "squad",
		"11. 报告伊莱后，TransactionResult 包含 rumor seed"
	)
	_check(
		not report_result.narrative_result.is_empty()
		and "actor_reported_discipline_violation" in (report_result.narrative_result.get("fact_types", []) as Array),
		"12. 报告伊莱后，NarrativeResult 不为空"
	)
	_check(
		conceal_result.rumors_added.is_empty(),
		"13. 替伊莱隐瞒后，不生成 rumor seed"
	)

	var fact_store = FactStoreModel.new()
	var state_store = StateStoreModel.new()
	state_store.load_from_context(outpost_context)
	var writer_relationship_store = RelationshipStoreModel.new()
	writer_relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	var memory_store = MemoryStoreModel.new()
	var writer_trace_store = TraceStoreModel.new()
	var writer_rumor_store = RumorStoreModel.new()
	var writer = TransactionWorldWriterModel.new()
	writer.apply_result(report_result, {
		"fact_store": fact_store,
		"state_store": state_store,
		"relationship_store": writer_relationship_store,
		"memory_store": memory_store,
		"trace_store": writer_trace_store,
		"rumor_store": writer_rumor_store,
	})
	_check(
		not fact_store.find_facts_by_type("actor_reported_discipline_violation").is_empty()
		and int(writer_relationship_store.get_relation("recruit_elai", "player", "resentment")) == 25
		and not memory_store.find_memories_by_type("recruit_elai", "being_reported").is_empty()
		and not writer_trace_store.find_traces_by_source_fact("actor_reported_discipline_violation").is_empty()
		and not writer_rumor_store.find_rumors_by_source_fact("actor_reported_discipline_violation").is_empty(),
		"14. TransactionWorldWriter 能把 facts / states / relationships / memories / traces / rumors 写入对应 store"
	)

	_finish()


func _relationship_delta_exists(
	result: Variant,
	source_id: String,
	target_id: String,
	axis: String,
	delta: int
) -> bool:
	for change: Dictionary in result.relationship_changes:
		if (
			str(change.get("source_id", "")) == source_id
			and str(change.get("target_id", "")) == target_id
			and str(change.get("axis", "")) == axis
			and int(change.get("delta", 0)) == delta
		):
			return true
	return false


func _find_candidate_by_rule(candidates: Array, rule_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) == rule_id:
			return candidate
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 RELATIONSHIP TRACE RUMOR NARRATIVE FAIL] " + failure)
		print("[V5 RELATIONSHIP TRACE RUMOR NARRATIVE RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 RELATIONSHIP TRACE RUMOR NARRATIVE PASS] " + message)
	else:
		failures.append(message)
