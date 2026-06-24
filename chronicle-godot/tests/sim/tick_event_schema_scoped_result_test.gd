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
const TickEventSchemaModel = preload("res://scripts/sim/world_tick/tick_event_schema.gd")
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
	_check_schema()
	_check_invalid_tick_event_does_not_crash()
	_check_scoped_tick_from_delay_action()
	_check_different_scope_does_not_trigger()
	_check_global_scope_matches_all_scopes()
	_check_max_triggers()
	_check_world_log_queries()
	_check_contract_validator()
	_finish()


func _check_schema() -> void:
	var schema = TickEventSchemaModel.new()
	var valid: Dictionary = schema.validate(_tick_event("schema_valid", "location", "outpost_kitchen"))
	_check(
		bool(valid.get("ok", false))
		and str((valid.get("event", {}) as Dictionary).get("tick_type", "")) == "test_event",
		"1. TickEventSchema validates a legal tick_event"
	)

	var missing_id := _tick_event("", "location", "outpost_kitchen")
	_check(
		not bool(schema.validate(missing_id).get("ok", true))
		and "missing_tick_event_id" in (schema.validate(missing_id).get("errors", []) as Array),
		"2. missing tick_event_id fails validation"
	)

	var missing_trigger := _tick_event("missing_trigger_probe", "location", "outpost_kitchen")
	missing_trigger.erase("trigger_key")
	_check(
		not bool(schema.validate(missing_trigger).get("ok", true))
		and "missing_trigger_key" in (schema.validate(missing_trigger).get("errors", []) as Array),
		"3. missing trigger_key fails validation"
	)

	var missing_scope_id := _tick_event("missing_scope_id_probe", "location", "")
	missing_scope_id.erase("scope_id")
	_check(
		not bool(schema.validate(missing_scope_id).get("ok", true))
		and "missing_scope_id" in (schema.validate(missing_scope_id).get("errors", []) as Array),
		"4. non-global scope without scope_id fails validation"
	)

	var bad_limit := _tick_event("bad_limit_probe", "location", "outpost_kitchen")
	bad_limit["max_triggers"] = -1
	_check(
		not bool(schema.validate(bad_limit).get("ok", true))
		and "invalid_max_triggers" in (schema.validate(bad_limit).get("errors", []) as Array),
		"5. max_triggers < 0 fails validation"
	)


func _check_invalid_tick_event_does_not_crash() -> void:
	var adapter = WorldTickAdapterModel.new()
	var context = _context()
	var stores := _make_stores(context)
	var result: Dictionary = adapter.apply_tick_event(context, stores, {"tick_event_id": "invalid_probe"})
	var summary: Dictionary = result.get("world_log_summary", {})
	_check(
		not bool(result.get("success", true))
		and str(result.get("error_reason", "")) == "invalid_tick_event"
		and int(summary.get("failed_tick_event_count", 0)) == 1,
		"6. WorldTickAdapter returns failure for illegal tick_event without crashing"
	)


func _check_scoped_tick_from_delay_action() -> void:
	var adapter = WorldTickAdapterModel.new()
	var context = _context()
	var stores := _make_stores(context)
	_run_delay_action(context, stores)

	var pending: Array = stores["deferred_consequence_store"].find_pending_consequences()
	_check(
		pending.size() == 1
		and str((pending[0] as Dictionary).get("scope_type", "")) == "location"
		and str((pending[0] as Dictionary).get("scope_id", "")) == "outpost_kitchen",
		"7. delay_military_issue_until_after_patrol creates a scoped pending consequence"
	)

	var tick_result: Dictionary = adapter.apply_tick_event(
		context,
		stores,
		_tick_event("tick_after_patrol_location", "location", "outpost_kitchen")
	)
	_check(
		bool(tick_result.get("success", false))
		and int(tick_result.get("matched_count", 0)) == 1
		and int(tick_result.get("triggered_count", 0)) == 1,
		"8. institution slice uses location scope and after_patrol triggers matching consequence"
	)
	_check(
		str(stores["deferred_consequence_store"].find_deferred_consequence(
			"discipline_issue_after_patrol:outpost_kitchen"
		).get("status", "")) == "triggered",
		"9. scoped tick writeback sets deferred consequence status = triggered"
	)

	var second_tick: Dictionary = adapter.apply_tick_event(
		context,
		stores,
		_tick_event("tick_after_patrol_second", "location", "outpost_kitchen")
	)
	_check(
		bool(second_tick.get("success", false))
		and int(second_tick.get("triggered_count", 0)) == 0
		and int(second_tick.get("skipped_due_to_status_count", 0)) == 1,
		"10. second same-scope after_patrol tick does not retrigger a triggered consequence"
	)


func _check_different_scope_does_not_trigger() -> void:
	var adapter = WorldTickAdapterModel.new()
	var context = _context()
	var stores := _make_stores(context)
	_run_delay_action(context, stores)

	var tick_result: Dictionary = adapter.apply_tick_event(
		context,
		stores,
		_tick_event("tick_after_patrol_other_scope", "location", "other_kitchen")
	)
	_check(
		bool(tick_result.get("success", false))
		and int(tick_result.get("matched_count", 0)) == 0
		and int(tick_result.get("triggered_count", 0)) == 0
		and int(tick_result.get("skipped_due_to_scope_count", 0)) == 1
		and stores["deferred_consequence_store"].find_pending_consequences().size() == 1,
		"11. different scope_id after_patrol tick does not trigger the consequence"
	)


func _check_global_scope_matches_all_scopes() -> void:
	var adapter = WorldTickAdapterModel.new()
	var context = _context()
	var stores := _make_stores(context)
	_run_delay_action(context, stores)

	var tick_result: Dictionary = adapter.apply_tick_event(
		context,
		stores,
		_global_tick_event("tick_after_patrol_global")
	)
	_check(
		bool(tick_result.get("success", false))
		and str(tick_result.get("scope_type", "")) == "global"
		and str(tick_result.get("scope_id", "")) == ""
		and int(tick_result.get("matched_count", 0)) == 1
		and int(tick_result.get("triggered_count", 0)) == 1,
		"12. global after_patrol tick matches all pending scopes in this version"
	)


func _check_max_triggers() -> void:
	var adapter = WorldTickAdapterModel.new()
	var context = _context()
	var stores := _make_stores(context)
	stores["deferred_consequence_store"].add_deferred_consequence(
		_manual_deferred("limit_probe_a", "outpost_kitchen")
	)
	stores["deferred_consequence_store"].add_deferred_consequence(
		_manual_deferred("limit_probe_b", "outpost_kitchen")
	)

	var tick_event := _tick_event("tick_after_patrol_limited", "location", "outpost_kitchen")
	tick_event["max_triggers"] = 1
	var tick_result: Dictionary = adapter.apply_tick_event(context, stores, tick_event)
	_check(
		bool(tick_result.get("success", false))
		and int(tick_result.get("matched_count", 0)) == 2
		and int(tick_result.get("triggered_count", 0)) == 1
		and int(tick_result.get("skipped_due_to_limit_count", 0)) == 1
		and int(tick_result.get("skipped_count", 0)) == 1,
		"13. max_triggers = 1 triggers at most one matching consequence"
	)


func _check_world_log_queries() -> void:
	var adapter = WorldTickAdapterModel.new()
	var context = _context()
	var stores := _make_stores(context)
	_run_delay_action(context, stores)
	var tick_event := _tick_event("tick_after_patrol_log_probe", "location", "outpost_kitchen")
	var tick_result: Dictionary = adapter.apply_tick_event(context, stores, tick_event)
	var entries: Array = tick_result.get("world_log_entries", [])
	var summary: Dictionary = tick_result.get("world_log_summary", {})
	var entry: Dictionary = entries[0] if not entries.is_empty() else {}

	_check(
		str(tick_result.get("tick_type", "")) == "test_event"
		and str(tick_result.get("scope_type", "")) == "location"
		and str(tick_result.get("scope_id", "")) == "outpost_kitchen"
		and int(tick_result.get("matched_count", 0)) == 1
		and int(tick_result.get("triggered_count", 0)) == 1,
		"14. tick result records tick_type / scope / matched_count / triggered_count"
	)
	_check(
		str(entry.get("entry_type", "")) == "tick_event"
		and str(entry.get("scope_type", "")) == "location"
		and str(entry.get("scope_id", "")) == "outpost_kitchen"
		and int(entry.get("matched_count", 0)) == 1,
		"15. WorldLog tick entry records scoped tick information"
	)
	_check(
		int(summary.get("scoped_tick_event_count", 0)) == 1
		and int(summary.get("failed_tick_event_count", 0)) == 0
		and int(summary.get("triggered_deferred_count", 0)) == 1,
		"16. WorldLog summary tracks scoped tick and triggered deferred counts"
	)

	var world_log = SimWorldLogModel.new()
	world_log.append_entry(entry)
	_check(
		world_log.find_entries_by_tick_event_id("tick_after_patrol_log_probe").size() == 1
		and world_log.find_tick_entries_by_scope("location", "outpost_kitchen").size() == 1,
		"17. WorldLog query helpers find tick entries by id and scope"
	)


func _check_contract_validator() -> void:
	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(_rules(), effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "18. RawRuleContractValidator still PASS")


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


func _tick_event(tick_event_id: String, scope_type: String, scope_id: String) -> Dictionary:
	return {
		"tick_event_id": tick_event_id,
		"tick_type": "test_event",
		"trigger_key": "after_patrol",
		"scope_type": scope_type,
		"scope_id": scope_id,
		"day": 1,
		"time_key": "after_patrol",
		"source": "test",
		"label": "after patrol test tick",
	}


func _global_tick_event(tick_event_id: String) -> Dictionary:
	return {
		"tick_event_id": tick_event_id,
		"tick_type": "test_event",
		"trigger_key": "after_patrol",
		"scope_type": "global",
		"day": 1,
		"time_key": "after_patrol",
		"source": "test",
		"label": "global after patrol test tick",
	}


func _manual_deferred(deferred_id: String, scope_id: String) -> Dictionary:
	return {
		"deferred_id": deferred_id,
		"trigger_key": "after_patrol",
		"status": "pending",
		"source_actor_id": "player",
		"target_id": "recruit_elai",
		"location_id": scope_id,
		"scope_type": "location",
		"scope_id": scope_id,
		"source_fact_type": "manual_test",
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
		print("[V5 TICK EVENT SCHEMA SCOPED RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 TICK EVENT SCHEMA SCOPED RESULT FAIL] " + failure)
		print("[V5 TICK EVENT SCHEMA SCOPED RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 TICK EVENT SCHEMA SCOPED RESULT PASS] " + message)
	else:
		failures.append(message)
