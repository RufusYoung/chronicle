extends RefCounted
class_name V5SimSnapshotBuilder

const SimSnapshotModel = preload("res://scripts/sim/core/sim_snapshot.gd")


func build_snapshot(context: Variant, stores: Dictionary) -> Variant:
	var state_store: Variant = stores.get("state_store")
	var relationship_store: Variant = stores.get("relationship_store")
	var memory_store: Variant = stores.get("memory_store")
	var trace_store: Variant = stores.get("trace_store")
	var rumor_store: Variant = stores.get("rumor_store")
	var fact_store: Variant = stores.get("fact_store")

	var states := _states_from_context(context)
	if state_store != null:
		states = state_store.states.duplicate(true)

	var entities := _entities_with_states(context.entities, states)
	var player: Dictionary = context.player.duplicate(true)
	var player_id := str(context.get_player_value("id", "player"))
	if states.has(player_id):
		var player_states: Dictionary = states[player_id]
		for key: String in player_states.keys():
			player[key] = player_states[key]

	return SimSnapshotModel.new({
		"fixture_id": str(context.fixture_id),
		"location": context.location.duplicate(true),
		"region_state": context.region_state.duplicate(true),
		"institution": context.institution.duplicate(true),
		"player": player,
		"entities": entities,
		"states": states,
		"relationships": {} if relationship_store == null else relationship_store.relations.duplicate(true),
		"memories": [] if memory_store == null else memory_store.memories.duplicate(true),
		"traces": [] if trace_store == null else trace_store.list_traces(),
		"rumors": [] if rumor_store == null else rumor_store.list_rumors(),
		"facts": [] if fact_store == null else fact_store.list_facts(),
	})


func _states_from_context(context: Variant) -> Dictionary:
	var states: Dictionary = {}
	for entity: Dictionary in context.entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id == "":
			continue
		states[entity_id] = (entity.get("states", {}) as Dictionary).duplicate(true)

	var player_id := str(context.get_player_value("id", "player"))
	states[player_id] = context.player.duplicate(true)
	return states


func _entities_with_states(source_entities: Array, states: Dictionary) -> Array:
	var rows: Array = []
	for entity: Dictionary in source_entities:
		var entity_copy := entity.duplicate(true)
		var entity_id := str(entity_copy.get("id", ""))
		if states.has(entity_id):
			entity_copy["states"] = (states[entity_id] as Dictionary).duplicate(true)
		rows.append(entity_copy)
	return rows
