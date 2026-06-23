extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
const ConsequenceTriggerSystemModel = preload("res://scripts/sim/consequence/consequence_trigger_system.gd")
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
	_check_store_updates()
	_check_transaction_update_atoms()
	_check_effect_template_updates()
	_check_consequence_trigger_system()
	_check_pressure_priority()
	_check_contract_validator()
	_finish()


func _check_store_updates() -> void:
	var obligation_store = ObligationStoreModel.new()
	obligation_store.add_obligation(_obligation("open_obligation"))
	_check(
		obligation_store.mark_fulfilled("open_obligation", "test")
		and str(obligation_store.find_obligation("open_obligation").get("status", "")) == "fulfilled",
		"1. ObligationStore updates open obligation to fulfilled"
	)
	obligation_store.add_obligation(_obligation("breach_obligation"))
	_check(
		obligation_store.mark_breached("breach_obligation", "test")
		and str(obligation_store.find_obligation("breach_obligation").get("status", "")) == "breached",
		"2. ObligationStore updates open obligation to breached"
	)

	var exchange_store = ExchangeStoreModel.new()
	exchange_store.add_exchange(_exchange("open_exchange"))
	_check(
		exchange_store.mark_settled("open_exchange", "test")
		and str(exchange_store.find_exchange("open_exchange").get("status", "")) == "settled",
		"3. ExchangeStore updates open exchange to settled"
	)

	var deferred_store = DeferredConsequenceStoreModel.new()
	deferred_store.add_deferred_consequence(_deferred("pending_deferred"))
	_check(
		deferred_store.mark_triggered("pending_deferred", "test")
		and str(deferred_store.find_deferred_consequence("pending_deferred").get("status", "")) == "triggered",
		"4. DeferredConsequenceStore updates pending consequence to triggered"
	)


func _check_transaction_update_atoms() -> void:
	var result = TransactionResultModel.new()
	result.add_obligation_update({
		"obligation_id": "writer_obligation",
		"status": "fulfilled",
	})
	result.add_exchange_update({
		"exchange_id": "writer_exchange",
		"status": "settled",
	})
	result.add_deferred_consequence_update({
		"deferred_id": "writer_deferred",
		"status": "triggered",
	})
	_check(
		not result.is_empty()
		and result.obligation_updates.size() == 1
		and result.exchange_updates.size() == 1
		and result.deferred_consequence_updates.size() == 1,
		"5. TransactionResult supports settlement update arrays"
	)

	var stores := _make_stores(_context())
	stores["obligation_store"].add_obligation(_obligation("writer_obligation"))
	stores["exchange_store"].add_exchange(_exchange("writer_exchange"))
	stores["deferred_consequence_store"].add_deferred_consequence(_deferred("writer_deferred"))
	var writer = TransactionWorldWriterModel.new()
	writer.apply_result(result, stores)
	_check(
		str(stores["obligation_store"].find_obligation("writer_obligation").get("status", "")) == "fulfilled"
		and str(stores["exchange_store"].find_exchange("writer_exchange").get("status", "")) == "settled"
		and str(stores["deferred_consequence_store"].find_deferred_consequence("writer_deferred").get("status", "")) == "triggered",
		"6. TransactionWorldWriter writes settlement updates"
	)


func _check_effect_template_updates() -> void:
	var resolver = EffectTemplateResolverModel.new()
	resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var result = resolver.resolve_template_with_bindings("obligation_fulfilled_effect", {
		"actor_id": "recruit_elai",
		"target_id": "player",
		"location_id": "outpost_kitchen",
		"rule_id": "test",
		"obligation_id": "template_obligation",
	})
	_check(
		_result_has_fact(result, "obligation_fulfilled")
		and _obligation_update_exists(result, "template_obligation", "fulfilled"),
		"7. EffectTemplateResolver parses obligation / exchange / deferred update atoms"
	)


func _check_consequence_trigger_system() -> void:
	var context = _context()
	var writer = TransactionWorldWriterModel.new()
	var trigger_system = ConsequenceTriggerSystemModel.new()

	var fulfill_stores := _make_stores(context)
	fulfill_stores["obligation_store"].add_obligation(_obligation("fulfill_obligation"))
	var fulfill_snapshot = _snapshot(context, fulfill_stores)
	var fulfill_result = trigger_system.fulfill_obligation(fulfill_snapshot, "fulfill_obligation")
	_check(
		_result_has_fact(fulfill_result, "obligation_fulfilled"),
		"8. ConsequenceTriggerSystem.fulfill_obligation returns obligation_fulfilled fact"
	)
	writer.apply_result(fulfill_result, fulfill_stores)
	_check(
		str(fulfill_stores["obligation_store"].find_obligation("fulfill_obligation").get("status", "")) == "fulfilled",
		"9. fulfill_obligation writeback sets obligation.status = fulfilled"
	)

	var breach_stores := _make_stores(context)
	breach_stores["obligation_store"].add_obligation(_obligation("breach_obligation"))
	var breach_snapshot = _snapshot(context, breach_stores)
	var breach_result = trigger_system.breach_obligation(breach_snapshot, "breach_obligation")
	_check(
		_result_has_fact(breach_result, "obligation_breached"),
		"10. ConsequenceTriggerSystem.breach_obligation returns obligation_breached fact"
	)
	writer.apply_result(breach_result, breach_stores)
	_check(
		str(breach_stores["obligation_store"].find_obligation("breach_obligation").get("status", "")) == "breached",
		"11. breach_obligation writeback sets obligation.status = breached"
	)

	var exchange_stores := _make_stores(context)
	exchange_stores["exchange_store"].add_exchange(_exchange("settle_exchange"))
	var exchange_snapshot = _snapshot(context, exchange_stores)
	var exchange_result = trigger_system.settle_exchange(exchange_snapshot, "settle_exchange")
	_check(
		_result_has_fact(exchange_result, "exchange_settled"),
		"12. ConsequenceTriggerSystem.settle_exchange returns exchange_settled fact"
	)
	writer.apply_result(exchange_result, exchange_stores)
	_check(
		str(exchange_stores["exchange_store"].find_exchange("settle_exchange").get("status", "")) == "settled",
		"13. settle_exchange writeback sets exchange.status = settled"
	)

	var deferred_stores := _make_stores(context)
	deferred_stores["deferred_consequence_store"].add_deferred_consequence(_deferred("trigger_deferred"))
	var deferred_snapshot = _snapshot(context, deferred_stores)
	var deferred_results: Array = trigger_system.trigger_deferred_by_key(deferred_snapshot, "after_patrol")
	_check(
		deferred_results.size() == 1,
		"14. trigger_deferred_by_key(\"after_patrol\") triggers a pending consequence"
	)
	var deferred_result = deferred_results[0]
	writer.apply_result(deferred_result, deferred_stores)
	_check(
		str(deferred_stores["deferred_consequence_store"].find_deferred_consequence("trigger_deferred").get("status", "")) == "triggered",
		"15. triggered deferred consequence writeback sets deferred.status = triggered"
	)
	_check(
		_result_has_fact(deferred_result, "deferred_consequence_triggered"),
		"16. triggering deferred consequence produces deferred_consequence_triggered fact"
	)
	_check(
		_pressure_change_exists(deferred_result, "outpost_kitchen", "unresolved_issue", 5),
		"17. triggering deferred consequence produces pressure change"
	)

	var runner = SimRunnerModel.new()
	var world_log = SimWorldLogModel.new()
	world_log.append_entry(runner._build_world_log_entry(
		0,
		{"step_id": "settlement_probe"},
		_fake_candidate(),
		deferred_result,
		1,
		"SimSnapshot",
		"SimSnapshot"
	))
	var summary: Dictionary = world_log.summary()
	_check(
		int(summary.get("deferred_consequence_update_count", 0)) == 1,
		"18. WorldLog records obligation / exchange / deferred update counts"
	)


func _check_pressure_priority() -> void:
	var context = _context()
	var rules := _rules()
	var builder = SimSnapshotBuilderModel.new()
	var affordance_system = ActionAffordanceModel.new()

	var base_snapshot = builder.build_snapshot(context, _make_stores(context))
	var base_candidates: Array = affordance_system.generate_candidates(base_snapshot, rules)
	var base_candidate = _find_candidate(base_candidates, "confirm_ration_record_with_cook")

	var pressure_stores := _make_stores(context)
	pressure_stores["pressure_store"].add_pressure_change({
		"pressure_id": "priority_probe",
		"scope_id": "outpost_kitchen",
		"scope_type": "location",
		"domain": "military_discipline",
		"pressure_type": "unresolved_issue",
		"value": 10,
	})
	var pressure_snapshot = builder.build_snapshot(context, pressure_stores)
	var pressure_candidates: Array = affordance_system.generate_candidates(pressure_snapshot, rules)
	var pressure_candidate = _find_candidate(pressure_candidates, "confirm_ration_record_with_cook")
	_check(
		pressure_candidate != null
		and base_candidate != null
		and int(pressure_candidate.priority) == int(base_candidate.priority) + 20
		and bool(pressure_candidate.extra.get("pressure_priority_applied", false)),
		"19. pressure_priority raises related action candidate priority"
	)


func _check_contract_validator() -> void:
	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)
	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(_rules(), effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "20. RawRuleContractValidator still PASS")


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


func _obligation(obligation_id: String) -> Dictionary:
	return {
		"obligation_id": obligation_id,
		"owner_id": "recruit_elai",
		"target_id": "player",
		"obligation_type": "watch_duty",
		"status": "open",
	}


func _exchange(exchange_id: String) -> Dictionary:
	return {
		"exchange_id": exchange_id,
		"party_a": "player",
		"party_b": "recruit_elai",
		"give": "silence",
		"receive": "watch_duty",
		"status": "open",
	}


func _deferred(deferred_id: String) -> Dictionary:
	return {
		"deferred_id": deferred_id,
		"trigger_key": "after_patrol",
		"status": "pending",
		"source_actor_id": "player",
		"target_id": "recruit_elai",
		"location_id": "outpost_kitchen",
	}


func _fake_candidate() -> Dictionary:
	return {
		"action_id": "settlement_probe",
		"rule_id": "settlement_probe",
		"target_id": "",
		"target_display_name": "",
	}


func _find_candidate(candidates: Array, rule_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) == rule_id:
			return candidate
	return null


func _result_has_fact(result: Variant, fact_type: String) -> bool:
	for fact: Dictionary in result.facts_added:
		if str(fact.get("fact_type", "")) == fact_type:
			return true
	return false


func _obligation_update_exists(result: Variant, obligation_id: String, status: String) -> bool:
	for update: Dictionary in result.obligation_updates:
		if (
			str(update.get("obligation_id", "")) == obligation_id
			and str(update.get("status", "")) == status
		):
			return true
	return false


func _pressure_change_exists(
	result: Variant,
	scope_id: String,
	pressure_type: String,
	value: int
) -> bool:
	for change: Dictionary in result.pressure_changes:
		if (
			str(change.get("scope_id", "")) == scope_id
			and str(change.get("pressure_type", "")) == pressure_type
			and int(change.get("value", 0)) == value
		):
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 CONSEQUENCE TRIGGER SETTLEMENT RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 CONSEQUENCE TRIGGER SETTLEMENT FAIL] " + failure)
		print("[V5 CONSEQUENCE TRIGGER SETTLEMENT RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 CONSEQUENCE TRIGGER SETTLEMENT PASS] " + message)
	else:
		failures.append(message)
