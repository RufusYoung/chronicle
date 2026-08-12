extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const TEST_RULES_PATH := "res://data/sim/raw/action_rules/test_action_rules.json"
const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const RELATIONSHIP_AXIS_DEFS_PATH := "res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
const LAKE_TOWN_FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"
const TRANSACTION_RESOLVER_PATH := "res://scripts/sim/transaction/transaction_resolver.gd"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	var raw_rule_paths := [BASIC_RULES_PATH, DOMAIN_RULES_PATH, TEST_RULES_PATH]
	registry.load_action_rules(raw_rule_paths)
	var rules: Array = registry.get_action_rules()

	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(rules, effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "1. RawRuleContractValidator returns ok")

	_check(
		_rule_mode(rules, "hear_rumor_seed") == "effect_template",
		"2. hear_rumor_seed is effect_template"
	)
	_check(
		_rule_effect_template_id(rules, "hear_rumor_seed") == "hear_rumor_effect",
		"3. hear_rumor_seed binds hear_rumor_effect"
	)
	_check(
		_rule_mode(rules, "request_favor_from_indebted_person") == "effect_template",
		"4. request_favor_from_indebted_person is effect_template"
	)
	_check(
		_rule_effect_template_id(rules, "request_favor_from_indebted_person") == "request_favor_effect",
		"5. request_favor_from_indebted_person binds request_favor_effect"
	)
	_check(
		_rule_mode(rules, "ask_about_food_pressure_at_market") == "effect_template",
		"6. ask_about_food_pressure_at_market is effect_template"
	)
	_check(
		_rule_effect_template_id(rules, "ask_about_food_pressure_at_market") == "ask_market_pressure_effect",
		"7. ask_about_food_pressure_at_market binds ask_market_pressure_effect"
	)

	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()
	var snapshot_builder = SimSnapshotBuilderModel.new()

	var outpost_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var rumor_stores := _make_stores(outpost_context)
	var report_snapshot = snapshot_builder.build_snapshot(outpost_context, rumor_stores)
	var report_candidates: Array = affordance_system.generate_candidates(report_snapshot, rules)
	var report_candidate = _find_candidate(report_candidates, "report_discipline_violation_to_superior", "recruit_elai")
	writer.apply_result(resolver.resolve_action(report_candidate, report_snapshot), rumor_stores)

	var rumor_snapshot = snapshot_builder.build_snapshot(outpost_context, rumor_stores)
	var rumor_candidates: Array = affordance_system.generate_candidates(rumor_snapshot, rules)
	var hear_candidate = _find_candidate(rumor_candidates, "hear_rumor_seed", "outpost_discipline_report_seed")
	var hear_result = resolver.resolve_action(hear_candidate, rumor_snapshot)
	_check(_result_has_fact(hear_result, "actor_heard_rumor_seed"), "8. hear_rumor_seed produces actor_heard_rumor_seed fact")
	_check(_result_has_memory(hear_result, "player", "remembers_heard_rumor"), "9. hear_rumor_seed produces remembers_heard_rumor memory")
	_check(
		str(hear_candidate.label).begins_with("[传闻] 听听：")
		and str(hear_result.narrative_result.get("summary", ""))
			== "有人说，玩家把私藏口粮的事报告给了罗恩。",
		"10. 传闻候选显示具体主题，结算正文显示实际内容"
	)
	writer.apply_result(hear_result, rumor_stores)
	var heard_snapshot = snapshot_builder.build_snapshot(
		outpost_context,
		rumor_stores
	)
	var heard_candidates: Array = affordance_system.generate_candidates(
		heard_snapshot,
		rules
	)
	_check(
		_find_candidate(
			heard_candidates,
			"hear_rumor_seed",
			"outpost_discipline_report_seed"
		) == null,
		"11. 同一条传闻听过后不再生成可重复按钮"
	)

	var favor_stores := _make_stores(outpost_context)
	var conceal_snapshot = snapshot_builder.build_snapshot(outpost_context, favor_stores)
	var conceal_candidates: Array = affordance_system.generate_candidates(conceal_snapshot, rules)
	var conceal_candidate = _find_candidate(conceal_candidates, "conceal_discipline_violation_once", "recruit_elai")
	writer.apply_result(resolver.resolve_action(conceal_candidate, conceal_snapshot), favor_stores)

	var favor_snapshot = snapshot_builder.build_snapshot(outpost_context, favor_stores)
	var favor_candidates: Array = affordance_system.generate_candidates(favor_snapshot, rules)
	var favor_candidate = _find_candidate(favor_candidates, "request_favor_from_indebted_person", "recruit_elai")
	var favor_result = resolver.resolve_action(favor_candidate, favor_snapshot)
	_check(_result_has_fact(favor_result, "actor_requested_favor_from_target"), "12. request_favor produces actor_requested_favor_from_target fact")
	_check(_relationship_delta_exists(favor_result, "recruit_elai", "player", "debt", -5), "13. request_favor produces target -> player debt -5")
	_check(_result_has_memory(favor_result, "recruit_elai", "remembers_favor_requested"), "14. request_favor produces remembers_favor_requested memory")
	writer.apply_result(favor_result, favor_stores)
	var after_favor_snapshot = snapshot_builder.build_snapshot(
		outpost_context,
		favor_stores
	)
	var after_favor_candidates: Array = affordance_system.generate_candidates(
		after_favor_snapshot,
		rules
	)
	_check(
		_find_candidate(
			after_favor_candidates,
			"request_favor_from_indebted_person",
			"recruit_elai"
		) == null,
		"15. request_favor disappears after its first resolved use"
	)

	var lake_context = SimContextModel.new(registry.load_json(LAKE_TOWN_FIXTURE_PATH))
	var lake_candidates: Array = affordance_system.generate_candidates(lake_context, rules)
	var market_candidate = _find_candidate(lake_candidates, "ask_about_food_pressure_at_market")
	var market_result = resolver.resolve_action(market_candidate, lake_context)
	_check(_result_has_fact(market_result, "actor_asked_about_market_pressure"), "16. ask_market_pressure produces actor_asked_about_market_pressure fact")
	_check(_result_has_memory(market_result, "player", "learned_market_pressure"), "17. ask_market_pressure produces learned_market_pressure memory")

	_check(
		str(hear_result.contract_status) == "resolved"
		and str(favor_result.contract_status) == "resolved"
		and str(market_result.contract_status) == "resolved",
		"18. batch one results are resolved"
	)
	_check(_transaction_resolver_has_no_batch_one_rule_ids(), "19. batch one does not add TransactionResolver rule branches")
	_check(
		_rule_mode(rules, "approach_visible_person") == "effect_template"
		and _rule_effect_template_id(rules, "approach_visible_person")
			== "approach_person_effect",
		"20. approaching a person now resolves a visible one-shot result"
	)

	_finish()


func _make_stores(context: Variant) -> Dictionary:
	var state_store = StateStoreModel.new()
	state_store.load_from_context(context)
	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	return {
		"fact_store": FactStoreModel.new(),
		"state_store": state_store,
		"relationship_store": relationship_store,
		"memory_store": MemoryStoreModel.new(),
		"trace_store": TraceStoreModel.new(),
		"rumor_store": RumorStoreModel.new(),
	}


func _rule_mode(rules: Array, rule_id: String) -> String:
	for rule: Dictionary in rules:
		if str(rule.get("rule_id", "")) == rule_id:
			return str(rule.get("transaction_mode", ""))
	return ""


func _rule_effect_template_id(rules: Array, rule_id: String) -> String:
	for rule: Dictionary in rules:
		if str(rule.get("rule_id", "")) == rule_id:
			var value: Variant = rule.get("effect_template_id")
			return "" if value == null else str(value)
	return ""


func _find_candidate(candidates: Array, rule_id: String, target_id: String = "") -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) != rule_id:
			continue
		if target_id != "" and str(candidate.target_id) != target_id:
			continue
		return candidate
	return null


func _result_has_fact(result: Variant, fact_type: String) -> bool:
	for fact: Dictionary in result.facts_added:
		if str(fact.get("fact_type", "")) == fact_type:
			return true
	return false


func _result_has_memory(result: Variant, owner_id: String, memory_type: String) -> bool:
	for memory: Dictionary in result.memories_added:
		if (
			str(memory.get("owner_id", "")) == owner_id
			and str(memory.get("memory_type", "")) == memory_type
		):
			return true
	return false


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


func _transaction_resolver_has_no_batch_one_rule_ids() -> bool:
	var file := FileAccess.open(TRANSACTION_RESOLVER_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	return (
		text.find("hear_rumor_seed") == -1
		and text.find("request_favor_from_indebted_person") == -1
		and text.find("ask_about_food_pressure_at_market") == -1
	)


func _finish() -> void:
	if failures.is_empty():
		print("[V5 CANDIDATE EFFECT TEMPLATE BATCH1 RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 CANDIDATE EFFECT TEMPLATE BATCH1 FAIL] " + failure)
		print("[V5 CANDIDATE EFFECT TEMPLATE BATCH1 RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 CANDIDATE EFFECT TEMPLATE BATCH1 PASS] " + message)
	else:
		failures.append(message)
