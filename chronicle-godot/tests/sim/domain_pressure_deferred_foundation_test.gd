extends SceneTree

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimRunnerModel = preload("res://scripts/sim/core/sim_runner.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const RawRuleContractValidatorModel = preload("res://scripts/sim/action/raw_rule_contract_validator.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionResultModel = preload("res://scripts/sim/transaction/transaction_result.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const EffectTemplateResolverModel = preload("res://scripts/sim/transaction/effect_template_resolver.gd")
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
	_check_pressure_store()
	_check_obligation_store()
	_check_exchange_store()
	_check_deferred_consequence_store()
	_check_transaction_result_and_writer()
	_check_snapshot_reads_new_stores()
	_check_rules_and_effects()
	_finish()


func _check_pressure_store() -> void:
	var store = PressureStoreModel.new()
	store.add_pressure_change({
		"pressure_id": "unresolved_issue:outpost_kitchen",
		"scope_id": "outpost_kitchen",
		"scope_type": "location",
		"domain": "military_discipline",
		"pressure_type": "unresolved_issue",
		"value": 10,
	})
	store.add_pressure_change({
		"pressure_id": "ration_record_attention:outpost_kitchen",
		"scope_id": "outpost_kitchen",
		"scope_type": "location",
		"domain": "military_discipline",
		"pressure_type": "ration_record_attention",
		"value": 5,
	})
	_check(
		store.list_pressures().size() == 2
		and store.list_pressures_by_domain("military_discipline").size() == 2
		and store.list_pressures_by_location("outpost_kitchen").size() == 2
		and store.get_pressure_value("outpost_kitchen", "unresolved_issue") == 10,
		"1. PressureStore saves and queries pressure changes"
	)


func _check_obligation_store() -> void:
	var store = ObligationStoreModel.new()
	store.add_obligation({
		"obligation_id": "recruit_elai_watch_duty_for_player",
		"owner_id": "recruit_elai",
		"target_id": "player",
		"obligation_type": "watch_duty",
		"status": "open",
	})
	store.add_obligation({
		"obligation_id": "closed_probe",
		"owner_id": "captain_ron",
		"target_id": "player",
		"obligation_type": "report",
		"status": "closed",
	})
	_check(
		store.list_obligations().size() == 2
		and store.list_obligations_by_owner("recruit_elai").size() == 1
		and store.list_obligations_by_target("player").size() == 2
		and store.find_open_obligations().size() == 1,
		"2. ObligationStore saves and queries open obligations"
	)


func _check_exchange_store() -> void:
	var store = ExchangeStoreModel.new()
	store.add_exchange({
		"exchange_id": "player_recruit_elai_silence_for_watch_duty",
		"party_a": "player",
		"party_b": "recruit_elai",
		"give": "silence",
		"receive": "watch_duty",
		"status": "open",
	})
	store.add_exchange({
		"exchange_id": "captain_probe",
		"party_a": "captain_ron",
		"party_b": "player",
		"give": "order",
		"receive": "report",
		"status": "closed",
	})
	_check(
		store.list_exchanges().size() == 2
		and store.list_exchanges_by_actor("player").size() == 2
		and store.list_exchanges_by_actor("recruit_elai").size() == 1
		and store.find_open_exchanges().size() == 1,
		"3. ExchangeStore saves and queries open exchanges"
	)


func _check_deferred_consequence_store() -> void:
	var store = DeferredConsequenceStoreModel.new()
	store.add_deferred_consequence({
		"deferred_id": "discipline_issue_after_patrol:outpost_kitchen",
		"trigger_key": "after_patrol",
		"status": "pending",
		"expected_effect_hint": "discipline_issue_must_be_revisited",
	})
	store.add_deferred_consequence({
		"deferred_id": "resolved_probe",
		"trigger_key": "after_meal",
		"status": "resolved",
	})
	_check(
		store.list_deferred_consequences().size() == 2
		and store.find_pending_consequences().size() == 1
		and store.find_by_trigger_key("after_patrol").size() == 1,
		"4. DeferredConsequenceStore saves and queries pending consequences"
	)


func _check_transaction_result_and_writer() -> void:
	var result = TransactionResultModel.new()
	result.add_pressure_change(_pressure_change())
	result.add_obligation(_obligation())
	result.add_exchange(_exchange())
	result.add_deferred_consequence(_deferred_consequence())
	_check(
		not result.is_empty()
		and result.pressure_changes.size() == 1
		and result.obligations_added.size() == 1
		and result.exchanges_added.size() == 1
		and result.deferred_consequences_added.size() == 1
		and (result.to_dict().get("pressure_changes", []) as Array).size() == 1,
		"5. TransactionResult supports pressure / obligation / exchange / deferred arrays"
	)

	var stores := _make_empty_stores()
	var writer = TransactionWorldWriterModel.new()
	writer.apply_result(result, stores)
	_check(
		stores["pressure_store"].list_pressures().size() == 1
		and stores["obligation_store"].list_obligations().size() == 1
		and stores["exchange_store"].list_exchanges().size() == 1
		and stores["deferred_consequence_store"].list_deferred_consequences().size() == 1,
		"6. TransactionWorldWriter writes all new stores"
	)


func _check_snapshot_reads_new_stores() -> void:
	var registry = SimRegistryModel.new()
	var context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var stores := _make_stores(context)
	stores["pressure_store"].add_pressure_change(_pressure_change())
	stores["obligation_store"].add_obligation(_obligation())
	stores["exchange_store"].add_exchange(_exchange())
	stores["deferred_consequence_store"].add_deferred_consequence(_deferred_consequence())

	var snapshot_builder = SimSnapshotBuilderModel.new()
	var snapshot = snapshot_builder.build_snapshot(context, stores)
	_check(
		snapshot.get_pressures().size() == 1
		and snapshot.get_open_obligations().size() == 1
		and snapshot.get_open_exchanges().size() == 1
		and snapshot.get_pending_deferred_consequences().size() == 1,
		"7. SimSnapshot reads pressure / obligation / exchange / deferred stores"
	)


func _check_rules_and_effects() -> void:
	var registry = SimRegistryModel.new()
	var raw_rule_paths := [BASIC_RULES_PATH, DOMAIN_RULES_PATH, TEST_RULES_PATH]
	registry.load_action_rules(raw_rule_paths)
	var rules: Array = registry.get_action_rules()
	var effect_resolver = EffectTemplateResolverModel.new()
	effect_resolver.load_effect_templates(EFFECT_TEMPLATES_PATH)

	_check(
		_rule_effect_template_id(rules, "confirm_ration_record_with_cook") == "confirm_ration_record_effect",
		"8. confirm_ration_record_with_cook binds confirm_ration_record_effect"
	)
	_check(
		_rule_effect_template_id(rules, "trade_watch_duty_for_silence") == "trade_watch_duty_for_silence_effect",
		"9. trade_watch_duty_for_silence binds trade_watch_duty_for_silence_effect"
	)
	_check(
		_rule_effect_template_id(rules, "delay_military_issue_until_after_patrol") == "delay_issue_until_after_patrol_effect",
		"10. delay_military_issue_until_after_patrol binds delay_issue_until_after_patrol_effect"
	)

	var context = SimContextModel.new(registry.load_json(SEVENTH_OUTPOST_FIXTURE_PATH))
	var stores := _make_stores(context)
	var snapshot_builder = SimSnapshotBuilderModel.new()
	var snapshot = snapshot_builder.build_snapshot(context, stores)
	var affordance_system = ActionAffordanceModel.new()
	var candidates: Array = affordance_system.generate_candidates(snapshot, rules)
	var resolver = TransactionResolverModel.new()

	var confirm_candidate = _find_candidate(candidates, "confirm_ration_record_with_cook")
	var confirm_result = resolver.resolve_action(confirm_candidate, snapshot)
	_check(
		_result_has_fact(confirm_result, "actor_confirmed_ration_record"),
		"11. confirm_ration_record_with_cook produces actor_confirmed_ration_record fact"
	)
	_check(
		_pressure_change_exists(confirm_result, "outpost_kitchen", "ration_record_attention", 5),
		"12. confirm_ration_record_with_cook produces ration_record_attention pressure"
	)

	var trade_candidate = _find_candidate(candidates, "trade_watch_duty_for_silence", "recruit_elai")
	var trade_result = resolver.resolve_action(trade_candidate, snapshot)
	_check(
		_exchange_exists(trade_result, "player", "recruit_elai", "silence", "watch_duty"),
		"13. trade_watch_duty_for_silence produces silence-for-watch-duty exchange"
	)
	_check(
		_obligation_exists(trade_result, "recruit_elai", "player", "watch_duty"),
		"14. trade_watch_duty_for_silence produces watch_duty obligation"
	)

	var delay_candidate = _find_candidate(candidates, "delay_military_issue_until_after_patrol")
	var delay_result = resolver.resolve_action(delay_candidate, snapshot)
	_check(
		_deferred_consequence_exists(delay_result, "after_patrol", "pending"),
		"15. delay_military_issue_until_after_patrol produces pending deferred consequence"
	)
	_check(
		_pressure_change_exists(delay_result, "outpost_kitchen", "unresolved_issue", 10),
		"16. delay_military_issue_until_after_patrol produces unresolved_issue pressure"
	)

	var runner = SimRunnerModel.new()
	var world_log = SimWorldLogModel.new()
	var log_entry: Dictionary = runner._build_world_log_entry(
		0,
		{"step_id": "delay_probe"},
		delay_candidate,
		delay_result,
		candidates.size(),
		"SimSnapshot",
		"SimSnapshot"
	)
	world_log.append_entry(log_entry)
	var summary: Dictionary = world_log.summary()
	_check(
		int(log_entry.get("pressure_change_count", 0)) == 1
		and int(log_entry.get("deferred_consequence_count", 0)) == 1
		and int(summary.get("pressure_change_count", 0)) == 1
		and int(summary.get("deferred_consequence_count", 0)) == 1,
		"17. WorldLog records pressure and deferred counts"
	)

	var validator = RawRuleContractValidatorModel.new()
	var validation: Dictionary = validator.validate_rules(rules, effect_resolver.templates)
	_check(bool(validation.get("ok", false)), "18. RawRuleContractValidator PASS")


func _make_empty_stores() -> Dictionary:
	return {
		"pressure_store": PressureStoreModel.new(),
		"obligation_store": ObligationStoreModel.new(),
		"exchange_store": ExchangeStoreModel.new(),
		"deferred_consequence_store": DeferredConsequenceStoreModel.new(),
	}


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


func _pressure_change() -> Dictionary:
	return {
		"pressure_id": "unresolved_issue:outpost_kitchen",
		"scope_id": "outpost_kitchen",
		"scope_type": "location",
		"domain": "military_discipline",
		"pressure_type": "unresolved_issue",
		"value": 10,
		"source_fact_type": "actor_deferred_issue_until_after_patrol",
	}


func _obligation() -> Dictionary:
	return {
		"obligation_id": "recruit_elai_watch_duty_for_player",
		"owner_id": "recruit_elai",
		"target_id": "player",
		"obligation_type": "watch_duty",
		"status": "open",
		"source_fact_type": "actor_traded_watch_duty_for_silence",
	}


func _exchange() -> Dictionary:
	return {
		"exchange_id": "player_recruit_elai_silence_for_watch_duty",
		"party_a": "player",
		"party_b": "recruit_elai",
		"give": "silence",
		"receive": "watch_duty",
		"status": "open",
		"source_fact_type": "actor_traded_watch_duty_for_silence",
	}


func _deferred_consequence() -> Dictionary:
	return {
		"deferred_id": "discipline_issue_after_patrol:outpost_kitchen",
		"trigger_key": "after_patrol",
		"status": "pending",
		"source_fact_type": "actor_deferred_issue_until_after_patrol",
		"expected_effect_hint": "discipline_issue_must_be_revisited",
	}


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


func _obligation_exists(
	result: Variant,
	owner_id: String,
	target_id: String,
	obligation_type: String
) -> bool:
	for obligation: Dictionary in result.obligations_added:
		if (
			str(obligation.get("owner_id", "")) == owner_id
			and str(obligation.get("target_id", "")) == target_id
			and str(obligation.get("obligation_type", "")) == obligation_type
			and str(obligation.get("status", "")) == "open"
		):
			return true
	return false


func _exchange_exists(
	result: Variant,
	party_a: String,
	party_b: String,
	give: String,
	receive: String
) -> bool:
	for exchange: Dictionary in result.exchanges_added:
		if (
			str(exchange.get("party_a", "")) == party_a
			and str(exchange.get("party_b", "")) == party_b
			and str(exchange.get("give", "")) == give
			and str(exchange.get("receive", "")) == receive
			and str(exchange.get("status", "")) == "open"
		):
			return true
	return false


func _deferred_consequence_exists(result: Variant, trigger_key: String, status: String) -> bool:
	for consequence: Dictionary in result.deferred_consequences_added:
		if (
			str(consequence.get("trigger_key", "")) == trigger_key
			and str(consequence.get("status", "")) == status
		):
			return true
	return false


func _finish() -> void:
	if failures.is_empty():
		print("[V5 DOMAIN PRESSURE DEFERRED FOUNDATION RESULT] PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error("[V5 DOMAIN PRESSURE DEFERRED FOUNDATION FAIL] " + failure)
		print("[V5 DOMAIN PRESSURE DEFERRED FOUNDATION RESULT] FAIL: %s" % JSON.stringify(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[V5 DOMAIN PRESSURE DEFERRED FOUNDATION PASS] " + message)
	else:
		failures.append(message)
