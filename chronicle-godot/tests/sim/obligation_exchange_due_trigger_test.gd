extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
const DueTriggerSystemModel = preload("res://scripts/sim/consequence/due_trigger_system.gd")
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
	_check_store_due_queries()
	_check_trade_action_due_metadata()
	_check_due_trigger_system()
	_check_world_tick_adapter_due_checks()
	_check_tick_event_schema_due_fields()
	_check_contract_validator()
	_finish()


func _check_store_due_queries() -> void:
	var obligation_store = ObligationStoreModel.new()
	obligation_store.add_obligation(_manual_obligation("store_obligation", "outpost_kitchen"))
	_check(
		obligation_store.find_open_due_by_deadline_and_scope(
			"tonight_watch",
			"location",
			"outpost_kitchen"
		).size() == 1,
		"1. ObligationStore finds open due obligation by deadline and scope"
	)
	_check(
		obligation_store.find_open_due_by_deadline_and_scope(
			"tonight_watch",
			"location",
			"other_kitchen"
		).is_empty(),
		"2. ObligationStore ignores different scope_id"
	)
	obligation_store.mark_due("store_obligation", _tick_event("store_due_tick", true))
	var marked_obligation: Dictionary = obligation_store.find_obligation("store_obligation")
	_check(
		str(marked_obligation.get("status", "")) == "open"
		and str(marked_obligation.get("due_status", "")) == "due"
		and int(marked_obligation.get("due_count", 0)) == 1
		and obligation_store.find_open_due_by_deadline_and_scope(
			"tonight_watch",
			"location",
			"outpost_kitchen"
		).is_empty(),
		"3. ObligationStore mark_due keeps status open and suppresses same trigger repeat"
	)

	var exchange_store = ExchangeStoreModel.new()
	exchange_store.add_exchange(_manual_exchange("store_exchange", "outpost_kitchen"))
	_check(
		exchange_store.find_open_due_by_deadline_and_scope(
			"tonight_watch",
			"location",
			"outpost_kitchen"
		).size() == 1,
		"4. ExchangeStore finds open due exchange by deadline and scope"
	)
	exchange_store.mark_due("store_exchange", _tick_event("store_exchange_due_tick", true))
	var marked_exchange: Dictionary = exchange_store.find_exchange("store_exchange")
	_check(
		str(marked_exchange.get("status", "")) == "open"
		and str(marked_exchange.get("due_status", "")) == "due"
		and int(marked_exchange.get("due_count", 0)) == 1
		and exchange_store.find_open_due_by_deadline_and_scope(
			"tonight_watch",
			"location",
			"outpost_kitchen"
		).is_empty(),
		"5. ExchangeStore mark_due keeps status open and suppresses same trigger repeat"
	)


func _check_trade_action_due_metadata() -> void:
	var context = _context()
	var stores := _make_stores(context)
	_run_trade_action(context, stores)
	var obligation: Dictionary = _first_obligation(stores)
	var exchange: Dictionary = _first_exchange(stores)

	_check(
		str(obligation.get("deadline_key", "")) == "tonight_watch"
		and str(obligation.get("scope_type", "")) == "location"
		and str(obligation.get("scope_id", "")) == "outpost_kitchen",
		"6. trade_watch_duty_for_silence creates obligation with deadline and location scope"
	)
	_check(
		str(exchange.get("deadline_key", "")) == "tonight_watch"
		and str(exchange.get("scope_type", "")) == "location"
		and str(exchange.get("scope_id", "")) == "outpost_kitchen",
		"7. trade_watch_duty_for_silence creates exchange with deadline and location scope"
	)
	_check(
		str(obligation.get("due_status", "")) == "not_due"
		and int(obligation.get("due_count", -1)) == 0
		and str(exchange.get("due_status", "")) == "not_due"
		and int(exchange.get("due_count", -1)) == 0,
		"8. trade action initializes obligation and exchange due_status = not_due"
	)


func _check_due_trigger_system() -> void:
	var context = _context()
	var stores := _make_stores(context)
	_run_trade_action(context, stores)
	var snapshot = _snapshot(context, stores)
	var due_system = DueTriggerSystemModel.new()
	var due_data: Dictionary = due_system.trigger_due_for_tick(
		snapshot,
		_tick_event("direct_due_tick", true)
	)
	var obligation_results: Array = due_data.get("obligation_results", [])
	var exchange_results: Array = due_data.get("exchange_results", [])
	_check(
		int(due_data.get("obligation_due_count", 0)) == 1
		and int(due_data.get("exchange_due_count", 0)) == 1
		and _results_have_fact(obligation_results, "obligation_due")
		and _results_have_fact(exchange_results, "exchange_due"),
		"9. DueTriggerSystem creates obligation_due and exchange_due results"
	)
	_check(
		str(_first_obligation(stores).get("due_status", "")) == "not_due"
		and str(_first_exchange(stores).get("due_status", "")) == "not_due",
		"10. DueTriggerSystem does not directly write Store"
	)

	var writer = TransactionWorldWriterModel.new()
	for result: Variant in obligation_results:
		writer.apply_result(result, stores)
	for result: Variant in exchange_results:
		writer.apply_result(result, stores)
	var obligation: Dictionary = _first_obligation(stores)
	var exchange: Dictionary = _first_exchange(stores)
	_check(
		str(obligation.get("status", "")) == "open"
		and str(obligation.get("due_status", "")) == "due"
		and int(obligation.get("due_count", 0)) == 1,
		"11. TransactionWorldWriter writes obligation.due_status without changing status"
	)
	_check(
		str(exchange.get("status", "")) == "open"
		and str(exchange.get("due_status", "")) == "due"
		and int(exchange.get("due_count", 0)) == 1,
		"12. TransactionWorldWriter writes exchange.due_status without changing status"
	)
	_check(
		not stores["fact_store"].find_facts_by_type("obligation_due").is_empty()
		and not stores["fact_store"].find_facts_by_type("exchange_due").is_empty()
		and stores["pressure_store"].get_pressure_value("outpost_kitchen", "obligation_attention") == 5
		and stores["pressure_store"].get_pressure_value("outpost_kitchen", "exchange_attention") == 5,
		"13. due writeback records facts and attention pressure"
	)


func _check_world_tick_adapter_due_checks() -> void:
	var adapter = WorldTickAdapterModel.new()

	var false_context = _context()
	var false_stores := _make_stores(false_context)
	_run_trade_action(false_context, false_stores)
	var false_result: Dictionary = adapter.apply_tick_event(
		false_context,
		false_stores,
		_tick_event("no_due_tick", false)
	)
	_check(
		bool(false_result.get("success", false))
		and int(false_result.get("due_result_count", 0)) == 0
		and str(_first_obligation(false_stores).get("due_status", "")) == "not_due"
		and str(_first_exchange(false_stores).get("due_status", "")) == "not_due",
		"14. include_due_checks=false does not trigger due checks"
	)

	var true_context = _context()
	var true_stores := _make_stores(true_context)
	_run_trade_action(true_context, true_stores)
	var true_result: Dictionary = adapter.apply_tick_event(
		true_context,
		true_stores,
		_tick_event("due_tick", true)
	)
	var true_entries: Array = true_result.get("world_log_entries", [])
	var true_entry: Dictionary = true_entries[0] if not true_entries.is_empty() else {}
	var true_summary: Dictionary = true_result.get("world_log_summary", {})
	_check(
		bool(true_result.get("success", false))
		and int(true_result.get("obligation_due_count", 0)) == 1
		and int(true_result.get("exchange_due_count", 0)) == 1
		and int(true_result.get("due_result_count", 0)) == 2,
		"15. include_due_checks=true triggers obligation and exchange due"
	)
	_check(
		str(_first_obligation(true_stores).get("due_status", "")) == "due"
		and str(_first_exchange(true_stores).get("due_status", "")) == "due"
		and not true_stores["fact_store"].find_facts_by_type("obligation_due").is_empty()
		and not true_stores["fact_store"].find_facts_by_type("exchange_due").is_empty(),
		"16. WorldTickAdapter writes due facts and due_status through writer"
	)
	_check(
		int(true_entry.get("due_result_count", 0)) == 2
		and int(true_summary.get("obligation_due_count", 0)) == 1
		and int(true_summary.get("exchange_due_count", 0)) == 1
		and int(true_summary.get("due_result_count", 0)) == 2,
		"17. TickResult and WorldLog record due counts"
	)

	var scoped_context = _context()
	var scoped_stores := _make_stores(scoped_context)
	_run_trade_action(scoped_context, scoped_stores)
	var scoped_result: Dictionary = adapter.apply_tick_event(
		scoped_context,
		scoped_stores,
		_tick_event("wrong_scope_due_tick", true, "other_kitchen")
	)
	_check(
		int(scoped_result.get("due_result_count", 0)) == 0
		and str(_first_obligation(scoped_stores).get("due_status", "")) == "not_due"
		and str(_first_exchange(scoped_stores).get("due_status", "")) == "not_due",
		"18. different scope_id does not trigger obligation or exchange due"
	)

	var global_context = _context()
	var global_stores := _make_stores(global_context)
	_run_trade_action(global_context, global_stores)
	var global_result: Dictionary = adapter.apply_tick_event(
		global_context,
		global_stores,
		_global_tick_event("global_due_tick")
	)
	_check(
		bool(global_result.get("success", false))
		and str(global_result.get("scope_type", "")) == "global"
		and int(global_result.get("obligation_due_count", 0)) == 1
		and int(global_result.get("exchange_due_count", 0)) == 1,
		"19. global scope due tick follows 24.2 and matches all scopes"
	)

	var repeat_result: Dictionary = adapter.apply_tick_event(
		true_context,
		true_stores,
		_tick_event("due_tick_repeat", true)
	)
	_check(
		bool(repeat_result.get("success", false))
		and int(repeat_result.get("due_result_count", 0)) == 0
		and int(_first_obligation(true_stores).get("due_count", 0)) == 1
		and int(_first_exchange(true_stores).get("due_count", 0)) == 1,
		"20. repeated same trigger_key does not mark already due records again"
	)


func _check_tick_event_schema_due_fields() -> void:
	var schema = TickEventSchemaModel.new()
	var valid: Dictionary = schema.validate(_tick_event("schema_due_tick", true))
	var event: Dictionary = valid.get("event", {})
	_check(
		bool(valid.get("ok", false))
		and bool(event.get("include_due_checks", false))
		and (event.get("due_kinds", []) as Array).size() == 2,
		"21. TickEventSchema accepts include_due_checks and default due_kinds"
	)

	var bad_kind := _tick_event("schema_bad_due_kind", true)
	bad_kind["due_kinds"] = ["obligation", "unknown"]
	var bad_kind_result: Dictionary = schema.validate(bad_kind)
	_check(
		not bool(bad_kind_result.get("ok", true))
		and "invalid_due_kind:unknown" in (bad_kind_result.get("errors", []) as Array),
		"22. TickEventSchema rejects unknown due_kinds"
	)
	var bad_flag := _tick_event("schema_bad_due_flag", true)
	bad_flag["include_due_checks"] = "yes"
	var bad_flag_result: Dictionary = schema.validate(bad_flag)
	_check(
		not bool(bad_flag_result.get("ok", true))
		and "invalid_include_due_checks" in (bad_flag_result.get("errors", []) as Array),
		"23. TickEventSchema rejects non-bool include_due_checks"
	)


func _check_contract_validator() -> void:
	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(_rules(), effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "24. RawRuleContractValidator still PASS")


func _run_trade_action(context: Variant, stores: Dictionary) -> void:
	var snapshot = _snapshot(context, stores)
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()
	var candidates: Array = affordance_system.generate_candidates(snapshot, _rules())
	var trade_candidate = _find_candidate(candidates, "trade_watch_duty_for_silence", "recruit_elai")
	var result = resolver.resolve_action(trade_candidate, snapshot)
	writer.apply_result(result, stores)


func _tick_event(
	tick_event_id: String,
	include_due_checks: bool,
	scope_id: String = "outpost_kitchen"
) -> Dictionary:
	return {
		"tick_event_id": tick_event_id,
		"tick_type": "test_event",
		"trigger_key": "tonight_watch",
		"scope_type": "location",
		"scope_id": scope_id,
		"day": 1,
		"time_key": "tonight_watch",
		"source": "test",
		"label": "tonight watch due tick",
		"include_due_checks": include_due_checks,
	}


func _global_tick_event(tick_event_id: String) -> Dictionary:
	return {
		"tick_event_id": tick_event_id,
		"tick_type": "test_event",
		"trigger_key": "tonight_watch",
		"scope_type": "global",
		"day": 1,
		"time_key": "tonight_watch",
		"source": "test",
		"label": "global tonight watch due tick",
		"include_due_checks": true,
	}


func _manual_obligation(obligation_id: String, scope_id: String) -> Dictionary:
	return {
		"obligation_id": obligation_id,
		"owner_id": "recruit_elai",
		"target_id": "player",
		"obligation_type": "watch_duty",
		"status": "open",
		"deadline_key": "tonight_watch",
		"location_id": scope_id,
		"scope_type": "location",
		"scope_id": scope_id,
		"due_status": "not_due",
		"due_count": 0,
	}


func _manual_exchange(exchange_id: String, scope_id: String) -> Dictionary:
	return {
		"exchange_id": exchange_id,
		"party_a": "player",
		"party_b": "recruit_elai",
		"give": "silence",
		"receive": "watch_duty",
		"status": "open",
		"deadline_key": "tonight_watch",
		"location_id": scope_id,
		"scope_type": "location",
		"scope_id": scope_id,
		"due_status": "not_due",
		"due_count": 0,
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


func _results_have_fact(results: Array, fact_type: String) -> bool:
	for result: Variant in results:
		for fact: Dictionary in result.facts_added:
			if str(fact.get("fact_type", "")) == fact_type:
				return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 OBLIGATION EXCHANGE DUE TRIGGER RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 OBLIGATION EXCHANGE DUE TRIGGER FAIL] " + failure)
		print("[V5 OBLIGATION EXCHANGE DUE TRIGGER RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 OBLIGATION EXCHANGE DUE TRIGGER PASS] " + message)
	else:
		failures.append(message)
