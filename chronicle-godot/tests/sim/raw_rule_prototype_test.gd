extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")

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
	_check(
		rules.size() >= 11
		and _rules_include(rules, "give_food_to_hungry_person")
		and _rules_include(rules, "report_discipline_violation_to_superior"),
		"1. 能加载 raw action rules"
	)

	var lake_fixture: Dictionary = registry.load_json(LAKE_TOWN_FIXTURE_PATH)
	_check(
		lake_fixture.get("fixture_id", "") == "lake_town_food_crisis",
		"2. 能加载 lake_town_food_crisis_fixture"
	)
	_check(
		not lake_fixture.has("actions"),
		"4. 湖湾镇不依赖 fixture.actions"
	)

	var lake_context = SimContextModel.new(lake_fixture)
	var affordance_system = ActionAffordanceModel.new()
	var lake_candidates: Array = affordance_system.generate_candidates(lake_context, rules)
	var lake_rule_ids := _candidate_rule_ids(lake_candidates)
	_check(
		_all_present(lake_rule_ids, [
			"approach_visible_person",
			"give_food_to_hungry_person",
			"ask_about_concealed_item",
			"read_visible_readable_object",
			"inspect_visible_trace",
		]),
		"3. 湖湾镇能生成基础行动"
	)

	var outpost_fixture: Dictionary = registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH)
	_check(
		outpost_fixture.get("fixture_id", "") == "seventh_outpost_ration",
		"5. 能加载 seventh_outpost_ration_fixture"
	)
	_check(
		not outpost_fixture.has("actions"),
		"5a. 第七哨站不依赖 fixture.actions"
	)

	var outpost_context = SimContextModel.new(outpost_fixture)
	var outpost_candidates: Array = affordance_system.generate_candidates(outpost_context, rules)
	var outpost_rule_ids := _candidate_rule_ids(outpost_candidates)
	_check(
		_all_present(outpost_rule_ids, [
			"approach_visible_person",
			"give_food_to_hungry_person",
			"ask_about_concealed_item",
			"read_visible_readable_object",
			"inspect_visible_trace",
		]),
		"6. 第七哨站能生成基础行动"
	)

	var outpost_military_rule_ids := _candidate_rule_ids_by_domain(outpost_candidates, "military_discipline")
	_check(
		outpost_military_rule_ids.size() >= 3
		and "report_discipline_violation_to_superior" in outpost_military_rule_ids
		and "conceal_discipline_violation_once" in outpost_military_rule_ids
		and "confirm_ration_record_with_cook" in outpost_military_rule_ids,
		"7. 第七哨站能生成至少 3 个军纪 / 口粮领域行动"
	)

	var lake_military_rule_ids := _candidate_rule_ids_by_domain(lake_candidates, "military_discipline")
	_check(
		lake_military_rule_ids.is_empty()
		and outpost_military_rule_ids.size() > lake_military_rule_ids.size(),
		"8. 第七哨站行动不是湖湾镇换壳"
	)

	var resolver = TransactionResolverModel.new()
	var fact_store = FactStoreModel.new()

	var give_food_candidate = _find_candidate_by_rule(lake_candidates, "give_food_to_hungry_person")
	var give_food_result = resolver.resolve_action(give_food_candidate, lake_context)
	for fact: Dictionary in give_food_result.facts_added:
		fact_store.add_fact(fact)
	_check(
		not fact_store.find_facts_by_type("actor_gave_food_to_target").is_empty(),
		"9. 执行 give_food_to_hungry_person 后 FactStore 出现 actor_gave_food_to_target"
	)

	var report_candidate = _find_candidate_by_rule(outpost_candidates, "report_discipline_violation_to_superior")
	var report_result = resolver.resolve_action(report_candidate, outpost_context)
	for fact: Dictionary in report_result.facts_added:
		fact_store.add_fact(fact)
	_check(
		not fact_store.find_facts_by_type("actor_reported_discipline_violation").is_empty(),
		"10. 执行 report_discipline_violation_to_superior 后 FactStore 出现 actor_reported_discipline_violation"
	)

	_finish()


func _rules_include(rules: Array, rule_id: String) -> bool:
	for rule: Dictionary in rules:
		if str(rule.get("rule_id", "")) == rule_id:
			return true
	return false


func _candidate_rule_ids(candidates: Array) -> Array[String]:
	var ids: Array[String] = []
	for candidate: Variant in candidates:
		ids.append(str(candidate.rule_id))
	return ids


func _candidate_rule_ids_by_domain(candidates: Array, domain: String) -> Array[String]:
	var ids: Array[String] = []
	for candidate: Variant in candidates:
		if str(candidate.domain) == domain:
			ids.append(str(candidate.rule_id))
	return ids


func _all_present(values: Array, expected_values: Array) -> bool:
	for expected: String in expected_values:
		if expected not in values:
			return false
	return true


func _find_candidate_by_rule(candidates: Array, rule_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) == rule_id:
			return candidate
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RAW RULE PROTOTYPE RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 RAW RULE PROTOTYPE FAIL] " + failure)
		print("[V5 RAW RULE PROTOTYPE RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 RAW RULE PROTOTYPE PASS] " + message)
	else:
		failures.append(message)
