extends RefCounted
class_name V5SimSnapshot

var fixture_id: String = ""
var location: Dictionary = {}
var region_state: Dictionary = {}
var institution: Dictionary = {}
var player: Dictionary = {}
var entities: Array = []
var states: Dictionary = {}
var relationships: Dictionary = {}
var memories: Array = []
var traces: Array = []
var rumors: Array = []
var facts: Array = []
var pressures: Array = []
var obligations: Array = []
var exchanges: Array = []
var deferred_consequences: Array = []
var items: Array = []
var chronicle_entries: Array = []


func _init(data: Dictionary = {}) -> void:
	fixture_id = str(data.get("fixture_id", ""))
	location = (data.get("location", {}) as Dictionary).duplicate(true)
	region_state = (data.get("region_state", {}) as Dictionary).duplicate(true)
	institution = (data.get("institution", {}) as Dictionary).duplicate(true)
	player = (data.get("player", {}) as Dictionary).duplicate(true)
	entities = (data.get("entities", []) as Array).duplicate(true)
	states = (data.get("states", {}) as Dictionary).duplicate(true)
	relationships = (data.get("relationships", {}) as Dictionary).duplicate(true)
	memories = (data.get("memories", []) as Array).duplicate(true)
	traces = (data.get("traces", []) as Array).duplicate(true)
	rumors = (data.get("rumors", []) as Array).duplicate(true)
	facts = (data.get("facts", []) as Array).duplicate(true)
	pressures = (data.get("pressures", []) as Array).duplicate(true)
	obligations = (data.get("obligations", []) as Array).duplicate(true)
	exchanges = (data.get("exchanges", []) as Array).duplicate(true)
	deferred_consequences = (data.get("deferred_consequences", []) as Array).duplicate(true)
	items = (data.get("items", []) as Array).duplicate(true)
	chronicle_entries = (data.get("chronicle_entries", []) as Array).duplicate(true)


func get_entity(entity_id: String) -> Dictionary:
	for entity: Dictionary in entities:
		if str(entity.get("id", "")) == entity_id:
			return entity.duplicate(true)
	return {}


func get_entities() -> Array:
	return entities.duplicate(true)


func get_visible_entities() -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		if bool(get_entity_state(str(entity.get("id", "")), "visible", false)):
			rows.append(entity.duplicate(true))
	return rows


func get_entities_by_type(type_name: String) -> Array:
	var rows: Array = []
	for entity: Dictionary in entities:
		if str(entity.get("type", "")) == type_name:
			rows.append(entity.duplicate(true))
	return rows


func get_entity_state(entity_id: String, key: String, default_value: Variant = null) -> Variant:
	if states.has(entity_id):
		var entity_states: Dictionary = states[entity_id]
		if entity_states.has(key):
			return entity_states.get(key)

	var entity := get_entity(entity_id)
	var entity_states: Dictionary = entity.get("states", {})
	return entity_states.get(key, default_value)


func get_relation(
	source_id: String,
	target_id: String,
	axis: String,
	default_value: Variant = 0
) -> Variant:
	if not relationships.has(source_id):
		return default_value

	var source_relations: Dictionary = relationships[source_id]
	if not source_relations.has(target_id):
		return default_value

	var target_relations: Dictionary = source_relations[target_id]
	return target_relations.get(axis, default_value)


func get_memories(owner_id: String) -> Array:
	var rows: Array = []
	for memory: Dictionary in memories:
		if str(memory.get("owner_id", "")) == owner_id:
			rows.append(memory.duplicate(true))
	return rows


func get_visible_traces() -> Array:
	var rows: Array = []
	var current_location_id := str(location.get("id", ""))
	for trace: Dictionary in traces:
		var trace_location_id := str(trace.get("location_id", ""))
		if (
			bool(trace.get("visible", true))
			and (trace_location_id == "" or trace_location_id == current_location_id)
		):
			rows.append(trace.duplicate(true))
	return rows


func get_rumor_seeds() -> Array:
	return rumors.duplicate(true)


func get_facts() -> Array:
	return facts.duplicate(true)


func get_pressures() -> Array:
	return pressures.duplicate(true)


func get_open_obligations() -> Array:
	var rows: Array = []
	for obligation: Dictionary in obligations:
		if str(obligation.get("status", "open")) == "open":
			rows.append(obligation.duplicate(true))
	return rows


func get_open_exchanges() -> Array:
	var rows: Array = []
	for exchange: Dictionary in exchanges:
		if str(exchange.get("status", "open")) == "open":
			rows.append(exchange.duplicate(true))
	return rows


func get_pending_deferred_consequences() -> Array:
	var rows: Array = []
	for consequence: Dictionary in deferred_consequences:
		if str(consequence.get("status", "pending")) == "pending":
			rows.append(consequence.duplicate(true))
	return rows


func get_items() -> Array:
	return items.duplicate(true)


func get_item(item_id: String) -> Dictionary:
	for item: Dictionary in items:
		if str(item.get("item_id", item.get("id", ""))) == item_id:
			return item.duplicate(true)
	return {}


func get_player_items() -> Array:
	var owner_id := str(get_player_value("id", "player"))
	var rows: Array = []
	for item: Dictionary in items:
		if str(item.get("owner_id", "")) == owner_id:
			rows.append(item.duplicate(true))
	return rows


func get_chronicle_entries() -> Array:
	return chronicle_entries.duplicate(true)


func get_player_chronicle_entries() -> Array:
	var subject_id := str(get_player_value("id", "player"))
	var rows: Array = []
	for entry: Dictionary in chronicle_entries:
		if str(entry.get("subject_id", "")) == subject_id:
			rows.append(entry.duplicate(true))
	return rows


func get_location_tags() -> Array:
	return (location.get("tags", []) as Array).duplicate(true)


func get_region_state_value(key: String, default_value: Variant = null) -> Variant:
	return region_state.get(key, default_value)


func get_institution_value(key: String, default_value: Variant = null) -> Variant:
	return institution.get(key, default_value)


func get_player_value(key: String, default_value: Variant = null) -> Variant:
	return player.get(key, default_value)


func to_dict() -> Dictionary:
	return {
		"fixture_id": fixture_id,
		"location": location.duplicate(true),
		"region_state": region_state.duplicate(true),
		"institution": institution.duplicate(true),
		"player": player.duplicate(true),
		"entities": entities.duplicate(true),
		"states": states.duplicate(true),
		"relationships": relationships.duplicate(true),
		"memories": memories.duplicate(true),
		"traces": traces.duplicate(true),
		"rumors": rumors.duplicate(true),
		"facts": facts.duplicate(true),
		"pressures": pressures.duplicate(true),
		"obligations": obligations.duplicate(true),
		"exchanges": exchanges.duplicate(true),
		"deferred_consequences": deferred_consequences.duplicate(true),
		"items": items.duplicate(true),
		"chronicle_entries": chronicle_entries.duplicate(true),
	}
