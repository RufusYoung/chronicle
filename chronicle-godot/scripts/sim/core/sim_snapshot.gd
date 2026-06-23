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
	for trace: Dictionary in traces:
		if bool(trace.get("visible", true)):
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
	}
