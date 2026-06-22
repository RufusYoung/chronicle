extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
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

	var fact_store = FactStoreModel.new()
	var state_store = StateStoreModel.new()
	var relationship_store = RelationshipStoreModel.new()
	var memory_store = MemoryStoreModel.new()

	var lake_context = SimContextModel.new(registry.load_json(LAKE_TOWN_FIXTURE_PATH))
	state_store.load_from_context(lake_context)
	var lake_candidates: Array = affordance_system.generate_candidates(lake_context, rules)
	var give_food_candidate = _find_candidate_by_rule(lake_candidates, "give_food_to_hungry_person")
	var give_food_result = resolver.resolve_action(give_food_candidate, lake_context)
	_apply_result(give_food_result, fact_store, state_store, relationship_store, memory_store)

	_check(
		not fact_store.find_facts_by_type("actor_gave_food_to_target").is_empty(),
		"1. 给陈米食物后写入 actor_gave_food_to_target"
	)
	_check(
		state_store.get_state("chen_mi", "hunger") == "medium",
		"2. 给陈米食物后 hunger 从 high 降为 medium"
	)
	_check(
		int(relationship_store.get_relation("chen_mi", "player", "gratitude")) == 15,
		"3. 给陈米食物后 chen_mi -> player gratitude 增加"
	)
	_check(
		not memory_store.find_memories_by_type("chen_mi", "received_help").is_empty(),
		"4. 给陈米食物后生成 received_help memory"
	)

	var outpost_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	state_store.load_from_context(outpost_context)
	var outpost_candidates: Array = affordance_system.generate_candidates(outpost_context, rules)

	var report_candidate = _find_candidate_by_rule(outpost_candidates, "report_discipline_violation_to_superior")
	var report_result = resolver.resolve_action(report_candidate, outpost_context)
	_apply_result(report_result, fact_store, state_store, relationship_store, memory_store)

	_check(
		not fact_store.find_facts_by_type("actor_reported_discipline_violation").is_empty(),
		"5. 报告伊莱后写入 actor_reported_discipline_violation"
	)
	_check(
		int(relationship_store.get_relation("recruit_elai", "player", "resentment")) == 25,
		"6. 报告伊莱后 recruit_elai -> player resentment 增加"
	)
	_check(
		int(relationship_store.get_relation("captain_ron", "player", "discipline_respect")) == 15,
		"7. 报告伊莱后 captain_ron -> player discipline_respect 增加"
	)

	var trust_before_conceal := int(relationship_store.get_relation("recruit_elai", "player", "trust"))
	var conceal_candidate = _find_candidate_by_rule(outpost_candidates, "conceal_discipline_violation_once")
	var conceal_result = resolver.resolve_action(conceal_candidate, outpost_context)
	_apply_result(conceal_result, fact_store, state_store, relationship_store, memory_store)

	_check(
		int(relationship_store.get_relation("recruit_elai", "player", "trust")) == trust_before_conceal + 15,
		"8. 替伊莱隐瞒后 recruit_elai -> player trust 增加"
	)
	_check(
		not memory_store.find_memories_by_type("recruit_elai", "being_protected").is_empty(),
		"9. 替伊莱隐瞒后生成 being_protected memory"
	)

	_finish()


func _apply_result(
	result: Variant,
	fact_store: Variant,
	state_store: Variant,
	relationship_store: Variant,
	memory_store: Variant
) -> void:
	for fact: Dictionary in result.facts_added:
		fact_store.add_fact(fact)
	for state_change: Dictionary in result.state_changes:
		state_store.apply_state_change(state_change)
	for relationship_change: Dictionary in result.relationship_changes:
		relationship_store.apply_relationship_change(relationship_change)
	for memory: Dictionary in result.memories_added:
		memory_store.add_memory(memory)


func _find_candidate_by_rule(candidates: Array, rule_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) == rule_id:
			return candidate
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 TRANSACTION STATE MEMORY RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 TRANSACTION STATE MEMORY FAIL] " + failure)
		print("[V5 TRANSACTION STATE MEMORY RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 TRANSACTION STATE MEMORY PASS] " + message)
	else:
		failures.append(message)
