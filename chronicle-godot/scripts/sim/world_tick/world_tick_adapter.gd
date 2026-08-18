extends RefCounted
class_name V5WorldTickAdapter

const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const ConsequenceTriggerSystemModel = preload("res://scripts/sim/consequence/consequence_trigger_system.gd")
const DueTriggerSystemModel = preload("res://scripts/sim/consequence/due_trigger_system.gd")
const NpcDecisionSystemModel = preload(
	"res://scripts/sim/npc/npc_decision_system.gd"
)
const NpcNeedSystemModel = preload(
	"res://scripts/sim/npc/npc_need_system.gd"
)
const NpcLivelihoodSystemModel = preload(
	"res://scripts/sim/npc/npc_livelihood_system.gd"
)
const NpcSocialFollowupSystemModel = preload(
	"res://scripts/sim/npc/npc_social_followup_system.gd"
)
const SettlementResourceSystemModel = preload(
	"res://scripts/sim/resource/settlement_resource_system.gd"
)
const SettlementNetworkSystemModel = preload(
	"res://scripts/sim/resource/settlement_network_system.gd"
)
const SettlementAbsorptionSystemModel = preload(
	"res://scripts/sim/migration/settlement_absorption_system.gd"
)
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const TickEventSchemaModel = preload("res://scripts/sim/world_tick/tick_event_schema.gd")

const ENTRY_TYPE_TICK_EVENT := "tick_event"
const SOURCE := "WorldTickAdapter"

var autonomous_action_rules: Array = []
var npc_need_profiles: Array = []
var npc_livelihood_profiles: Array = []
var settlement_network_config: Dictionary = {}
var registry: Variant = null


func configure_registry(source_registry: Variant) -> void:
	registry = source_registry


func configure_autonomous_actions(rules: Array) -> void:
	autonomous_action_rules = rules.duplicate(true)


func configure_need_profiles(profiles: Array) -> void:
	npc_need_profiles = profiles.duplicate(true)


func configure_livelihood_profiles(profiles: Array) -> void:
	npc_livelihood_profiles = profiles.duplicate(true)


func configure_settlement_network(config: Dictionary) -> void:
	settlement_network_config = config.duplicate(true)


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
	var include_due_checks := bool(event.get("include_due_checks", false))
	var due_kinds: Array = event.get("due_kinds", [])
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
	var due_results: Array = []
	var autonomous_results: Array = []
	var autonomous_decisions: Array = []
	var observed_autonomous_results: Array = []
	var observed_autonomous_decisions: Array = []
	var need_results: Array = []
	var need_changes: Array = []
	var observed_need_results: Array = []
	var observed_need_changes: Array = []
	var livelihood_results: Array = []
	var livelihood_events: Array = []
	var resource_results: Array = []
	var resource_events: Array = []
	var network_results: Array = []
	var network_events: Array = []
	var social_followup_results: Array = []
	var social_followup_events: Array = []
	var autonomous_actor_ids: Dictionary = {}
	var autonomous_actor_count := 0
	var obligation_due_count := 0
	var exchange_due_count := 0

	for consequence: Dictionary in selected_consequences:
		var deferred_id := str(consequence.get("deferred_id", ""))
		if deferred_id == "":
			continue
		var result: Variant = trigger_system.trigger_deferred(snapshot, deferred_id)
		writer.apply_result(result, stores)
		transaction_results.append(result)

	if include_due_checks:
		var due_snapshot = snapshot_builder.build_snapshot(context, stores)
		var due_trigger_system = DueTriggerSystemModel.new()
		var due_result_data: Dictionary = due_trigger_system.trigger_due_for_tick(due_snapshot, event)
		var obligation_results: Array = due_result_data.get("obligation_results", [])
		var exchange_results: Array = due_result_data.get("exchange_results", [])
		obligation_due_count = int(due_result_data.get("obligation_due_count", obligation_results.size()))
		exchange_due_count = int(due_result_data.get("exchange_due_count", exchange_results.size()))
		due_results.append_array(obligation_results)
		due_results.append_array(exchange_results)
		for due_result: Variant in due_results:
			writer.apply_result(due_result, stores)

	var elapsed_hours := int(event.get("elapsed_hours", 0))
	var simulation_round_count := maxi(elapsed_hours, 1)
	for round_index: int in range(simulation_round_count):
		var round_event := event.duplicate(true)
		round_event["elapsed_hours"] = 1 if elapsed_hours > 0 else 0
		if simulation_round_count > 1:
			round_event["tick_event_id"] = "%s:hour_%d" % [
				tick_event_id,
				round_index + 1,
			]
		if event.has("start_day") and event.has("start_hour"):
			var round_absolute_hour := int(event.get(
				"start_hour", 0
			)) + round_index + (1 if elapsed_hours > 0 else 0)
			round_event["day"] = int(event.get("start_day", 1)) + int(
				round_absolute_hour / 24
			)
			round_event["hour"] = posmod(round_absolute_hour, 24)

		var resource_store: Variant = stores.get("resource_stock_store")
		if (
			resource_store != null
			and not resource_store.list_stocks().is_empty()
		):
			var resource_system = SettlementResourceSystemModel.new()
			var recovery_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var recovery_data: Dictionary = (
				resource_system.resolve_recovery_tick(
					recovery_snapshot,
					round_event
				)
			)
			var recovery_results: Array = recovery_data.get("results", [])
			for recovery_result: Variant in recovery_results:
				writer.apply_result(recovery_result, stores)
			resource_results.append_array(recovery_results)
			resource_events.append_array(recovery_data.get("events", []))

		if not npc_need_profiles.is_empty():
			var need_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var need_system = NpcNeedSystemModel.new()
			var need_data: Dictionary = need_system.resolve_tick(
				need_snapshot,
				npc_need_profiles,
				round_event
			)
			var round_need_results: Array = need_data.get("results", [])
			var round_need_changes: Array = need_data.get("changes", [])
			var observed_result_indexes: Array = need_data.get(
				"observed_result_indexes",
				[]
			)
			for index: int in range(round_need_results.size()):
				var need_result: Variant = round_need_results[index]
				writer.apply_result(need_result, stores)
				if index in observed_result_indexes:
					observed_need_results.append(need_result)
			for change: Dictionary in round_need_changes:
				if bool(change.get("observed_by_player", false)):
					observed_need_changes.append(change.duplicate(true))
			need_results.append_array(round_need_results)
			need_changes.append_array(round_need_changes)

		if not npc_livelihood_profiles.is_empty():
			var livelihood_system = NpcLivelihoodSystemModel.new()
			var work_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var work_data: Dictionary = livelihood_system.resolve_work_tick(
				work_snapshot,
				npc_livelihood_profiles,
				round_event
			)
			var work_results: Array = work_data.get("results", [])
			for work_result: Variant in work_results:
				writer.apply_result(work_result, stores)
			livelihood_results.append_array(work_results)
			livelihood_events.append_array(work_data.get("events", []))

			var support_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var support_data: Dictionary = (
				livelihood_system.resolve_household_support(
					support_snapshot,
					round_event
				)
			)
			var support_results: Array = support_data.get("results", [])
			for support_result: Variant in support_results:
				writer.apply_result(support_result, stores)
			livelihood_results.append_array(support_results)
			livelihood_events.append_array(support_data.get("events", []))

			var followup_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var followup_system = NpcSocialFollowupSystemModel.new()
			var followup_data: Dictionary = followup_system.resolve_tick(
				followup_snapshot,
				round_event
			)
			var round_followup_results: Array = followup_data.get("results", [])
			for followup_result: Variant in round_followup_results:
				writer.apply_result(followup_result, stores)
			social_followup_results.append_array(round_followup_results)
			social_followup_events.append_array(followup_data.get("events", []))

		if (
			resource_store != null
			and not resource_store.list_stocks().is_empty()
		):
			var status_system = SettlementResourceSystemModel.new()
			var status_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var status_data: Dictionary = status_system.resolve_status_tick(
				status_snapshot,
				round_event,
				str(context.region_entity_id)
			)
			var status_results: Array = status_data.get("results", [])
			for status_result: Variant in status_results:
				writer.apply_result(status_result, stores)
			resource_results.append_array(status_results)
			resource_events.append_array(status_data.get("events", []))

		if not settlement_network_config.is_empty():
			var network_system = SettlementNetworkSystemModel.new()
			var consumption_snapshot = snapshot_builder.build_snapshot(
				context, stores, true
			)
			var consumption_data: Dictionary = (
				network_system.resolve_daily_consumption(
					consumption_snapshot,
					round_event,
					settlement_network_config
				)
			)
			var consumption_results: Array = consumption_data.get("results", [])
			for consumption_result: Variant in consumption_results:
				writer.apply_result(consumption_result, stores)
			network_results.append_array(consumption_results)
			network_events.append_array(consumption_data.get("events", []))

			var trade_snapshot = snapshot_builder.build_snapshot(
				context, stores, true
			)
			var trade_data: Dictionary = network_system.resolve_trade_tick(
				trade_snapshot,
				round_event,
				settlement_network_config
			)
			var trade_results: Array = trade_data.get("results", [])
			for trade_result: Variant in trade_results:
				writer.apply_result(trade_result, stores)
			network_results.append_array(trade_results)
			network_events.append_array(trade_data.get("events", []))

			var migration_snapshot = snapshot_builder.build_snapshot(
				context, stores, true
			)
			var migration_data: Dictionary = network_system.resolve_migration_tick(
				migration_snapshot,
				round_event,
				settlement_network_config
			)
			var migration_results: Array = migration_data.get("results", [])
			for migration_result: Variant in migration_results:
				writer.apply_result(migration_result, stores)
			network_results.append_array(migration_results)
			network_events.append_array(migration_data.get("events", []))

			var absorption_snapshot = snapshot_builder.build_snapshot(
				context, stores, true
			)
			var absorption_data: Dictionary = (
				SettlementAbsorptionSystemModel.new().resolve_tick(
					absorption_snapshot,
					round_event,
					settlement_network_config,
					npc_livelihood_profiles,
					context.get_locations()
				)
			)
			var absorption_results: Array = absorption_data.get("results", [])
			for absorption_result: Variant in absorption_results:
				writer.apply_result(absorption_result, stores)
			network_results.append_array(absorption_results)
			network_events.append_array(absorption_data.get("events", []))

		if not autonomous_action_rules.is_empty():
			var decision_snapshot = snapshot_builder.build_snapshot(
				context,
				stores,
				true
			)
			var decision_system = NpcDecisionSystemModel.new()
			decision_system.configure(registry)
			var decision_data: Dictionary = decision_system.resolve_tick(
				decision_snapshot,
				autonomous_action_rules,
				round_event
			)
			var round_results: Array = decision_data.get("results", [])
			var round_decisions: Array = decision_data.get("decisions", [])
			for index: int in range(round_results.size()):
				var autonomous_result: Variant = round_results[index]
				writer.apply_result(autonomous_result, stores)
				if index < round_decisions.size():
					var decision := round_decisions[index] as Dictionary
					autonomous_actor_ids[str(decision.get("actor_id", ""))] = true
					if bool(decision.get("observed_by_player", false)):
						observed_autonomous_results.append(autonomous_result)
						observed_autonomous_decisions.append(decision)
			autonomous_results.append_array(round_results)
			autonomous_decisions.append_array(round_decisions)
	autonomous_actor_ids.erase("")
	autonomous_actor_count = autonomous_actor_ids.size()

	var skipped_count := (
		skipped_due_to_scope_count
		+ skipped_due_to_status_count
		+ skipped_due_to_limit_count
	)
	var tick_log_results := transaction_results.duplicate()
	tick_log_results.append_array(due_results)
	tick_log_results.append_array(need_results)
	tick_log_results.append_array(livelihood_results)
	tick_log_results.append_array(social_followup_results)
	tick_log_results.append_array(resource_results)
	tick_log_results.append_array(network_results)
	tick_log_results.append_array(autonomous_results)
	world_log.append_entry(_build_tick_log_entry(
		event,
		tick_log_results,
		matched_consequences.size(),
		transaction_results.size(),
		skipped_count,
		skipped_due_to_scope_count,
		skipped_due_to_status_count,
		skipped_due_to_limit_count,
		"",
		[],
		[],
		obligation_due_count,
		exchange_due_count,
		due_results,
		need_changes,
		autonomous_actor_count,
		autonomous_decisions
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
		"include_due_checks": include_due_checks,
		"due_kinds": due_kinds.duplicate(true),
		"matched_count": matched_consequences.size(),
		"triggered_count": transaction_results.size(),
		"skipped_count": skipped_count,
		"skipped_due_to_scope_count": skipped_due_to_scope_count,
		"skipped_due_to_status_count": skipped_due_to_status_count,
		"skipped_due_to_limit_count": skipped_due_to_limit_count,
		"obligation_due_count": obligation_due_count,
		"exchange_due_count": exchange_due_count,
		"due_result_count": due_results.size(),
		"simulation_round_count": simulation_round_count,
		"need_change_count": need_changes.size(),
		"need_changes": need_changes.duplicate(true),
		"observed_need_change_count": observed_need_changes.size(),
		"observed_need_changes": observed_need_changes.duplicate(true),
		"autonomous_actor_count": autonomous_actor_count,
		"autonomous_decision_count": autonomous_decisions.size(),
		"autonomous_decisions": autonomous_decisions.duplicate(true),
		"observed_autonomous_decision_count": (
			observed_autonomous_decisions.size()
		),
		"observed_autonomous_decisions": (
			observed_autonomous_decisions.duplicate(true)
		),
		"error_reason": "",
		"results": _result_rows(transaction_results),
		"due_results": _result_rows(due_results),
		"need_results": _result_rows(need_results),
		"observed_need_results": _result_rows(observed_need_results),
		"livelihood_result_count": livelihood_results.size(),
		"livelihood_results": _result_rows(livelihood_results),
		"livelihood_event_count": livelihood_events.size(),
		"livelihood_events": livelihood_events.duplicate(true),
		"resource_result_count": resource_results.size(),
		"resource_results": _result_rows(resource_results),
		"resource_event_count": resource_events.size(),
		"resource_events": resource_events.duplicate(true),
		"network_result_count": network_results.size(),
		"network_results": _result_rows(network_results),
		"network_event_count": network_events.size(),
		"network_events": network_events.duplicate(true),
		"social_followup_result_count": social_followup_results.size(),
		"social_followup_results": _result_rows(social_followup_results),
		"social_followup_event_count": social_followup_events.size(),
		"social_followup_events": social_followup_events.duplicate(true),
		"autonomous_results": _result_rows(autonomous_results),
		"observed_autonomous_results": _result_rows(
			observed_autonomous_results
		),
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
		"include_due_checks": bool(tick_event.get("include_due_checks", false)),
		"due_kinds": (tick_event.get("due_kinds", []) as Array).duplicate(true) if tick_event.get("due_kinds", []) is Array else [],
		"matched_count": 0,
		"triggered_count": 0,
		"skipped_count": 0,
		"skipped_due_to_scope_count": 0,
		"skipped_due_to_status_count": 0,
		"skipped_due_to_limit_count": 0,
		"obligation_due_count": 0,
		"exchange_due_count": 0,
		"due_result_count": 0,
		"need_change_count": 0,
		"need_changes": [],
		"observed_need_change_count": 0,
		"observed_need_changes": [],
		"autonomous_actor_count": 0,
		"autonomous_decision_count": 0,
		"autonomous_decisions": [],
		"observed_autonomous_decision_count": 0,
		"observed_autonomous_decisions": [],
		"error_reason": error_reason,
		"validation_errors": validation_errors.duplicate(true),
		"validation_warnings": validation_warnings.duplicate(true),
		"results": [],
		"due_results": [],
		"need_results": [],
		"observed_need_results": [],
		"livelihood_result_count": 0,
		"livelihood_results": [],
		"livelihood_event_count": 0,
		"livelihood_events": [],
		"resource_result_count": 0,
		"resource_results": [],
		"resource_event_count": 0,
		"resource_events": [],
		"network_result_count": 0,
		"network_results": [],
		"network_event_count": 0,
		"network_events": [],
		"autonomous_results": [],
		"observed_autonomous_results": [],
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
	validation_warnings: Array = [],
	obligation_due_count: int = 0,
	exchange_due_count: int = 0,
	due_results: Array = [],
	need_changes: Array = [],
	autonomous_actor_count: int = 0,
	autonomous_decisions: Array = []
) -> Dictionary:
	var aggregate := _aggregate_results(results)
	var pressure_changes: Array = aggregate.get("pressure_changes", [])
	var state_changes: Array = aggregate.get("state_changes", [])
	var relationship_changes: Array = aggregate.get("relationship_changes", [])
	var memories: Array = aggregate.get("memories", [])
	var traces: Array = aggregate.get("traces", [])
	var rumors: Array = aggregate.get("rumors", [])
	var obligations: Array = aggregate.get("obligations", [])
	var exchanges: Array = aggregate.get("exchanges", [])
	var deferred_consequences: Array = aggregate.get("deferred_consequences", [])
	var item_changes: Array = aggregate.get("item_changes", [])
	var resource_changes: Array = aggregate.get("resource_changes", [])
	var chronicle_entries: Array = aggregate.get("chronicle_entries", [])
	var investigation_changes: Array = aggregate.get("investigation_changes", [])
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
		"elapsed_hours": int(tick_event.get("elapsed_hours", 0)),
		"source": _entry_source(tick_event),
		"include_due_checks": bool(tick_event.get("include_due_checks", false)),
		"due_kinds": (tick_event.get("due_kinds", []) as Array).duplicate(true) if tick_event.get("due_kinds", []) is Array else [],
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
		"obligation_due_count": obligation_due_count,
		"exchange_due_count": exchange_due_count,
		"due_result_count": due_results.size(),
		"due_results": _result_rows(due_results),
		"need_change_count": need_changes.size(),
		"need_changes": need_changes.duplicate(true),
		"observed_need_change_count": _observed_need_change_count(
			need_changes
		),
		"autonomous_actor_count": autonomous_actor_count,
		"autonomous_decision_count": autonomous_decisions.size(),
		"autonomous_decisions": autonomous_decisions.duplicate(true),
		"observed_autonomous_decision_count": _observed_decision_count(
			autonomous_decisions
		),
		"facts_added": _fact_types(aggregate.get("facts", [])),
		"fact_ids": _fact_ids(aggregate.get("facts", [])),
		"state_change_count": state_changes.size(),
		"relationship_change_count": relationship_changes.size(),
		"memory_count": memories.size(),
		"trace_count": traces.size(),
		"rumor_seed_count": rumors.size(),
		"pressure_changes": pressure_changes.duplicate(true),
		"pressure_change_count": pressure_changes.size(),
		"obligation_count": obligations.size(),
		"exchange_count": exchanges.size(),
		"deferred_consequence_count": deferred_consequences.size(),
		"deferred_consequence_updates": deferred_updates.duplicate(true),
		"deferred_consequence_update_count": deferred_updates.size(),
		"obligation_update_count": obligation_updates.size(),
		"exchange_update_count": exchange_updates.size(),
		"item_change_count": item_changes.size(),
		"resource_change_count": resource_changes.size(),
		"chronicle_entry_count": chronicle_entries.size(),
		"investigation_change_count": investigation_changes.size(),
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
	var state_changes: Array = []
	var relationship_changes: Array = []
	var memories: Array = []
	var traces: Array = []
	var rumors: Array = []
	var pressure_changes: Array = []
	var obligations: Array = []
	var exchanges: Array = []
	var deferred_consequences: Array = []
	var obligation_updates: Array = []
	var exchange_updates: Array = []
	var deferred_updates: Array = []
	var item_changes: Array = []
	var resource_changes: Array = []
	var chronicle_entries: Array = []
	var investigation_changes: Array = []
	var narrative_results: Array = []

	for result: Variant in results:
		if result == null:
			continue
		facts.append_array(result.facts_added.duplicate(true))
		state_changes.append_array(result.state_changes.duplicate(true))
		relationship_changes.append_array(
			result.relationship_changes.duplicate(true)
		)
		memories.append_array(result.memories_added.duplicate(true))
		traces.append_array(result.traces_added.duplicate(true))
		rumors.append_array(result.rumors_added.duplicate(true))
		pressure_changes.append_array(result.pressure_changes.duplicate(true))
		obligations.append_array(result.obligations_added.duplicate(true))
		exchanges.append_array(result.exchanges_added.duplicate(true))
		deferred_consequences.append_array(
			result.deferred_consequences_added.duplicate(true)
		)
		obligation_updates.append_array(result.obligation_updates.duplicate(true))
		exchange_updates.append_array(result.exchange_updates.duplicate(true))
		deferred_updates.append_array(result.deferred_consequence_updates.duplicate(true))
		item_changes.append_array(result.item_changes.duplicate(true))
		resource_changes.append_array(result.resource_changes.duplicate(true))
		chronicle_entries.append_array(
			result.chronicle_entries_added.duplicate(true)
		)
		investigation_changes.append_array(
			result.investigation_changes.duplicate(true)
		)
		if not result.narrative_result.is_empty():
			narrative_results.append(result.narrative_result.duplicate(true))

	return {
		"facts": facts,
		"state_changes": state_changes,
		"relationship_changes": relationship_changes,
		"memories": memories,
		"traces": traces,
		"rumors": rumors,
		"pressure_changes": pressure_changes,
		"obligations": obligations,
		"exchanges": exchanges,
		"deferred_consequences": deferred_consequences,
		"obligation_updates": obligation_updates,
		"exchange_updates": exchange_updates,
		"deferred_consequence_updates": deferred_updates,
		"item_changes": item_changes,
		"resource_changes": resource_changes,
		"chronicle_entries": chronicle_entries,
		"investigation_changes": investigation_changes,
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


func _observed_decision_count(decisions: Array) -> int:
	var count := 0
	for decision: Dictionary in decisions:
		if bool(decision.get("observed_by_player", false)):
			count += 1
	return count


func _observed_need_change_count(changes: Array) -> int:
	var count := 0
	for change: Dictionary in changes:
		if bool(change.get("observed_by_player", false)):
			count += 1
	return count


func _store_summary(stores: Dictionary) -> Dictionary:
	return {
		"facts": _list_size(stores.get("fact_store"), "list_facts"),
		"memories": _array_property_size(stores.get("memory_store"), "memories"),
		"traces": _list_size(stores.get("trace_store"), "list_traces"),
		"rumors": _list_size(stores.get("rumor_store"), "list_rumors"),
		"pressures": _list_size(stores.get("pressure_store"), "list_pressures"),
		"resource_stocks": _list_size(
			stores.get("resource_stock_store"), "list_stocks"
		),
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
