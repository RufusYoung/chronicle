extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
const DueResolutionPolicyModel = preload("res://scripts/sim/consequence/due_resolution_policy.gd")
const DueResolutionSystemModel = preload("res://scripts/sim/consequence/due_resolution_system.gd")
const WorldTickAdapterModel = preload("res://scripts/sim/world_tick/world_tick_adapter.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")
const PressureStoreModel = preload("res://scripts/sim/pressure/pressure_store.gd")
const ObligationStoreModel = preload("res://scripts/sim/obligation/obligation_store.gd")
const ExchangeStoreModel = preload("res://scripts/sim/exchange/exchange_store.gd")
const DeferredConsequenceStoreModel = preload("res://scripts/sim/deferred/deferred_consequence_store.gd")

const BASIC_RULES_PATH := "res://data/sim/raw/action_rules/basic_action_rules.json"
const DOMAIN_RULES_PATH := "res://data/sim/raw/action_rules/domain_action_rules.json"
const TEST_RULES_PATH := "res://data/sim/raw/action_rules/test_action_rules.json"
const EFFECT_TEMPLATES_PATH := "res://data/sim/raw/effect_templates/basic_effect_templates.json"
const RELATIONSHIP_AXIS_DEFS_PATH := "res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
const SEVENTH_OUTPOST_FIXTURE_PATH := "res://data/sim/fixtures/seventh_outpost_ration_fixture.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_policy_validation()
	_check_due_setup()
	_check_obligation_resolution()
	_check_exchange_resolution()
	_check_keep_due_and_invalid_targets()
	_check_world_log_summary()
	_check_contract_validator()
	_finish()


func _check_policy_validation() -> void:
	var policy = DueResolutionPolicyModel.new()
	_check(
		bool(policy.validate(_decision("policy_obl_fulfilled", "obligation", "obl_a", "fulfilled")).get("ok", false)),
		"1. DueResolutionPolicy validates obligation fulfilled decision"
	)
	_check(
		bool(policy.validate(_decision("policy_obl_breached", "obligation", "obl_a", "breached")).get("ok", false)),
		"2. DueResolutionPolicy validates obligation breached decision"
	)
	_check(
		bool(policy.validate(_decision("policy_ex_settled", "exchange", "ex_a", "settled")).get("ok", false)),
		"3. DueResolutionPolicy validates exchange settled decision"
	)
	_check(
		bool(policy.validate(_decision("policy_ex_failed", "exchange", "ex_a", "failed")).get("ok", false)),
		"4. DueResolutionPolicy validates exchange failed decision"
	)
	_check(
		not bool(policy.validate(_decision("policy_bad_obl", "obligation", "obl_a", "settled")).get("ok", true)),
		"5. obligation + settled decision is invalid"
	)
	_check(
		not bool(policy.validate(_decision("policy_bad_ex", "exchange", "ex_a", "breached")).get("ok", true)),
		"6. exchange + breached decision is invalid"
	)
	var missing_target := _decision("policy_missing_target", "obligation", "", "fulfilled")
	_check(
		not bool(policy.validate(missing_target).get("ok", true)),
		"7. missing target_id decision is invalid"
	)


func _check_due_setup() -> void:
	var world := _make_due_world()
	var stores: Dictionary = world.get("stores", {})
	_check(
		stores["obligation_store"].list_obligations().size() == 1
		and stores["exchange_store"].list_exchanges().size() == 1,
		"8. trade_watch_duty_for_silence creates obligation and exchange"
	)
	_check(
		str(_first_obligation(stores).get("due_status", "")) == "due"
		and str(_first_exchange(stores).get("due_status", "")) == "due",
		"9. tick_event include_due_checks=true sets obligation and exchange due_status = due"
	)


func _check_obligation_resolution() -> void:
	var fulfilled_world := _make_due_world()
	var fulfilled_context: Variant = fulfilled_world.get("context")
	var fulfilled_stores: Dictionary = fulfilled_world.get("stores", {})
	var fulfilled_obligation_id := str(_first_obligation(fulfilled_stores).get("obligation_id", ""))
	var system = DueResolutionSystemModel.new()
	var writer = TransactionWorldWriterModel.new()
	var fulfilled_decision := _decision(
		"resolve_obl_fulfilled",
		"obligation",
		fulfilled_obligation_id,
		"fulfilled"
	)
	var fulfilled_result = system.resolve_due(
		_snapshot(fulfilled_context, fulfilled_stores),
		fulfilled_decision
	)
	_check(
		_result_has_fact(fulfilled_result, "obligation_fulfilled"),
		"10. DueResolutionSystem fulfilled obligation creates obligation_fulfilled fact"
	)
	_check(
		str(_first_obligation(fulfilled_stores).get("status", "")) == "open"
		and str(_first_obligation(fulfilled_stores).get("due_status", "")) == "due",
		"11. DueResolutionSystem does not directly write Store"
	)
	writer.apply_result(fulfilled_result, fulfilled_stores)
	var fulfilled_obligation: Dictionary = _first_obligation(fulfilled_stores)
	_check(
		str(fulfilled_obligation.get("status", "")) == "fulfilled",
		"12. fulfilled writeback sets obligation.status = fulfilled"
	)
	_check(
		str(fulfilled_obligation.get("due_status", "")) == "resolved"
		and str(fulfilled_obligation.get("resolution_status", "")) == "fulfilled"
		and int(fulfilled_obligation.get("resolution_count", 0)) == 1,
		"13. fulfilled writeback sets due_status = resolved and resolution fields"
	)

	var breached_world := _make_due_world()
	var breached_context: Variant = breached_world.get("context")
	var breached_stores: Dictionary = breached_world.get("stores", {})
	var breached_obligation_id := str(_first_obligation(breached_stores).get("obligation_id", ""))
	var breached_decision := _decision(
		"resolve_obl_breached",
		"obligation",
		breached_obligation_id,
		"breached"
	)
	var breached_result = system.resolve_due(
		_snapshot(breached_context, breached_stores),
		breached_decision
	)
	_check(
		_result_has_fact(breached_result, "obligation_breached"),
		"14. DueResolutionSystem breached obligation creates obligation_breached fact"
	)
	writer.apply_result(breached_result, breached_stores)
	_check(
		str(_first_obligation(breached_stores).get("status", "")) == "breached"
		and str(_first_obligation(breached_stores).get("due_status", "")) == "resolved",
		"15. breached writeback sets obligation.status = breached and due_status = resolved"
	)


func _check_exchange_resolution() -> void:
	var system = DueResolutionSystemModel.new()
	var writer = TransactionWorldWriterModel.new()

	var settled_world := _make_due_world()
	var settled_context: Variant = settled_world.get("context")
	var settled_stores: Dictionary = settled_world.get("stores", {})
	var settled_exchange_id := str(_first_exchange(settled_stores).get("exchange_id", ""))
	var settled_result = system.resolve_due(
		_snapshot(settled_context, settled_stores),
		_decision("resolve_ex_settled", "exchange", settled_exchange_id, "settled")
	)
	_check(
		_result_has_fact(settled_result, "exchange_settled"),
		"16. DueResolutionSystem settled exchange creates exchange_settled fact"
	)
	writer.apply_result(settled_result, settled_stores)
	_check(
		str(_first_exchange(settled_stores).get("status", "")) == "settled"
		and str(_first_exchange(settled_stores).get("due_status", "")) == "resolved",
		"17. settled writeback sets exchange.status = settled and due_status = resolved"
	)

	var failed_world := _make_due_world()
	var failed_context: Variant = failed_world.get("context")
	var failed_stores: Dictionary = failed_world.get("stores", {})
	var failed_exchange_id := str(_first_exchange(failed_stores).get("exchange_id", ""))
	var failed_result = system.resolve_due(
		_snapshot(failed_context, failed_stores),
		_decision("resolve_ex_failed", "exchange", failed_exchange_id, "failed")
	)
	_check(
		_result_has_fact(failed_result, "exchange_failed"),
		"18. DueResolutionSystem failed exchange creates exchange_failed fact"
	)
	writer.apply_result(failed_result, failed_stores)
	_check(
		str(_first_exchange(failed_stores).get("status", "")) == "failed"
		and str(_first_exchange(failed_stores).get("due_status", "")) == "resolved"
		and str(_first_exchange(failed_stores).get("resolution_status", "")) == "failed",
		"19. failed writeback sets exchange.status = failed and resolution fields"
	)


func _check_keep_due_and_invalid_targets() -> void:
	var system = DueResolutionSystemModel.new()
	var writer = TransactionWorldWriterModel.new()

	var keep_world := _make_due_world()
	var keep_context: Variant = keep_world.get("context")
	var keep_stores: Dictionary = keep_world.get("stores", {})
	var keep_obligation_id := str(_first_obligation(keep_stores).get("obligation_id", ""))
	var keep_result = system.resolve_due(
		_snapshot(keep_context, keep_stores),
		_decision("resolve_keep_due", "obligation", keep_obligation_id, "keep_due")
	)
	writer.apply_result(keep_result, keep_stores)
	var kept_obligation: Dictionary = _first_obligation(keep_stores)
	_check(
		_result_has_fact(keep_result, "due_resolution_kept_pending")
		and str(kept_obligation.get("status", "")) == "open"
		and str(kept_obligation.get("due_status", "")) == "due"
		and str(kept_obligation.get("resolution_status", "")) == "keep_due",
		"20. keep_due records pending resolution without changing main status"
	)

	var not_due_context = _context()
	var not_due_stores := _make_stores(not_due_context)
	_run_trade_action(not_due_context, not_due_stores)
	var not_due_obligation_id := str(_first_obligation(not_due_stores).get("obligation_id", ""))
	var not_due_result = system.resolve_due(
		_snapshot(not_due_context, not_due_stores),
		_decision("resolve_not_due", "obligation", not_due_obligation_id, "fulfilled")
	)
	_check(
		str(not_due_result.contract_status) == "invalid_contract"
		and str(not_due_result.error_reason).begins_with("target_not_due"),
		"21. non-due obligation cannot be resolved"
	)

	var closed_world := _make_due_world()
	var closed_context: Variant = closed_world.get("context")
	var closed_stores: Dictionary = closed_world.get("stores", {})
	var closed_obligation_id := str(_first_obligation(closed_stores).get("obligation_id", ""))
	var close_result = system.resolve_due(
		_snapshot(closed_context, closed_stores),
		_decision("resolve_closed_once", "obligation", closed_obligation_id, "fulfilled")
	)
	writer.apply_result(close_result, closed_stores)
	var repeat_result = system.resolve_due(
		_snapshot(closed_context, closed_stores),
		_decision("resolve_closed_twice", "obligation", closed_obligation_id, "breached")
	)
	_check(
		str(repeat_result.contract_status) == "invalid_contract"
		and str(repeat_result.error_reason).begins_with("target_not_open"),
		"22. already fulfilled obligation cannot be resolved again"
	)
	_check(
		int(_first_obligation(closed_stores).get("resolution_count", 0)) == 1,
		"23. TransactionWorldWriter writes resolution_count updates exactly once"
	)


func _check_world_log_summary() -> void:
	var world_log = SimWorldLogModel.new()
	world_log.append_entry(_resolution_entry("log_obl_fulfilled", "obligation", "obl_a", "fulfilled"))
	world_log.append_entry(_resolution_entry("log_obl_breached", "obligation", "obl_b", "breached"))
	world_log.append_entry(_resolution_entry("log_ex_settled", "exchange", "ex_a", "settled"))
	world_log.append_entry(_resolution_entry("log_ex_failed", "exchange", "ex_b", "failed"))
	world_log.append_entry(_resolution_entry("log_keep_due", "obligation", "obl_c", "keep_due"))
	var summary: Dictionary = world_log.summary()
	_check(
		int(summary.get("due_resolution_count", 0)) == 5
		and int(summary.get("obligation_fulfilled_count", 0)) == 1
		and int(summary.get("obligation_breached_count", 0)) == 1
		and int(summary.get("exchange_settled_count", 0)) == 1
		and int(summary.get("exchange_failed_count", 0)) == 1
		and int(summary.get("keep_due_count", 0)) == 1,
		"24. WorldLog summarizes due resolution entries"
	)


func _check_contract_validator() -> void:
	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(_rules(), effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "25. RawRuleContractValidator still PASS")


func _make_due_world() -> Dictionary:
	var context = _context()
	var stores := _make_stores(context)
	_run_trade_action(context, stores)
	var adapter = WorldTickAdapterModel.new()
	adapter.apply_tick_event(context, stores, _due_tick_event("tick_due_resolution_setup"))
	return {
		"context": context,
		"stores": stores,
	}


func _run_trade_action(context: Variant, stores: Dictionary) -> void:
	var snapshot = _snapshot(context, stores)
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()
	var candidates: Array = affordance_system.generate_candidates(snapshot, _rules())
	var trade_candidate = _find_candidate(candidates, "trade_watch_duty_for_silence", "recruit_elai")
	var result = resolver.resolve_action(trade_candidate, snapshot)
	writer.apply_result(result, stores)


func _due_tick_event(tick_event_id: String) -> Dictionary:
	return {
		"tick_event_id": tick_event_id,
		"tick_type": "test_event",
		"trigger_key": "tonight_watch",
		"scope_type": "location",
		"scope_id": "outpost_kitchen",
		"day": 1,
		"time_key": "tonight_watch",
		"source": "test",
		"label": "due resolution setup tick",
		"include_due_checks": true,
	}


func _decision(
	resolution_id: String,
	target_kind: String,
	target_id: String,
	resolution: String
) -> Dictionary:
	return {
		"resolution_id": resolution_id,
		"target_kind": target_kind,
		"target_id": target_id,
		"resolution": resolution,
		"reason": "manual_test_policy",
		"source": "test",
		"resolver_actor_id": "test_resolver",
		"tick_event_id": "tick_due_resolution_setup",
		"trigger_key": "tonight_watch",
		"scope_type": "location",
		"scope_id": "outpost_kitchen",
	}


func _resolution_entry(
	resolution_id: String,
	target_kind: String,
	target_id: String,
	resolution: String
) -> Dictionary:
	return {
		"entry_type": "due_resolution",
		"resolution_id": resolution_id,
		"target_kind": target_kind,
		"target_id": target_id,
		"resolution": resolution,
		"resolution_status": resolution,
		"contract_status": "resolved",
		"rule_id": "due_resolution_system",
	}


func _context() -> Variant:
	var registry = SimRegistryModel.new()
	return SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))


func _rules() -> Array:
	var registry = SimRegistryModel.new()
	registry.load_action_rules([BASIC_RULES_PATH, DOMAIN_RULES_PATH, TEST_RULES_PATH])
	return registry.get_action_rules()


func _snapshot(context: Variant, stores: Dictionary) -> Variant:
	var builder = SimSnapshotBuilderModel.new()
	return builder.build_snapshot(context, stores)


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
		"pressure_store": PressureStoreModel.new(),
		"obligation_store": ObligationStoreModel.new(),
		"exchange_store": ExchangeStoreModel.new(),
		"deferred_consequence_store": DeferredConsequenceStoreModel.new(),
	}


func _first_obligation(stores: Dictionary) -> Dictionary:
	var obligations: Array = stores["obligation_store"].list_obligations()
	return (obligations[0] as Dictionary).duplicate(true) if not obligations.is_empty() else {}


func _first_exchange(stores: Dictionary) -> Dictionary:
	var exchanges: Array = stores["exchange_store"].list_exchanges()
	return (exchanges[0] as Dictionary).duplicate(true) if not exchanges.is_empty() else {}


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
		print("[V5 DUE RESOLUTION POLICY RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 DUE RESOLUTION POLICY FAIL] " + failure)
		print("[V5 DUE RESOLUTION POLICY RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 DUE RESOLUTION POLICY PASS] " + message)
	else:
		failures.append(message)
