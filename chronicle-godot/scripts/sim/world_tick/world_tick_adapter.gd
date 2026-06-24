extends RefCounted
class_name V5WorldTickAdapter

const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ConsequenceTriggerSystemModel = preload("res://scripts/sim/consequence/consequence_trigger_system.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const TickEventSchemaModel = preload("res://scripts/sim/world_tick/tick_event_schema.gd")

const ENTRY_TYPE_TICK_EVENT := "tick_event"
const SOURCE := "WorldTickAdapter"


func apply_tick_event(context: Variant, stores: Dictionary, tick_event: Dictionary) -> Dictionary:
	var schema = TickEventSchemaModel.new()
	var validation: Dictionary = schema.validate(tick_event)
	var event: Dictionary = validation.get("event", {})
	var validation_errors: Array = validation.get("errors", [])
	var validation_warnings: Array = validation.get("warnings", [])

	if not bool(validation.get("ok", false)):
		return _failure_result(
			event,
			"invalid_tick_event",
			stores,
			validation_errors,
			validation_warnings
		)

	if not stores.has("deferred_consequence_store") or stores.get("deferred_consequence_store") == null:
		return _failure_result(event, "missing_deferred_consequence_store", stores)

	var tick_event_id := str(event.get("tick_event_id", ""))
	var tick_type := str(event.get("tick_type", ""))
	var trigger_key := str(event.get("trigger_key", ""))
	var scope_type := str(event.get("scope_type", ""))
	var scope_id := str(event.get("scope_id", ""))
	var source := str(event.get("source", ""))
	var max_triggers := int(event.get("max_triggers", 0))
	var deferred_store: Variant = stores.get("deferred_consequence_store")
	var all_for_trigger: Array = _find_by_trigger_key(deferred_store, trigger_key)
	var matched_consequences: Array = _find_pending_by_trigger_and_scope(
		deferred_store,
		trigger_key,
		scope_type,
		scope_id
	)
	var skipped_due_to_scope_count := _skipped_due_to_scope_count(
		all_for_trigger,
		scope_type,
		scope_id
	)
	var skipped_due_to_status_count := _skipped_due_to_status_count(all_for_trigger)
	var selected_consequences := _select_with_limit(matched_consequences, max_triggers)
	var skipped_due_to_limit_count := matched_consequences.size() - selected_consequences.size()

	var snapshot_builder = SimSnapshotBuilderModel.new()
	var trigger_system = ConsequenceTriggerSystemModel.new()
	var writer = TransactionWorldWriterModel.new()
	var world_log = SimWorldLogModel.new()
	var snapshot = snapshot_builder.build_snapshot(context, stores)
	var transaction_results: Array = []

	for consequence: Dictionary in selected_consequences:
		var deferred_id := str(consequence.get("deferred_id", ""))
		if deferred_id == "":
			continue
		var result: Variant = trigger_system.trigger_deferred(snapshot, deferred_id)
		writer.apply_result(result, stores)
		transaction_results.append(result)

	var skipped_count := (
		skipped_due_to_scope_count
		+ skipped_due_to_status_count
		+ skipped_due_to_limit_count
	)
	world_log.append_entry(_build_tick_log_entry(
		event,
		transaction_results,
		matched_consequences.size(),
		transaction_results.size(),
		skipped_count,
		skipped_due_to_scope_count,
		skipped_due_to_status_count,
		skipped_due_to_limit_count,
		""
	))

	return {
		"success": true,
		"tick_event_id": tick_event_id,
		"tick_type": tick_type,
		"trigger_key": trigger_key,
		"scope_type": scope_type,
		"scope_id": scope_id,
		"source": source,
		"max_triggers": max_triggers,
		"matched_count": matched_consequences.size(),
		"triggered_count": transaction_results.size(),
		"skipped_count": skipped_count,
		"skipped_due_to_scope_count": skipped_due_to_scope_count,
		"skipped_due_to_status_count": skipped_due_to_status_count,
		"skipped_due_to_limit_count": skipped_due_to_limit_count,
		"error_reason": "",
		"results": _result_rows(transaction_results),
		"world_log_entries": world_log.list_entries(),
		"world_log_summary": world_log.summary(),
		"store_summary": _store_summary(stores),
	}


func _failure_result(
	tick_event: Dictionary,
	error_reason: String,
	stores: Dictionary,
	validation_errors: Array = [],
	validation_warnings: Array = []
) -> Dictionary:
	var world_log = SimWorldLogModel.new()
	world_log.append_entry(_build_tick_log_entry(
		tick_event,
		[],
		0,
		0,
		0,
		0,
		0,
		0,
		error_reason,
		validation_errors,
		validation_warnings
	))
	return {
		"success": false,
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"tick_type": str(tick_event.get("tick_type", "")),
		"trigger_key": str(tick_event.get("trigger_key", "")),
		"scope_type": str(tick_event.get("scope_type", "")),
		"scope_id": str(tick_event.get("scope_id", "")),
		"source": str(tick_event.get("source", "")),
		"max_triggers": int(tick_event.get("max_triggers", 0)),
		"matched_count": 0,
		"triggered_count": 0,
		"skipped_count": 0,
		"skipped_due_to_scope_count": 0,
		"skipped_due_to_status_count": 0,
		"skipped_due_to_limit_count": 0,
		"error_reason": error_reason,
		"validation_errors": validation_errors.duplicate(true),
		"validation_warnings": validation_warnings.duplicate(true),
		"results": [],
		"world_log_entries": world_log.list_entries(),
		"world_log_summary": world_log.summary(),
		"store_summary": _store_summary(stores),
	}


func _build_tick_log_entry(
	tick_event: Dictionary,
	results: Array,
	matched_count: int,
	triggered_count: int,
	skipped_count: int,
	skipped_due_to_scope_count: int,
	skipped_due_to_status_count: int,
	skipped_due_to_limit_count: int,
	error_reason: String,
	validation_errors: Array = [],
	validation_warnings: Array = []
) -> Dictionary:
	var aggregate := _aggregate_results(results)
	var pressure_changes: Array = aggregate.get("pressure_changes", [])
	var obligation_updates: Array = aggregate.get("obligation_updates", [])
	var exchange_updates: Array = aggregate.get("exchange_updates", [])
	var deferred_updates: Array = aggregate.get("deferred_consequence_updates", [])
	var narrative_results: Array = aggregate.get("narrative_results", [])
	var contract_status := "resolved"
	if error_reason != "":
		contract_status = "invalid_contract"

	return {
		"entry_type": ENTRY_TYPE_TICK_EVENT,
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"tick_type": str(tick_event.get("tick_type", "")),
		"trigger_key": str(tick_event.get("trigger_key", "")),
		"scope_type": str(tick_event.get("scope_type", "")),
		"scope_id": str(tick_event.get("scope_id", "")),
		"day": int(tick_event.get("day", 0)),
		"time_key": str(tick_event.get("time_key", "")),
		"source": _entry_source(tick_event),
		"rule_id": "world_tick_adapter",
		"action_id": str(tick_event.get("tick_event_id", "")),
		"transaction_mode": "world_tick_adapter",
		"contract_status": contract_status,
		"skip_reason": "",
		"error_reason": error_reason,
		"validation_errors": validation_errors.duplicate(true),
		"validation_warnings": validation_warnings.duplicate(true),
		"matched_count": matched_count,
		"triggered_count": triggered_count,
		"skipped_count": skipped_count,
		"skipped_due_to_scope_count": skipped_due_to_scope_count,
		"skipped_due_to_status_count": skipped_due_to_status_count,
		"skipped_due_to_limit_count": skipped_due_to_limit_count,
		"facts_added": _fact_types(aggregate.get("facts", [])),
		"fact_ids": _fact_ids(aggregate.get("facts", [])),
		"pressure_changes": pressure_changes.duplicate(true),
		"pressure_change_count": pressure_changes.size(),
		"deferred_consequence_updates": deferred_updates.duplicate(true),
		"deferred_consequence_update_count": deferred_updates.size(),
		"obligation_update_count": obligation_updates.size(),
		"exchange_update_count": exchange_updates.size(),
		"narrative_summary": _narrative_summaries(narrative_results),
		"narrative_result": narrative_results.duplicate(true),
	}


func _find_by_trigger_key(store: Variant, trigger_key: String) -> Array:
	if store != null and store.has_method("find_by_trigger_key"):
		return store.find_by_trigger_key(trigger_key)

	var rows: Array = []
	for consequence: Dictionary in _list_deferred_consequences(store):
		if str(consequence.get("trigger_key", "")) == trigger_key:
			rows.append(consequence.duplicate(true))
	return rows


func _find_pending_by_trigger_and_scope(
	store: Variant,
	trigger_key: String,
	scope_type: String,
	scope_id: String
) -> Array:
	if store != null and store.has_method("find_pending_by_trigger_and_scope"):
		return store.find_pending_by_trigger_and_scope(trigger_key, scope_type, scope_id)

	var rows: Array = []
	for consequence: Dictionary in _list_deferred_consequences(store):
		if str(consequence.get("status", "pending")) != "pending":
			continue
		if str(consequence.get("trigger_key", "")) != trigger_key:
			continue
		if not _scope_matches(consequence, scope_type, scope_id):
			continue
		rows.append(consequence.duplicate(true))
	return rows


func _list_deferred_consequences(store: Variant) -> Array:
	if store != null and store.has_method("list_deferred_consequences"):
		return store.list_deferred_consequences()
	return []


func _skipped_due_to_scope_count(
	consequences: Array,
	scope_type: String,
	scope_id: String
) -> int:
	var count := 0
	for consequence: Dictionary in consequences:
		if str(consequence.get("status", "pending")) != "pending":
			continue
		if _scope_matches(consequence, scope_type, scope_id):
			continue
		count += 1
	return count


func _skipped_due_to_status_count(consequences: Array) -> int:
	var count := 0
	for consequence: Dictionary in consequences:
		if str(consequence.get("status", "pending")) != "pending":
			count += 1
	return count


func _scope_matches(consequence: Dictionary, scope_type: String, scope_id: String) -> bool:
	if scope_type == "global":
		return true
	return (
		str(consequence.get("scope_type", "")) == scope_type
		and str(consequence.get("scope_id", "")) == scope_id
	)


func _select_with_limit(consequences: Array, max_triggers: int) -> Array:
	var selected: Array = []
	for consequence: Dictionary in consequences:
		if max_triggers > 0 and selected.size() >= max_triggers:
			break
		selected.append(consequence.duplicate(true))
	return selected


func _result_rows(results: Array) -> Array:
	var rows: Array = []
	for result: Variant in results:
		if result != null and result.has_method("to_dict"):
			rows.append(result.to_dict())
	return rows


func _aggregate_results(results: Array) -> Dictionary:
	var facts: Array = []
	var pressure_changes: Array = []
	var obligation_updates: Array = []
	var exchange_updates: Array = []
	var deferred_updates: Array = []
	var narrative_results: Array = []

	for result: Variant in results:
		if result == null:
			continue
		facts.append_array(result.facts_added.duplicate(true))
		pressure_changes.append_array(result.pressure_changes.duplicate(true))
		obligation_updates.append_array(result.obligation_updates.duplicate(true))
		exchange_updates.append_array(result.exchange_updates.duplicate(true))
		deferred_updates.append_array(result.deferred_consequence_updates.duplicate(true))
		if not result.narrative_result.is_empty():
			narrative_results.append(result.narrative_result.duplicate(true))

	return {
		"facts": facts,
		"pressure_changes": pressure_changes,
		"obligation_updates": obligation_updates,
		"exchange_updates": exchange_updates,
		"deferred_consequence_updates": deferred_updates,
		"narrative_results": narrative_results,
	}


func _entry_source(tick_event: Dictionary) -> String:
	var source := str(tick_event.get("source", ""))
	return SOURCE if source == "" else source


func _fact_types(facts: Array) -> Array:
	var rows: Array = []
	for fact: Dictionary in facts:
		rows.append(str(fact.get("fact_type", fact.get("type", ""))))
	return rows


func _fact_ids(facts: Array) -> Array:
	var rows: Array = []
	for fact: Dictionary in facts:
		rows.append(str(fact.get("fact_id", "")))
	return rows


func _narrative_summaries(narrative_results: Array) -> String:
	var text := ""
	for narrative_result: Dictionary in narrative_results:
		var summary := _narrative_summary(narrative_result)
		if summary == "":
			continue
		if text != "":
			text += " | "
		text += summary
	return text


func _narrative_summary(narrative_result: Dictionary) -> String:
	if narrative_result.has("summary"):
		return str(narrative_result.get("summary", ""))
	return str(narrative_result.get("body", ""))


func _store_summary(stores: Dictionary) -> Dictionary:
	return {
		"facts": _list_size(stores.get("fact_store"), "list_facts"),
		"memories": _array_property_size(stores.get("memory_store"), "memories"),
		"traces": _list_size(stores.get("trace_store"), "list_traces"),
		"rumors": _list_size(stores.get("rumor_store"), "list_rumors"),
		"pressures": _list_size(stores.get("pressure_store"), "list_pressures"),
		"obligations": _list_size(stores.get("obligation_store"), "list_obligations"),
		"exchanges": _list_size(stores.get("exchange_store"), "list_exchanges"),
		"deferred_consequences": _list_size(
			stores.get("deferred_consequence_store"),
			"list_deferred_consequences"
		),
	}


func _list_size(store: Variant, method_name: String) -> int:
	if store != null and store.has_method(method_name):
		return store.call(method_name).size()
	return 0


func _array_property_size(store: Variant, property_name: String) -> int:
	if store == null:
		return 0
	var value: Variant = store.get(property_name)
	return value.size() if value is Array else 0
