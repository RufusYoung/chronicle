extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const ActionCandidateModel = preload("res://scripts/sim/action/action_candidate.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const TEST_RULES_PATH := "res://data/sim/raw/action_rules/test_action_rules.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry = SimRegistryModel.new()
	registry.load_action_rules([BASIC_RULES_PATH, DOMAIN_RULES_PATH, TEST_RULES_PATH])
	var rules: Array = registry.get_action_rules()
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()

	_check(
		_rule_effect_template_id(rules, "give_food_to_hungry_person") == "give_food_help_effect",
		"1. basic give_food_to_hungry_person carries give_food_help_effect"
	)
	_check(
		_rule_effect_template_id(rules, "ask_about_concealed_item") == "inquiry_concealed_item_effect",
		"2. basic ask_about_concealed_item carries inquiry_concealed_item_effect"
	)
	_check(
		_rule_effect_template_id(rules, "report_discipline_violation_to_superior") == "discipline_report_effect",
		"3. domain report_discipline_violation_to_superior carries discipline_report_effect"
	)

	var outpost_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var candidates: Array = affordance_system.generate_candidates(outpost_context, rules)
	var ask_candidate = _find_candidate(candidates, "ask_about_concealed_item", "recruit_elai")
	_check(
		ask_candidate != null
		and str(ask_candidate.effect_template_id) == "inquiry_concealed_item_effect"
		and str(ask_candidate.to_dict().get("effect_template_id", "")) == "inquiry_concealed_item_effect",
		"4. ActionCandidate carries effect_template_id"
	)

	var prefer_candidate = ActionCandidateModel.new({
		"action_id": "prefer_candidate_effect_template_probe:recruit_elai",
		"rule_id": "give_food_to_hungry_person",
		"action_type": "dialogue",
		"transaction_mode": "effect_template",
		"effect_template_id": "inquiry_concealed_item_effect",
		"target_id": "recruit_elai",
		"target_display_name": "recruit_elai",
	})
	var prefer_result = resolver.resolve_action(prefer_candidate, outpost_context)
	_check(
		_result_has_fact(prefer_result, "actor_asked_about_concealed_item")
		and not _result_has_fact(prefer_result, "actor_gave_food_to_target"),
		"5. TransactionResolver resolves candidate.effect_template_id instead of guessing from rule_id"
	)

	var alias_candidate = _find_candidate(candidates, "test_inquiry_concealed_item_alias", "recruit_elai")
	var alias_result = resolver.resolve_action(alias_candidate, outpost_context)
	_check(
		alias_candidate != null
		and str(alias_candidate.effect_template_id) == "inquiry_concealed_item_effect"
		and _result_has_fact(alias_result, "actor_asked_about_concealed_item"),
		"6. test_inquiry_concealed_item_alias executes without TransactionResolver rule mapping"
	)
	_check(
		_result_has_memory(alias_result, "recruit_elai", "being_questioned_about_hidden_item"),
		"7. test alias produces being_questioned_about_hidden_item memory"
	)
	_check(
		_relationship_delta_exists(alias_result, "recruit_elai", "player", "fear", 5),
		"8. test alias produces fear +5"
	)

	var no_effect_candidate = ActionCandidateModel.new({
		"action_id": "raw_rule_no_effect_probe:recruit_elai",
		"rule_id": "raw_rule_no_effect_probe",
		"action_type": "test",
		"transaction_mode": "candidate_only",
		"effect_template_id": "",
		"target_id": "recruit_elai",
		"target_display_name": "recruit_elai",
	})
	var no_effect_result = resolver.resolve_action(no_effect_candidate, outpost_context)
	_check(
		no_effect_result != null
		and no_effect_result.is_empty()
		and str(no_effect_result.contract_status) == "candidate_only",
		"9. candidate_only returns an empty transaction result safely"
	)

	_finish()


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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 RAW RULE EFFECT BINDING RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 RAW RULE EFFECT BINDING FAIL] " + failure)
		print("[V5 RAW RULE EFFECT BINDING RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 RAW RULE EFFECT BINDING PASS] " + message)
	else:
		failures.append(message)
