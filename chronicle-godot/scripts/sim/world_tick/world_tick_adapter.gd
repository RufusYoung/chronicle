extends RefCounted
class_name V5WorldTickAdapter

const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ConsequenceTriggerSystemModel = preload("res://scripts/sim/consequence/consequence_trigger_system.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")

const ENTRY_TYPE_TICK_EVENT := "tick_event"
const SOURCE := "WorldTickAdapter"


func apply_tick_event(context: Variant, stores: Dictionary, tick_event: Dictionary) -> Dictionary:
	var tick_event_id := str(tick_event.get("tick_event_id", ""))
	var trigger_key := str(tick_event.get("trigger_key", ""))

	if not stores.has("deferred_consequence_store") or stores.get("deferred_consequence_store") == null:
		return _failure_result(
			tick_event_id,
			trigger_key,
			"missing_deferred_consequence_store",
			stores
		)
	if trigger_key == "":
		return _failure_result(tick_event_id, trigger_key, "missing_trigger_key", stores)

	var snapshot_builder = SimSnapshotBuilderModel.new()
	var trigger_system = ConsequenceTriggerSystemModel.new()
	var writer = TransactionWorldWriterModel.new()
	var world_log = SimWorldLogModel.new()

	var snapshot = snapshot_builder.build_snapshot(context, stores)
	var transaction_results: Array = trigger_system.trigger_deferred_by_key(snapshot, trigger_key)
	var result_rows: Array = []

	for index: int in range(transaction_results.size()):
		var result: Variant = transaction_results[index]
		writer.apply_result(result, stores)
		result_rows.append(result.to_dict())
		world_log.append_entry(_build_tick_log_entry(
			index,
			tick_event,
			trigger_key,
			result
		))

	return {
		"success": true,
		"tick_event_id": tick_event_id,
		"trigger_key": trigger_key,
		"triggered_count": transaction_results.size(),
		"results": result_rows,
		"world_log_entries": world_log.list_entries(),
		"world_log_summary": world_log.summary(),
		"store_summary": _store_summary(stores),
	}


func _failure_result(
	tick_event_id: String,
	trigger_key: String,
	error_reason: String,
	stores: Dictionary
) -> Dictionary:
	return {
		"success": false,
		"tick_event_id": tick_event_id,
		"trigger_key": trigger_key,
		"triggered_count": 0,
		"error_reason": error_reason,
		"results": [],
		"world_log_entries": [],
		"world_log_summary": {},
		"store_summary": _store_summary(stores),
	}


func _build_tick_log_entry(
	result_index: int,
	tick_event: Dictionary,
	trigger_key: String,
	result: Variant
) -> Dictionary:
	return {
		"entry_type": ENTRY_TYPE_TICK_EVENT,
		"tick_event_id": str(tick_event.get("tick_event_id", "")),
		"trigger_key": trigger_key,
		"source": SOURCE,
		"result_index": result_index,
		"rule_id": "world_tick_adapter",
		"action_id": str(tick_event.get("tick_event_id", "")),
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"pressure_changes": result.pressure_changes.duplicate(true),
		"pressure_change_count": result.pressure_changes.size(),
		"deferred_consequence_updates": result.deferred_consequence_updates.duplicate(true),
		"deferred_consequence_update_count": result.deferred_consequence_updates.size(),
		"obligation_update_count": result.obligation_updates.size(),
		"exchange_update_count": result.exchange_updates.size(),
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


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
