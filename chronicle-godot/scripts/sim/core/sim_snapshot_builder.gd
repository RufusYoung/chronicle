extends RefCounted
class_name V5SimSnapshotBuilder

const SimSnapshotModel = preload("res://scripts/sim/core/sim_snapshot.gd")
const CharacterProgressProjectorModel = preload(
	"res://scripts/sim/character_feature/character_progress_projector.gd"
)


func build_snapshot(
		context: Variant,
		stores: Dictionary,
		include_all_entities: bool = false,
		world_time: Dictionary = {}
) -> Variant:
	var entity_store: Variant = stores.get("entity_store")
	var state_store: Variant = stores.get("state_store")
	var relationship_store: Variant = stores.get("relationship_store")
	var memory_store: Variant = stores.get("memory_store")
	var trace_store: Variant = stores.get("trace_store")
	var rumor_store: Variant = stores.get("rumor_store")
	var fact_store: Variant = stores.get("fact_store")
	var pressure_store: Variant = stores.get("pressure_store")
	var obligation_store: Variant = stores.get("obligation_store")
	var exchange_store: Variant = stores.get("exchange_store")
	var deferred_consequence_store: Variant = stores.get(
		"deferred_consequence_store"
	)
	var item_store: Variant = stores.get("item_store")
	var resource_stock_store: Variant = stores.get("resource_stock_store")
	var equipment_store: Variant = stores.get("equipment_store")
	var chronicle_store: Variant = stores.get("chronicle_store")
	var investigation_store: Variant = stores.get("investigation_store")
	var character_feature_store: Variant = stores.get("character_feature_store")

	var states := _states_from_context(context)
	if state_store != null:
		states = state_store.states.duplicate(true)

	var player_id := _player_id(context)
	var source_entities := _entities_from_context(context, player_id)
	if entity_store != null:
		source_entities = entity_store.list_entity_rows([player_id])
	var entities := _entities_with_states(source_entities, states)
	if not include_all_entities:
		entities = _entities_at_location(entities, context.location_id)

	var player := _player_from_context(context)
	if entity_store != null:
		var stored_player: Dictionary = entity_store.get_entity(player_id)
		if not stored_player.is_empty():
			player = stored_player
	if states.has(player_id):
		for key: String in (states[player_id] as Dictionary).keys():
			player[key] = (states[player_id] as Dictionary)[key]
	if character_feature_store != null:
		var legacy_projection: Dictionary = (
			character_feature_store.get_legacy_projection(player_id)
		)
		for key: String in legacy_projection.keys():
			player[key] = legacy_projection[key]
	if item_store != null:
		var player_items: Array = item_store.list_items_for_owner(player_id)
		player["inventory_item_ids"] = _item_ids(player_items)
		player["food_count"] = _item_quantity_by_definition(
			player_items,
			"item.travel_ration"
		)

	var character_progress: Dictionary = {}
	if state_store != null and character_feature_store != null:
		character_progress = CharacterProgressProjectorModel.new().build(
			player_id,
			state_store,
			character_feature_store
		)

	var region_state: Dictionary = context.region_state.duplicate(true)
	if state_store != null and str(context.region_entity_id) != "":
		region_state = state_store.list_states(str(context.region_entity_id))
	var institution: Dictionary = context.institution.duplicate(true)
	if state_store != null and str(context.institution_entity_id) != "":
		institution = state_store.list_states(str(context.institution_entity_id))

	return SimSnapshotModel.new({
		"fixture_id": str(context.fixture_id),
		"world_time": world_time.duplicate(true),
		"location": context.location.duplicate(true),
		"region_state": region_state,
		"institution": institution,
		"player": player,
		"entities": entities,
		"states": states,
		"relationships": (
			{} if relationship_store == null
			else relationship_store.relations.duplicate(true)
		),
		"memories": [] if memory_store == null else memory_store.memories.duplicate(true),
		"traces": [] if trace_store == null else trace_store.list_traces(),
		"rumors": [] if rumor_store == null else rumor_store.list_rumors(),
		"facts": [] if fact_store == null else fact_store.snapshot_facts(),
		"pressures": [] if pressure_store == null else pressure_store.list_pressures(),
		"obligations": [] if obligation_store == null else obligation_store.list_obligations(),
		"exchanges": [] if exchange_store == null else exchange_store.list_exchanges(),
		"deferred_consequences": (
			[] if deferred_consequence_store == null
			else deferred_consequence_store.list_deferred_consequences()
		),
		"items": [] if item_store == null else item_store.list_items(),
		"resource_stocks": (
			[]
			if resource_stock_store == null
			else resource_stock_store.list_stocks()
		),
		"equipment_loadouts": (
			{} if equipment_store == null
			else equipment_store.list_loadouts()
		),
		"chronicle_entries": [] if chronicle_store == null else chronicle_store.list_entries(),
		"investigation_leads": (
			[] if investigation_store == null
			else investigation_store.list_leads()
		),
		"talent_assignments": (
			[] if character_feature_store == null
			else character_feature_store.list_talent_assignments()
		),
		"trait_instances": (
			[] if character_feature_store == null
			else character_feature_store.list_trait_instances()
		),
		"mark_instances": (
			[] if character_feature_store == null
			else character_feature_store.list_mark_instances()
		),
		"skill_progress": (
			[] if character_feature_store == null
			else character_feature_store.list_skill_progress()
		),
		"character_progress": character_progress,
	})


func _states_from_context(context: Variant) -> Dictionary:
	var states: Dictionary = {}
	for entity: Dictionary in context.entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id == "":
			continue
		states[entity_id] = (entity.get("states", {}) as Dictionary).duplicate(true)

	var player_id := _player_id(context)
	var player_states: Dictionary = context.player.duplicate(true)
	for static_key: String in [
		"id", "type", "role", "display_name", "description", "tags", "interactions"
	]:
		player_states.erase(static_key)
	states[player_id] = player_states
	return states


func _item_ids(rows: Array) -> Array:
	var ids: Array = []
	for item: Dictionary in rows:
		ids.append(str(item.get("item_instance_id", "")))
	return ids


func _item_quantity_by_definition(rows: Array, item_def_id: String) -> int:
	var quantity := 0
	for item: Dictionary in rows:
		if str(item.get("item_def_id", "")) == item_def_id:
			quantity += int(item.get("quantity", 0))
	return quantity


func _entities_from_context(context: Variant, player_id: String) -> Array:
	var rows: Array = []
	for entity: Dictionary in context.entities:
		if str(entity.get("id", "")) == player_id:
			continue
		rows.append(entity.duplicate(true))
	return rows


func _player_from_context(context: Variant) -> Dictionary:
	var player: Dictionary = context.player.duplicate(true)
	var static_player: Dictionary = {}
	for key: String in [
		"id", "type", "role", "display_name", "description", "tags", "interactions"
	]:
		if player.has(key):
			static_player[key] = player[key]
	if not static_player.has("id"):
		static_player["id"] = _player_id(context)
	if not static_player.has("type"):
		static_player["type"] = "person"
	return static_player


func _player_id(context: Variant) -> String:
	var player_id := str(context.actor_id)
	if player_id == "":
		player_id = str(context.player.get("id", "player"))
	return player_id


func _entities_with_states(source_entities: Array, states: Dictionary) -> Array:
	var rows: Array = []
	for entity: Dictionary in source_entities:
		var entity_copy := entity.duplicate(true)
		var entity_id := str(entity_copy.get("id", ""))
		if states.has(entity_id):
			var entity_states := (states[entity_id] as Dictionary).duplicate(true)
			entity_copy["states"] = entity_states
			if entity_states.has("location_id"):
				entity_copy["location_id"] = str(
					entity_states.get("location_id", "")
				)
		rows.append(entity_copy)
	return rows


func _entities_at_location(entities: Array, location_id: String) -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		if str(entity.get("location_id", "")) == location_id:
			rows.append(entity.duplicate(true))
	return rows
