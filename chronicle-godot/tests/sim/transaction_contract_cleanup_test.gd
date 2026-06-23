extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ActionCandidateModel = preload("res://scripts/sim/action/action_candidate.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const TEST_RULES_PATH := "res://data/sim/raw/action_rules/test_action_rules.json"
const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"
const SEVENTH_OUTPOST_CONCEAL_SCENARIO_PATH := "res://data/sim/fixtures/scenarios/seventh_outpost_conceal_sequence.json"

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

	_check(
		_all_rules_have_transaction_mode(registry.load_json(BASIC_RULES_PATH).get("rules", [])),
		"1. all basic_action_rules have transaction_mode"
	)
	_check(
		_all_rules_have_transaction_mode(registry.load_json(DOMAIN_RULES_PATH).get("rules", [])),
		"2. all domain_action_rules have transaction_mode"
	)
	_check(
		_all_rules_have_transaction_mode(registry.load_json(TEST_RULES_PATH).get("rules", [])),
		"3. all test_action_rules have transaction_mode"
	)
	_check(
		_all_effect_template_rules_have_ids(rules),
		"4. effect_template mode requires effect_template_id"
	)
	_check(
		_all_candidate_only_rules_have_no_ids(rules),
		"5. candidate_only mode has no effect_template_id"
	)
	_check(
		_all_effect_template_ids_exist(rules, effect_resolver.templates),
		"6. effect_template_id exists in basic_effect_templates.json"
	)

	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(rules, effect_resolver.templates)
	_check(
		bool(validation.get("ok", false)),
		"7. RawRuleContractValidator returns ok for current rules"
	)

	var outpost_context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var affordance_system = ActionAffordanceModel.new()
	var candidates: Array = affordance_system.generate_candidates(outpost_context, rules)
	var ask_candidate = _find_candidate(candidates, "ask_about_concealed_item", "recruit_elai")
	_check(
		ask_candidate != null
		and str(ask_candidate.transaction_mode) == "effect_template"
		and str(ask_candidate.to_dict().get("transaction_mode", "")) == "effect_template",
		"8. ActionCandidate carries transaction_mode"
	)

	var resolver = TransactionResolverModel.new()
	var ask_result = resolver.resolve_action(ask_candidate, outpost_context)
	_check(
		str(ask_result.contract_status) == "resolved"
		and str(ask_result.transaction_mode) == "effect_template"
		and _result_has_fact(ask_result, "actor_asked_about_concealed_item"),
		"9. TransactionResolver returns resolved for effect_template mode"
	)

	var candidate_only_candidate = _find_candidate(candidates, "approach_visible_person", "recruit_elai")
	var candidate_only_result = resolver.resolve_action(candidate_only_candidate, outpost_context)
	_check(
		str(candidate_only_result.contract_status) == "candidate_only"
		and str(candidate_only_result.skip_reason) == "candidate_only_rule",
		"10. TransactionResolver returns candidate_only for approach_visible_person"
	)
	_check(
		candidate_only_result.is_empty()
		and candidate_only_result.facts_added.is_empty()
		and candidate_only_result.state_changes.is_empty()
		and candidate_only_result.relationship_changes.is_empty()
		and candidate_only_result.memories_added.is_empty()
		and candidate_only_result.traces_added.is_empty()
		and candidate_only_result.rumors_added.is_empty(),
		"11. candidate_only does not write facts / state / relationship / memory / trace / rumor"
	)

	var invalid_candidate = ActionCandidateModel.new({
		"action_id": "invalid_missing_effect_template_id:recruit_elai",
		"rule_id": "invalid_missing_effect_template_id",
		"action_type": "test",
		"transaction_mode": "effect_template",
		"effect_template_id": "",
		"target_id": "recruit_elai",
		"target_display_name": "recruit_elai",
	})
	var invalid_result = resolver.resolve_action(invalid_candidate, outpost_context)
	_check(
		str(invalid_result.contract_status) == "invalid_contract"
		and str(invalid_result.error_reason) == "missing_effect_template_id"
		and invalid_result.is_empty(),
		"12. missing effect_template_id returns invalid_contract without legacy fallback"
	)

	var alias_candidate = _find_candidate(candidates, "test_inquiry_concealed_item_alias", "recruit_elai")
	var alias_result = resolver.resolve_action(alias_candidate, outpost_context)
	_check(
		alias_candidate != null
		and str(alias_result.contract_status) == "resolved"
		and _result_has_fact(alias_result, "actor_asked_about_concealed_item"),
		"13. test_inquiry_concealed_item_alias still executes without Resolver rule mapping"
	)

	var runner = SimRunnerModel.new()
	var runner_result: Dictionary = runner.run_sequence(
		SEVENTH_OUTPOST_FIXTURE_PATH,
		SEVENTH_OUTPOST_CONCEAL_SCENARIO_PATH,
		[BASIC_RULES_PATH, DOMAIN_RULES_PATH]
	)
	var world_log: Array = runner_result.get("world_log", [])
	var first_entry: Dictionary = world_log[0] if not world_log.is_empty() else {}
	_check(
		bool(runner_result.get("success", false))
		and str(first_entry.get("transaction_mode", "")) == "effect_template"
		and str(first_entry.get("contract_status", "")) == "resolved",
		"14. SimRunner WorldLog records transaction_mode and contract_status"
	)

	var manual_log = SimWorldLogModel.new()
	manual_log.append_entry({"contract_status": "resolved"})
	manual_log.append_entry({"contract_status": "candidate_only"})
	manual_log.append_entry({"contract_status": "invalid_contract"})
	var manual_summary: Dictionary = manual_log.summary()
	_check(
		int(manual_summary.get("resolved_count", 0)) == 1
		and int(manual_summary.get("candidate_only_count", 0)) == 1
		and int(manual_summary.get("invalid_contract_count", 0)) == 1,
		"15. SimWorldLog summary counts resolved / candidate_only / invalid_contract"
	)

	_finish()


func _all_rules_have_transaction_mode(rules: Array) -> bool:
	for rule: Dictionary in rules:
		if not rule.has("transaction_mode"):
			return false
		if str(rule.get("transaction_mode", "")) == "":
			return false
	return true


func _all_effect_template_rules_have_ids(rules: Array) -> bool:
	for rule: Dictionary in rules:
		if str(rule.get("transaction_mode", "")) != "effect_template":
			continue
		if _optional_string(rule.get("effect_template_id")) == "":
			return false
	return true


func _all_candidate_only_rules_have_no_ids(rules: Array) -> bool:
	for rule: Dictionary in rules:
		if str(rule.get("transaction_mode", "")) != "candidate_only":
			continue
		if _optional_string(rule.get("effect_template_id")) != "":
			return false
	return true


func _all_effect_template_ids_exist(rules: Array, effect_templates: Dictionary) -> bool:
	for rule: Dictionary in rules:
		if str(rule.get("transaction_mode", "")) != "effect_template":
			continue
		if not effect_templates.has(_optional_string(rule.get("effect_template_id"))):
			return false
	return true


func _optional_string(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)


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


func _finish() -> void:
	if failures.is_empty():
		print("[V5 TRANSACTION CONTRACT CLEANUP RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 TRANSACTION CONTRACT CLEANUP FAIL] " + failure)
		print("[V5 TRANSACTION CONTRACT CLEANUP RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 TRANSACTION CONTRACT CLEANUP PASS] " + message)
	else:
		failures.append(message)
