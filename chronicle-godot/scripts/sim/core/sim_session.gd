extends RefCounted
class_name V5SimSession

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const TravelResolverModel = preload("res://scripts/sim/travel/travel_resolver.gd")
const WorldTickAdapterModel = preload(
	"res://scripts/sim/world_tick/world_tick_adapter.gd"
)
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")
const PressureStoreModel = preload("res://scripts/sim/pressure/pressure_store.gd")
const ObligationStoreModel = preload("res://scripts/sim/obligation/obligation_store.gd")
const ExchangeStoreModel = preload("res://scripts/sim/exchange/exchange_store.gd")
const DeferredConsequenceStoreModel = preload(
	"res://scripts/sim/deferred/deferred_consequence_store.gd"
)

const RELATIONSHIP_AXIS_DEFS_PATH := (
	"res://data/sim/raw/relationship_defs/relationship_axis_defs.json"
)

var registry: Variant = null
var context: Variant = null
var rules: Array = []
var stores: Dictionary = {}
var world_log: Variant = null
var snapshot_builder: Variant = null
var affordance_system: Variant = null
var resolver: Variant = null
var writer: Variant = null
var travel_resolver: Variant = null
var world_tick_adapter: Variant = null
var travel_routes: Array = []

var fixture_id: String = ""
var initialized: bool = false
var action_count: int = 0
var travel_count: int = 0
var candidate_generation_count: int = 0
var world_tick_count: int = 0
var current_day: int = 1
var current_hour: int = 8
var elapsed_hours_since_start: int = 0


func start_from_fixture_path(fixture_path: String, raw_rule_paths: Array) -> Dictionary:
	var loader = SimRegistryModel.new()
	var fixture: Dictionary = loader.load_json(fixture_path)
	if fixture.is_empty():
		_reset_runtime()
		return _start_failure("fixture_not_loaded")
	return start_from_fixture_data(fixture, raw_rule_paths)


func start_from_fixture_data(fixture: Dictionary, raw_rule_paths: Array) -> Dictionary:
	_reset_runtime()
	if fixture.is_empty():
		return _start_failure("fixture_not_loaded")

	registry.load_action_rules(raw_rule_paths)
	rules = registry.get_action_rules()
	context = SimContextModel.new(fixture)
	fixture_id = str(fixture.get("fixture_id", ""))
	if fixture_id == "":
		return _start_failure("missing_fixture_id")

	_configure_world_time(fixture)
	travel_routes = (fixture.get("travel_routes", []) as Array).duplicate(true)
	_create_stores(fixture)
	initialized = true
	return {
		"success": true,
		"fixture_id": fixture_id,
		"rule_count": rules.size(),
		"candidate_count": get_action_candidates().size(),
		"time": get_time_summary(),
	}


func is_ready() -> bool:
	return initialized


func get_snapshot() -> Variant:
	if not initialized:
		return null
	return snapshot_builder.build_snapshot(context, stores)


func get_action_candidates() -> Array:
	var snapshot: Variant = get_snapshot()
	if snapshot == null:
		return []
	return affordance_system.generate_candidates(snapshot, rules)


func get_action_options() -> Array:
	var rows: Array = []
	for candidate: Variant in get_action_candidates():
		rows.append(candidate.to_dict())
	return rows


func get_travel_options() -> Array:
	if not initialized:
		return []
	var rows: Array = []
	var food_count := int(context.get_player_value("food_count", 0))
	for route: Dictionary in travel_routes:
		if str(route.get("from_location_id", "")) != context.location_id:
			continue
		var to_location_id := str(route.get("to_location_id", ""))
		var destination: Dictionary = context.get_location(to_location_id)
		var route_food_cost := int(route.get("food_cost", 0))
		var food_cost := maxi(route_food_cost, 0)
		var can_travel := (
			not destination.is_empty()
			and int(route.get("hours", 0)) > 0
			and route_food_cost >= 0
			and food_count >= food_cost
		)
		rows.append({
			"route_id": str(route.get("route_id", "")),
			"from_location_id": context.location_id,
			"to_location_id": to_location_id,
			"destination_name": str(
				destination.get("display_name", to_location_id)
			),
			"label": str(route.get("label", "前往新的地点")),
			"hours": int(route.get("hours", 0)),
			"food_cost": food_cost,
			"can_travel": can_travel,
			"blocked_reason": (
				"" if can_travel else _travel_blocked_reason(
					destination,
					int(route.get("hours", 0)),
					food_count,
					route_food_cost
				)
			),
		})
	return rows


func travel(route_id: String, metadata: Dictionary = {}) -> Dictionary:
	if not initialized:
		return _travel_failure("session_not_initialized", route_id)

	var route := _find_travel_route(route_id, context.location_id)
	if route.is_empty():
		return _travel_failure("route_not_found", route_id)

	var to_location_id := str(route.get("to_location_id", ""))
	var destination: Dictionary = context.get_location(to_location_id)
	var hours := int(route.get("hours", 0))
	var food_cost := int(route.get("food_cost", 0))
	if destination.is_empty():
		return _travel_failure("destination_not_found", route_id)
	if hours <= 0 or food_cost < 0:
		return _travel_failure("invalid_route_contract", route_id)
	if int(context.get_player_value("food_count", 0)) < food_cost:
		return _travel_failure("insufficient_food", route_id)

	var from_location_id: String = str(context.location_id)
	var tick_metadata := {
		"scope_type": "location",
		"scope_id": from_location_id,
		"source": "SimSession.travel",
		"label": str(route.get("label", "travel")),
		"time_key": str(route.get("time_key", "after_route_travel")),
		"include_due_checks": true,
	}
	var raw_tick_metadata: Variant = metadata.get("tick_metadata", {})
	if not raw_tick_metadata is Dictionary:
		return _travel_failure("invalid_tick_metadata", route_id)
	tick_metadata.merge(
		(raw_tick_metadata as Dictionary),
		true
	)
	tick_metadata["scope_type"] = "location"
	tick_metadata["scope_id"] = from_location_id
	var tick_result := advance_time(
		hours,
		str(route.get("trigger_key", "after_route_travel")),
		tick_metadata
	)
	if not bool(tick_result.get("success", false)):
		return _travel_failure(
			str(tick_result.get("error_reason", "world_tick_failed")),
			route_id
		)

	var snapshot: Variant = get_snapshot()
	var transaction_result: Variant = travel_resolver.resolve(
		route,
		snapshot,
		travel_count + 1
	)
	writer.apply_result(transaction_result, stores)
	_sync_context_after_result(transaction_result)
	if not context.set_current_location(to_location_id):
		return _travel_failure("destination_switch_failed", route_id)

	var log_entry := _build_travel_log_entry(
		route,
		transaction_result,
		travel_count
	)
	world_log.append_entry(log_entry)
	travel_count += 1
	return {
		"success": true,
		"error": "",
		"fixture_id": fixture_id,
		"route_id": route_id,
		"from_location_id": from_location_id,
		"to_location_id": to_location_id,
		"destination": destination.duplicate(true),
		"hours": hours,
		"food_cost": food_cost,
		"transaction_result": transaction_result.to_dict(),
		"tick_result": tick_result,
		"world_log_entry": log_entry.duplicate(true),
		"time": get_time_summary(),
		"travel_count": travel_count,
		"store_summary": get_store_summary(),
	}


func execute_action(action_id: String, metadata: Dictionary = {}) -> Dictionary:
	if not initialized:
		return _execution_failure("session_not_initialized", action_id)

	var snapshot: Variant = get_snapshot()
	var candidates: Array = affordance_system.generate_candidates(snapshot, rules)
	candidate_generation_count += 1
	var candidate: Variant = _find_candidate_by_action_id(candidates, action_id)
	if candidate == null:
		return _candidate_not_found(action_id, "", "", candidates)
	return _execute_candidate(snapshot, candidate, candidates.size(), metadata)


func execute_selection(
		rule_id: String,
		target_id: String = "",
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _execution_failure("session_not_initialized", "")

	var snapshot: Variant = get_snapshot()
	var candidates: Array = affordance_system.generate_candidates(snapshot, rules)
	candidate_generation_count += 1
	var candidate: Variant = _find_candidate(candidates, rule_id, target_id)
	if candidate == null:
		return _candidate_not_found("", rule_id, target_id, candidates)
	return _execute_candidate(snapshot, candidate, candidates.size(), metadata)


func advance_time(
		hours: int,
		trigger_key: String,
		metadata: Dictionary = {}
) -> Dictionary:
	if not initialized:
		return _tick_failure("session_not_initialized")
	if hours <= 0:
		return _tick_failure("invalid_elapsed_hours")

	var scope_type := str(metadata.get("scope_type", "location"))
	var scope_id := str(metadata.get("scope_id", context.location_id))
	var next_time := _projected_time(hours)
	var due_kinds_value: Variant = metadata.get(
		"due_kinds",
		["obligation", "exchange"]
	)
	if not (due_kinds_value is Array):
		return _tick_failure("invalid_due_kinds")
	var due_kinds: Array = (due_kinds_value as Array).duplicate(true)
	var tick_event := {
		"tick_event_id": str(metadata.get(
			"tick_event_id",
			"%s_time_%d" % [fixture_id, world_tick_count + 1]
		)),
		"tick_type": "time_event",
		"trigger_key": trigger_key,
		"scope_type": scope_type,
		"scope_id": scope_id,
		"day": int(next_time.get("day", current_day)),
		"time_key": str(metadata.get("time_key", trigger_key)),
		"source": str(metadata.get("source", "SimSession.advance_time")),
		"label": str(metadata.get("label", "advance time")),
		"max_triggers": int(metadata.get("max_triggers", 0)),
		"include_due_checks": bool(metadata.get("include_due_checks", true)),
		"due_kinds": due_kinds,
	}
	return advance_world(tick_event, hours)


func advance_world(tick_event: Dictionary, elapsed_hours_delta: int = 0) -> Dictionary:
	if not initialized:
		return _tick_failure("session_not_initialized")

	var result: Dictionary = world_tick_adapter.apply_tick_event(
		context,
		stores,
		tick_event
	)
	for entry: Dictionary in result.get("world_log_entries", []):
		world_log.append_entry(entry)

	if bool(result.get("success", false)):
		_sync_context_after_tick_result(result)
		_advance_clock(maxi(elapsed_hours_delta, 0))
		world_tick_count += 1

	result["fixture_id"] = fixture_id
	result["time"] = get_time_summary()
	result["world_tick_count"] = world_tick_count
	result["session_world_log_summary"] = get_world_log_summary()
	return result


func get_time_summary() -> Dictionary:
	return {
		"day": current_day,
		"hour": current_hour,
		"world_tick_count": world_tick_count,
		"elapsed_hours": elapsed_hours_since_start,
	}


func get_world_log_entries() -> Array:
	if world_log == null:
		return []
	return world_log.list_entries()


func get_world_log_summary() -> Dictionary:
	if world_log == null:
		return {}
	return world_log.summary()


func get_store_summary() -> Dictionary:
	if not initialized:
		return _empty_store_summary()
	return {
		"facts": stores["fact_store"].list_facts().size(),
		"states": _count_states(stores["state_store"]),
		"relationships": _count_relationship_axes(stores["relationship_store"]),
		"memories": stores["memory_store"].memories.size(),
		"traces": stores["trace_store"].list_traces().size(),
		"rumors": stores["rumor_store"].list_rumors().size(),
		"pressures": stores["pressure_store"].list_pressures().size(),
		"obligations": stores["obligation_store"].list_obligations().size(),
		"exchanges": stores["exchange_store"].list_exchanges().size(),
		"deferred_consequences": (
			stores["deferred_consequence_store"]
			.list_deferred_consequences()
			.size()
		),
	}


func get_store_snapshots() -> Dictionary:
	if not initialized:
		return {}
	return {
		"facts": stores["fact_store"].list_facts(),
		"states": stores["state_store"].states.duplicate(true),
		"relationships": stores["relationship_store"].relations.duplicate(true),
		"memories": stores["memory_store"].memories.duplicate(true),
		"traces": stores["trace_store"].list_traces(),
		"rumors": stores["rumor_store"].list_rumors(),
		"pressures": stores["pressure_store"].list_pressures(),
		"obligations": stores["obligation_store"].list_obligations(),
		"exchanges": stores["exchange_store"].list_exchanges(),
		"deferred_consequences": (
			stores["deferred_consequence_store"].list_deferred_consequences()
		),
	}


func build_result_summary(extra: Dictionary = {}) -> Dictionary:
	if not initialized:
		var failed := {
			"fixture_id": fixture_id,
			"success": false,
			"error": "session_not_initialized",
			"steps_executed": action_count,
			"world_log": get_world_log_entries(),
			"store_summary": get_store_summary(),
		}
		failed.merge(extra, true)
		return failed

	var final_snapshot: Variant = get_snapshot()
	var final_candidates: Array = affordance_system.generate_candidates(final_snapshot, rules)
	var result := {
		"fixture_id": fixture_id,
		"success": true,
		"steps_executed": action_count,
		"journeys_completed": travel_count,
		"world_ticks_executed": world_tick_count,
		"time": get_time_summary(),
		"candidate_selection_source": "ActionAffordanceSystem",
		"candidate_context_source": "SimSnapshot",
		"resolver_context_source": "SimSnapshot",
		"candidate_generation_count": candidate_generation_count,
		"world_log": get_world_log_entries(),
		"world_log_summary": get_world_log_summary(),
		"snapshot_summary": _snapshot_summary(final_snapshot, final_candidates),
		"store_summary": get_store_summary(),
		"store_snapshots": get_store_snapshots(),
	}
	result.merge(extra, true)
	return result


func _reset_runtime() -> void:
	registry = SimRegistryModel.new()
	context = null
	rules = []
	stores = {}
	world_log = SimWorldLogModel.new()
	snapshot_builder = SimSnapshotBuilderModel.new()
	affordance_system = ActionAffordanceModel.new()
	resolver = TransactionResolverModel.new()
	writer = TransactionWorldWriterModel.new()
	travel_resolver = TravelResolverModel.new()
	world_tick_adapter = WorldTickAdapterModel.new()
	travel_routes = []
	fixture_id = ""
	initialized = false
	action_count = 0
	travel_count = 0
	candidate_generation_count = 0
	world_tick_count = 0
	current_day = 1
	current_hour = 8
	elapsed_hours_since_start = 0


func _create_stores(fixture: Dictionary) -> void:
	var state_store = StateStoreModel.new()
	state_store.load_from_context(context)
	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	var deferred_store = DeferredConsequenceStoreModel.new()
	stores = {
		"fact_store": FactStoreModel.new(),
		"state_store": state_store,
		"relationship_store": relationship_store,
		"memory_store": MemoryStoreModel.new(),
		"trace_store": TraceStoreModel.new(),
		"rumor_store": RumorStoreModel.new(),
		"pressure_store": PressureStoreModel.new(),
		"obligation_store": ObligationStoreModel.new(),
		"exchange_store": ExchangeStoreModel.new(),
		"deferred_consequence_store": deferred_store,
	}
	for consequence: Dictionary in fixture.get(
		"initial_deferred_consequences",
		[]
	):
		deferred_store.add_deferred_consequence(consequence)


func _execute_candidate(
		snapshot: Variant,
		candidate: Variant,
		candidate_count: int,
		metadata: Dictionary
) -> Dictionary:
	var transaction_result: Variant = resolver.resolve_action(candidate, snapshot)
	writer.apply_result(transaction_result, stores)
	_sync_context_after_result(transaction_result)

	var step_index := int(metadata.get("step_index", action_count))
	var step_id := str(metadata.get("step_id", "live_action_%d" % action_count))
	var log_entry := _build_world_log_entry(
		step_index,
		step_id,
		candidate,
		transaction_result,
		candidate_count
	)
	world_log.append_entry(log_entry)
	action_count += 1

	var contract_status := str(transaction_result.contract_status)
	return {
		"success": contract_status != "invalid_contract",
		"error": str(transaction_result.error_reason),
		"fixture_id": fixture_id,
		"step_index": step_index,
		"step_id": step_id,
		"action_id": str(candidate.action_id),
		"rule_id": str(candidate.rule_id),
		"target_id": str(candidate.target_id),
		"contract_status": contract_status,
		"candidate": candidate.to_dict(),
		"transaction_result": transaction_result.to_dict(),
		"world_log_entry": log_entry.duplicate(true),
		"store_summary": get_store_summary(),
	}


func _sync_context_after_result(result: Variant) -> void:
	var state_store: Variant = stores.get("state_store")
	for change: Dictionary in result.state_changes:
		var entity_id := str(change.get("entity_id", ""))
		var state_key := str(change.get("key", ""))
		if entity_id == "" or state_key == "":
			continue

		var value: Variant = state_store.get_state(entity_id, state_key, null)
		_set_context_state(entity_id, state_key, value)

	for fact: Dictionary in result.facts_added:
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "" and fact_id not in context.known_fact_ids:
			context.known_fact_ids.append(fact_id)
			context.known_facts.append(fact.duplicate(true))


func _sync_context_after_tick_result(result: Dictionary) -> void:
	for result_data: Dictionary in result.get("results", []):
		_sync_context_after_result_data(result_data)
	for result_data: Dictionary in result.get("due_results", []):
		_sync_context_after_result_data(result_data)


func _sync_context_after_result_data(result_data: Dictionary) -> void:
	var state_store: Variant = stores.get("state_store")
	for change: Dictionary in result_data.get("state_changes", []):
		var entity_id := str(change.get("entity_id", ""))
		var state_key := str(change.get("key", ""))
		if entity_id == "" or state_key == "":
			continue
		var value: Variant = state_store.get_state(entity_id, state_key, null)
		_set_context_state(entity_id, state_key, value)

	for fact: Dictionary in result_data.get("facts_added", []):
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "" and fact_id not in context.known_fact_ids:
			context.known_fact_ids.append(fact_id)
			context.known_facts.append(fact.duplicate(true))


func _configure_world_time(fixture: Dictionary) -> void:
	var time_data: Dictionary = fixture.get("world_time", {})
	current_day = maxi(int(time_data.get("day", 1)), 1)
	current_hour = posmod(int(time_data.get("hour", 8)), 24)


func _projected_time(hours: int) -> Dictionary:
	var absolute_hour := current_hour + maxi(hours, 0)
	return {
		"day": current_day + int(absolute_hour / 24),
		"hour": posmod(absolute_hour, 24),
	}


func _advance_clock(hours: int) -> void:
	var projected := _projected_time(hours)
	current_day = int(projected.get("day", current_day))
	current_hour = int(projected.get("hour", current_hour))
	elapsed_hours_since_start += maxi(hours, 0)


func _set_context_state(entity_id: String, state_key: String, value: Variant) -> void:
	var player_id := str(context.get_player_value("id", "player"))
	if entity_id == player_id:
		context.player[state_key] = value
		return

	for index: int in range(context.entities.size()):
		var entity: Dictionary = context.entities[index]
		if str(entity.get("id", "")) != entity_id:
			continue
		var states: Dictionary = entity.get("states", {})
		states[state_key] = value
		entity["states"] = states
		context.entities[index] = entity
		return


func _find_candidate_by_action_id(candidates: Array, action_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.action_id) == action_id:
			return candidate
	return null


func _find_travel_route(route_id: String, from_location_id: String) -> Dictionary:
	for route: Dictionary in travel_routes:
		if str(route.get("route_id", "")) != route_id:
			continue
		if str(route.get("from_location_id", "")) != from_location_id:
			continue
		return route.duplicate(true)
	return {}


func _find_candidate(candidates: Array, rule_id: String, target_id: String) -> Variant:
	for candidate: Variant in candidates:
		if str(candidate.rule_id) != rule_id:
			continue
		if target_id != "" and str(candidate.target_id) != target_id:
			continue
		return candidate
	return null


func _candidate_not_found(
		action_id: String,
		rule_id: String,
		target_id: String,
		candidates: Array
) -> Dictionary:
	return {
		"success": false,
		"error": "candidate_not_found",
		"fixture_id": fixture_id,
		"action_id": action_id,
		"rule_id": rule_id,
		"target_id": target_id,
		"candidate_count": candidates.size(),
		"available_action_ids": _candidate_action_ids(candidates),
		"store_summary": get_store_summary(),
	}


func _execution_failure(error: String, action_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"action_id": action_id,
		"store_summary": get_store_summary(),
	}


func _travel_failure(error: String, route_id: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"route_id": route_id,
		"travel_count": travel_count,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _travel_blocked_reason(
		destination: Dictionary,
		hours: int,
		food_count: int,
		food_cost: int
) -> String:
	if destination.is_empty():
		return "destination_not_found"
	if hours <= 0:
		return "invalid_route_contract"
	if food_cost < 0:
		return "invalid_route_contract"
	if food_count < food_cost:
		return "insufficient_food"
	return ""


func _tick_failure(error: String) -> Dictionary:
	return {
		"success": false,
		"error_reason": error,
		"fixture_id": fixture_id,
		"time": get_time_summary(),
		"world_tick_count": world_tick_count,
		"store_summary": get_store_summary(),
	}


func _start_failure(error: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"fixture_id": fixture_id,
		"rule_count": rules.size(),
		"candidate_count": 0,
	}


func _build_world_log_entry(
		step_index: int,
		step_id: String,
		candidate: Variant,
		result: Variant,
		candidate_count: int
) -> Dictionary:
	return {
		"entry_type": "player_action",
		"step_index": step_index,
		"step_id": step_id,
		"rule_id": str(candidate.rule_id),
		"action_id": str(candidate.action_id),
		"target_id": str(candidate.target_id),
		"target_display_name": str(candidate.target_display_name),
		"selected_from_candidates": true,
		"candidate_context_source": "SimSnapshot",
		"resolver_context_source": "SimSnapshot",
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"candidate_count": candidate_count,
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_changes": result.relationship_changes.duplicate(true),
		"relationship_change_count": result.relationship_changes.size(),
		"memories_added": result.memories_added.duplicate(true),
		"memory_types": _memory_types(result.memories_added),
		"memory_count": result.memories_added.size(),
		"traces_added": result.traces_added.duplicate(true),
		"trace_types": _trace_types(result.traces_added),
		"trace_count": result.traces_added.size(),
		"rumors_added": result.rumors_added.duplicate(true),
		"rumor_seed_ids": _rumor_seed_ids(result.rumors_added),
		"rumor_seed_count": result.rumors_added.size(),
		"pressure_changes": result.pressure_changes.duplicate(true),
		"pressure_change_count": result.pressure_changes.size(),
		"obligations_added": result.obligations_added.duplicate(true),
		"obligation_count": result.obligations_added.size(),
		"exchanges_added": result.exchanges_added.duplicate(true),
		"exchange_count": result.exchanges_added.size(),
		"deferred_consequences_added": result.deferred_consequences_added.duplicate(true),
		"deferred_consequence_count": result.deferred_consequences_added.size(),
		"obligation_updates": result.obligation_updates.duplicate(true),
		"obligation_update_count": result.obligation_updates.size(),
		"exchange_updates": result.exchange_updates.duplicate(true),
		"exchange_update_count": result.exchange_updates.size(),
		"deferred_consequence_updates": result.deferred_consequence_updates.duplicate(true),
		"deferred_consequence_update_count": result.deferred_consequence_updates.size(),
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _build_travel_log_entry(
		route: Dictionary,
		result: Variant,
		journey_index: int
) -> Dictionary:
	return {
		"entry_type": "travel",
		"step_index": journey_index,
		"step_id": "travel_%d" % journey_index,
		"route_id": str(route.get("route_id", "")),
		"from_location_id": str(route.get("from_location_id", "")),
		"to_location_id": str(route.get("to_location_id", "")),
		"hours": int(route.get("hours", 0)),
		"food_cost": int(route.get("food_cost", 0)),
		"transaction_mode": str(result.transaction_mode),
		"contract_status": str(result.contract_status),
		"skip_reason": str(result.skip_reason),
		"error_reason": str(result.error_reason),
		"facts_added": _fact_types(result.facts_added),
		"fact_ids": _fact_ids(result.facts_added),
		"state_changes": result.state_changes.duplicate(true),
		"state_change_count": result.state_changes.size(),
		"relationship_change_count": 0,
		"memory_count": 0,
		"trace_count": 0,
		"rumor_seed_count": 0,
		"pressure_change_count": 0,
		"obligation_count": 0,
		"exchange_count": 0,
		"deferred_consequence_count": 0,
		"obligation_update_count": 0,
		"exchange_update_count": 0,
		"deferred_consequence_update_count": 0,
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _snapshot_summary(snapshot: Variant, candidates: Array) -> Dictionary:
	return {
		"final_fact_count": snapshot.get_facts().size(),
		"final_trace_count": snapshot.get_visible_traces().size(),
		"final_rumor_count": snapshot.get_rumor_seeds().size(),
		"final_relationship_count": _count_snapshot_relationship_axes(snapshot),
		"final_memory_count": snapshot.memories.size(),
		"final_pressure_count": snapshot.get_pressures().size(),
		"final_obligation_count": snapshot.obligations.size(),
		"final_exchange_count": snapshot.exchanges.size(),
		"final_deferred_consequence_count": snapshot.deferred_consequences.size(),
		"final_candidate_probe": {
			"rule_ids": _candidate_rule_ids(candidates),
			"action_ids": _candidate_action_ids(candidates),
		},
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


func _memory_types(memories: Array) -> Array:
	var rows: Array = []
	for memory: Dictionary in memories:
		rows.append(str(memory.get("memory_type", "")))
	return rows


func _trace_types(traces: Array) -> Array:
	var rows: Array = []
	for trace: Dictionary in traces:
		rows.append(str(trace.get("trace_type", "")))
	return rows


func _rumor_seed_ids(rumors: Array) -> Array:
	var rows: Array = []
	for rumor: Dictionary in rumors:
		rows.append(str(rumor.get("rumor_id", "")))
	return rows


func _narrative_summary(narrative_result: Dictionary) -> String:
	if narrative_result.has("summary"):
		return str(narrative_result.get("summary", ""))
	return str(narrative_result.get("body", ""))


func _candidate_rule_ids(candidates: Array) -> Array:
	var rows: Array = []
	for candidate: Variant in candidates:
		rows.append(str(candidate.rule_id))
	return rows


func _candidate_action_ids(candidates: Array) -> Array:
	var rows: Array = []
	for candidate: Variant in candidates:
		rows.append(str(candidate.action_id))
	return rows


func _count_states(state_store: Variant) -> int:
	var count := 0
	for entity_id: String in state_store.states.keys():
		var entity_states: Dictionary = state_store.states[entity_id]
		count += entity_states.size()
	return count


func _count_relationship_axes(relationship_store: Variant) -> int:
	var count := 0
	for source_id: String in relationship_store.relations.keys():
		var source_relations: Dictionary = relationship_store.relations[source_id]
		for target_id: String in source_relations.keys():
			var target_relations: Dictionary = source_relations[target_id]
			count += target_relations.size()
	return count


func _count_snapshot_relationship_axes(snapshot: Variant) -> int:
	var count := 0
	for source_id: String in snapshot.relationships.keys():
		var source_relations: Dictionary = snapshot.relationships[source_id]
		for target_id: String in source_relations.keys():
			var target_relations: Dictionary = source_relations[target_id]
			count += target_relations.size()
	return count


func _empty_store_summary() -> Dictionary:
	return {
		"facts": 0,
		"states": 0,
		"relationships": 0,
		"memories": 0,
		"traces": 0,
		"rumors": 0,
		"pressures": 0,
		"obligations": 0,
		"exchanges": 0,
		"deferred_consequences": 0,
	}
