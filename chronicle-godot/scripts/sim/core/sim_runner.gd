extends RefCounted
class_name V5SimRunner

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimContextModel = preload("res://scripts/sim/core/sim_context.gd")
const SimWorldLogModel = preload("res://scripts/sim/core/sim_world_log.gd")
const SimSnapshotBuilderModel = preload("res://scripts/sim/core/sim_snapshot_builder.gd")
const ActionAffordanceModel = preload("res://scripts/sim/action/action_affordance_system.gd")
const TransactionResolverModel = preload("res://scripts/sim/transaction/transaction_resolver.gd")
const TransactionWorldWriterModel = preload("res://scripts/sim/transaction/transaction_world_writer.gd")
const FactStoreModel = preload("res://scripts/sim/fact/fact_store.gd")
const StateStoreModel = preload("res://scripts/sim/state/state_store.gd")
const RelationshipStoreModel = preload("res://scripts/sim/relationship/relationship_store.gd")
const MemoryStoreModel = preload("res://scripts/sim/memory/memory_store.gd")
const TraceStoreModel = preload("res://scripts/sim/trace/trace_store.gd")
const RumorStoreModel = preload("res://scripts/sim/rumor/rumor_store.gd")

const RELATIONSHIP_AXIS_DEFS_PATH := "res://data/sim/raw/relationship_defs/relationship_axis_defs.json"


func run_sequence(fixture_path: String, scenario_path: String, raw_rule_paths: Array) -> Dictionary:
	var registry = SimRegistryModel.new()
	registry.load_action_rules(raw_rule_paths)
	var rules: Array = registry.get_action_rules()

	var fixture := registry.load_json(fixture_path)
	var scenario := registry.load_json(scenario_path)
	if fixture.is_empty():
		return _failure_result("", "", "fixture_not_loaded", 0, {}, _empty_store_summary())
	if scenario.is_empty():
		return _failure_result(str(fixture.get("fixture_id", "")), "", "scenario_not_loaded", 0, {}, _empty_store_summary())

	var fixture_id := str(fixture.get("fixture_id", ""))
	var scenario_id := str(scenario.get("scenario_id", ""))
	var expected_fixture_id := str(scenario.get("fixture_id", ""))
	if expected_fixture_id != "" and fixture_id != expected_fixture_id:
		return _failure_result(
			fixture_id,
			scenario_id,
			"scenario_fixture_mismatch",
			0,
			{},
			_empty_store_summary()
		)

	var context = SimContextModel.new(fixture)
	var affordance_system = ActionAffordanceModel.new()
	var resolver = TransactionResolverModel.new()
	var writer = TransactionWorldWriterModel.new()
	var world_log = SimWorldLogModel.new()
	var snapshot_builder = SimSnapshotBuilderModel.new()

	var fact_store = FactStoreModel.new()
	var state_store = StateStoreModel.new()
	state_store.load_from_context(context)
	var relationship_store = RelationshipStoreModel.new()
	relationship_store.load_axis_defs(RELATIONSHIP_AXIS_DEFS_PATH)
	var memory_store = MemoryStoreModel.new()
	var trace_store = TraceStoreModel.new()
	var rumor_store = RumorStoreModel.new()
	var stores := {
		"fact_store": fact_store,
		"state_store": state_store,
		"relationship_store": relationship_store,
		"memory_store": memory_store,
		"trace_store": trace_store,
		"rumor_store": rumor_store,
	}

	var steps: Array = scenario.get("steps", [])
	var candidate_generation_count := 0
	for step_index: int in range(steps.size()):
		var step: Dictionary = steps[step_index]
		var snapshot = snapshot_builder.build_snapshot(context, stores)
		var candidates: Array = affordance_system.generate_candidates(snapshot, rules)
		candidate_generation_count += 1
		var candidate: Variant = _select_candidate(candidates, step.get("select", {}))
		if candidate == null:
			return _failure_result(
				fixture_id,
				scenario_id,
				"candidate_not_found",
				step_index,
				step,
				_store_summary(fact_store, state_store, relationship_store, memory_store, trace_store, rumor_store),
				world_log,
				candidate_generation_count,
				"SimSnapshot"
			)

		var transaction_result = resolver.resolve_action(candidate, context)
		writer.apply_result(transaction_result, stores)
		_sync_context_after_result(context, transaction_result, state_store)
		world_log.append_entry(_build_world_log_entry(
			step_index,
			step,
			candidate,
			transaction_result,
			candidates.size(),
			"SimSnapshot"
		))

	var final_snapshot = snapshot_builder.build_snapshot(context, stores)
	var final_candidates: Array = affordance_system.generate_candidates(final_snapshot, rules)

	return {
		"fixture_id": fixture_id,
		"scenario_id": scenario_id,
		"success": true,
		"steps_executed": steps.size(),
		"candidate_selection_source": "ActionAffordanceSystem",
		"candidate_context_source": "SimSnapshot",
		"candidate_generation_count": candidate_generation_count,
		"world_log": world_log.list_entries(),
		"world_log_summary": world_log.summary(),
		"snapshot_summary": _snapshot_summary(final_snapshot, final_candidates),
		"store_summary": _store_summary(
			fact_store,
			state_store,
			relationship_store,
			memory_store,
			trace_store,
			rumor_store
		),
		"store_snapshots": _store_snapshots(
			fact_store,
			state_store,
			relationship_store,
			memory_store,
			trace_store,
			rumor_store
		),
	}


func _select_candidate(candidates: Array, select: Dictionary) -> Variant:
	var rule_id := str(select.get("rule_id", ""))
	var target_id := str(select.get("target_id", ""))
	for candidate: Variant in candidates:
		if str(candidate.rule_id) != rule_id:
			continue
		if target_id != "" and str(candidate.target_id) != target_id:
			continue
		return candidate
	return null


func _build_world_log_entry(
	step_index: int,
	step: Dictionary,
	candidate: Variant,
	result: Variant,
	candidate_count: int,
	candidate_context_source: String
) -> Dictionary:
	return {
		"step_index": step_index,
		"step_id": str(step.get("step_id", "")),
		"rule_id": str(candidate.rule_id),
		"action_id": str(candidate.action_id),
		"target_id": str(candidate.target_id),
		"target_display_name": str(candidate.target_display_name),
		"selected_from_candidates": true,
		"candidate_context_source": candidate_context_source,
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
		"narrative_summary": _narrative_summary(result.narrative_result),
		"narrative_result": result.narrative_result.duplicate(true),
	}


func _sync_context_after_result(context: Variant, result: Variant, state_store: Variant) -> void:
	for change: Dictionary in result.state_changes:
		var entity_id := str(change.get("entity_id", ""))
		var state_key := str(change.get("key", ""))
		if entity_id == "" or state_key == "":
			continue

		var value: Variant = state_store.get_state(entity_id, state_key, null)
		_set_context_state(context, entity_id, state_key, value)

	for fact: Dictionary in result.facts_added:
		var fact_id := str(fact.get("fact_id", ""))
		if fact_id != "" and not (fact_id in context.known_fact_ids):
			context.known_fact_ids.append(fact_id)
			context.known_facts.append(fact.duplicate(true))


func _set_context_state(context: Variant, entity_id: String, state_key: String, value: Variant) -> void:
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


func _store_summary(
	fact_store: Variant,
	state_store: Variant,
	relationship_store: Variant,
	memory_store: Variant,
	trace_store: Variant,
	rumor_store: Variant
) -> Dictionary:
	return {
		"facts": fact_store.list_facts().size(),
		"states": _count_states(state_store),
		"relationships": _count_relationship_axes(relationship_store),
		"memories": memory_store.memories.size(),
		"traces": trace_store.list_traces().size(),
		"rumors": rumor_store.list_rumors().size(),
	}


func _snapshot_summary(snapshot: Variant, candidates: Array) -> Dictionary:
	return {
		"final_fact_count": snapshot.get_facts().size(),
		"final_trace_count": snapshot.get_visible_traces().size(),
		"final_rumor_count": snapshot.get_rumor_seeds().size(),
		"final_relationship_count": _count_snapshot_relationship_axes(snapshot),
		"final_memory_count": snapshot.memories.size(),
		"final_candidate_probe": {
			"rule_ids": _candidate_rule_ids(candidates),
			"action_ids": _candidate_action_ids(candidates),
		},
	}


func _count_snapshot_relationship_axes(snapshot: Variant) -> int:
	var count := 0
	for source_id: String in snapshot.relationships.keys():
		var source_relations: Dictionary = snapshot.relationships[source_id]
		for target_id: String in source_relations.keys():
			var target_relations: Dictionary = source_relations[target_id]
			count += target_relations.size()
	return count


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


func _store_snapshots(
	fact_store: Variant,
	state_store: Variant,
	relationship_store: Variant,
	memory_store: Variant,
	trace_store: Variant,
	rumor_store: Variant
) -> Dictionary:
	return {
		"facts": fact_store.list_facts(),
		"states": state_store.states.duplicate(true),
		"relationships": relationship_store.relations.duplicate(true),
		"memories": memory_store.memories.duplicate(true),
		"traces": trace_store.list_traces(),
		"rumors": rumor_store.list_rumors(),
	}


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


func _empty_store_summary() -> Dictionary:
	return {
		"facts": 0,
		"states": 0,
		"relationships": 0,
		"memories": 0,
		"traces": 0,
		"rumors": 0,
	}


func _failure_result(
	fixture_id: String,
	scenario_id: String,
	error: String,
	failed_step_index: int,
	failed_step: Dictionary,
	store_summary: Dictionary,
	world_log: Variant = null,
	candidate_generation_count: int = 0,
	candidate_context_source: String = ""
) -> Dictionary:
	return {
		"fixture_id": fixture_id,
		"scenario_id": scenario_id,
		"success": false,
		"error": error,
		"failed_step_index": failed_step_index,
		"failed_step": failed_step.duplicate(true),
		"steps_executed": failed_step_index,
		"candidate_selection_source": "ActionAffordanceSystem",
		"candidate_context_source": candidate_context_source,
		"candidate_generation_count": candidate_generation_count,
		"world_log": [] if world_log == null else world_log.list_entries(),
		"store_summary": store_summary.duplicate(true),
	}
