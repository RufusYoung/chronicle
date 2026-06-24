extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
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
	var adapter = WorldTickAdapterModel.new()
	_check(adapter != null, "1. can create WorldTickAdapter")

	_check_missing_deferred_store(adapter)
	_check_after_patrol_tick(adapter)
	_check_unmatched_trigger_key(adapter)
	_check_contract_validator()

	_finish()


func _check_missing_deferred_store(adapter: Variant) -> void:
	var context = _context()
	var stores := _make_stores(context)
	stores.erase("deferred_consequence_store")
	var result: Dictionary = adapter.apply_tick_event(context, stores, _tick_event("after_patrol"))
	_check(
		not bool(result.get("success", true))
		and str(result.get("error_reason", "")) == "missing_deferred_consequence_store",
		"2. missing deferred_consequence_store returns failure without crash"
	)


func _check_after_patrol_tick(adapter: Variant) -> void:
	var context = _context()
	var stores := _make_stores(context)
	_run_delay_action(context, stores)

	var pending: Array = stores["deferred_consequence_store"].find_pending_consequences()
	_check(
		pending.size() == 1,
		"3. delay_military_issue_until_after_patrol produces pending deferred consequence"
	)
	_check(
		pending.size() == 1 and str((pending[0] as Dictionary).get("trigger_key", "")) == "after_patrol",
		"4. pending deferred consequence trigger_key is after_patrol"
	)

	var tick_result: Dictionary = adapter.apply_tick_event(context, stores, _tick_event("after_patrol"))
	_check(
		bool(tick_result.get("success", false))
		and int(tick_result.get("triggered_count", 0)) == 1,
		"5. apply_tick_event(\"after_patrol\") triggers the consequence"
	)
	_check(
		not stores["fact_store"].find_facts_by_type("deferred_consequence_triggered").is_empty(),
		"6. tick trigger writes deferred_consequence_triggered fact"
	)
	var triggered: Dictionary = stores["deferred_consequence_store"].find_deferred_consequence(
		"discipline_issue_after_patrol:outpost_kitchen"
	)
	_check(
		str(triggered.get("status", "")) == "triggered",
		"7. tick trigger sets deferred consequence status = triggered"
	)
	_check(
		stores["pressure_store"].get_pressure_value("outpost_kitchen", "unresolved_issue") >= 15,
		"8. tick trigger writes pressure change"
	)
	_check(
		int(tick_result.get("triggered_count", 0)) == 1,
		"9. tick result triggered_count = 1"
	)

	var entries: Array = tick_result.get("world_log_entries", [])
	var summary: Dictionary = tick_result.get("world_log_summary", {})
	_check(
		not entries.is_empty() and str((entries[0] as Dictionary).get("entry_type", "")) == "tick_event",
		"10. WorldLog has entry_type = tick_event"
	)
	_check(
		int(summary.get("tick_event_count", 0)) >= 1,
		"11. WorldLog summary.tick_event_count >= 1"
	)
	_check(
		int(summary.get("triggered_deferred_count", 0)) >= 1,
		"12. WorldLog summary.triggered_deferred_count >= 1"
	)

	var second_tick_result: Dictionary = adapter.apply_tick_event(context, stores, _tick_event("after_patrol"))
	_check(
		bool(second_tick_result.get("success", false))
		and int(second_tick_result.get("triggered_count", 0)) == 0,
		"13. second apply_tick_event(\"after_patrol\") does not retrigger triggered consequence"
	)


func _check_unmatched_trigger_key(adapter: Variant) -> void:
	var context = _context()
	var stores := _make_stores(context)
	_run_delay_action(context, stores)
	var tick_result: Dictionary = adapter.apply_tick_event(context, stores, _tick_event("after_meal"))
	_check(
		bool(tick_result.get("success", false))
		and int(tick_result.get("triggered_count", 0)) == 0
		and stores["deferred_consequence_store"].find_pending_consequences().size() == 1,
		"14. unmatched trigger_key does not trigger any consequence"
	)


func _check_contract_validator() -> void:
	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(_rules(), effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "15. RawRuleContractValidator still PASS")


func _run_delay_action(context: Variant, stores: Dictionary) -> void:
	var builder = SimSnapshotBuilderModel.new()
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()
	var snapshot = builder.build_snapshot(context, stores)
	var candidates: Array = affordance_system.generate_candidates(snapshot, _rules())
	var delay_candidate = _find_candidate(candidates, "delay_military_issue_until_after_patrol")
	var result = resolver.resolve_action(delay_candidate, snapshot)
	writer.apply_result(result, stores)


func _tick_event(trigger_key: String) -> Dictionary:
	return {
		"tick_event_id": "%s_event" % trigger_key,
		"tick_type": "test_event",
		"trigger_key": trigger_key,
		"scope_type": "location",
		"scope_id": "outpost_kitchen",
		"day": 1,
		"source": "test",
		"label": "tick event",
	}


func _context() -> Variant:
	var registry = SimRegistryModel.new()
	return SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))


func _rules() -> Array:
	var registry = SimRegistryModel.new()
	registry.load_action_rules([BASIC_RULES_PATH, DOMAIN_RULES_PATH, TEST_RULES_PATH])
	return registry.get_action_rules()


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


func _find_candidate(candidates: Array, rule_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) == rule_id:
			return candidate
	return null


func _finish() -> void:
	if failures.is_empty():
		print("[V5 MINI WORLD TICK ADAPTER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 MINI WORLD TICK ADAPTER FAIL] " + failure)
		print("[V5 MINI WORLD TICK ADAPTER RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 MINI WORLD TICK ADAPTER PASS] " + message)
	else:
		failures.append(message)
