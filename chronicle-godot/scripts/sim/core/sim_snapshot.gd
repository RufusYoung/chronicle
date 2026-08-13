extends RefCounted
class_name V5SimSnapshot

var fixture_id: String = ""
var world_time: Dictionary = {}
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
var equipment_loadouts: Dictionary = {}
var chronicle_entries: Array = []
var investigation_leads: Array = []
var talent_assignments: Array = []
var trait_instances: Array = []
var mark_instances: Array = []
var skill_progress: Array = []
var character_progress: Dictionary = {}


func _init(data: Dictionary = {}) -> void:
	fixture_id = str(data.get("fixture_id", ""))
	world_time = (data.get("world_time", {}) as Dictionary).duplicate(true)
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
	equipment_loadouts = (
		data.get("equipment_loadouts", {}) as Dictionary
	).duplicate(true)
	chronicle_entries = (data.get("chronicle_entries", []) as Array).duplicate(true)
	investigation_leads = (data.get("investigation_leads", []) as Array).duplicate(true)
	talent_assignments = (data.get("talent_assignments", []) as Array).duplicate(true)
	trait_instances = (data.get("trait_instances", []) as Array).duplicate(true)
	mark_instances = (data.get("mark_instances", []) as Array).duplicate(true)
	skill_progress = (data.get("skill_progress", []) as Array).duplicate(true)
	character_progress = (
		data.get("character_progress", {}) as Dictionary
	).duplicate(true)


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


func get_visible_rumors() -> Array:
	var rows: Array = []
	var current_location_id := str(location.get("id", ""))
	for rumor: Dictionary in rumors:
		var rumor_locations := [
			str(rumor.get("location_id", "")),
			str(rumor.get("current_location", "")),
			str(rumor.get("origin_location", "")),
		]
		if (
			bool(rumor.get("visible", true))
			and current_location_id in rumor_locations
		):
			rows.append(rumor.duplicate(true))
	return rows


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
		var holder: Dictionary = item.get("holder", {})
		if (
			str(holder.get("kind", "")) == "entity"
			and str(holder.get("id", "")) == owner_id
		):
			rows.append(item.duplicate(true))
	return rows


func get_inventory_view(owner_entity_id: String) -> Dictionary:
	var item_instance_ids: Array = []
	var total_mass := 0.0
	for item: Dictionary in items:
		var holder: Dictionary = item.get("holder", {})
		if (
			str(holder.get("kind", "")) != "entity"
			or str(holder.get("id", "")) != owner_entity_id
		):
			continue
		item_instance_ids.append(str(item.get("item_instance_id", "")))
		total_mass += float(item.get("base_mass", 0.0)) * int(
			item.get("quantity", 0)
		)
	return {
		"owner_entity_id": owner_entity_id,
		"item_instance_ids": item_instance_ids,
		"total_mass": total_mass,
	}


func get_market_stock_view(seller_entity_id: String) -> Dictionary:
	var offers: Array = []
	for item: Dictionary in items:
		var holder: Dictionary = item.get("holder", {})
		if (
			str(holder.get("kind", "")) != "entity"
			or str(holder.get("id", "")) != seller_entity_id
			or "trade" not in (item.get("capabilities", []) as Array)
		):
			continue
		offers.append({
			"item_instance_id": str(item.get("item_instance_id", "")),
			"available_quantity": int(item.get("quantity", 0)),
			"unit_base_value": float(item.get("base_value", 0.0)),
			"quote_status": "unquoted",
		})
	return {"seller_entity_id": seller_entity_id, "offers": offers}


func get_equipment_loadout(entity_id: String) -> Dictionary:
	if not equipment_loadouts.has(entity_id):
		return {"entity_id": entity_id, "slots": {}, "updated_tick": 0}
	return (equipment_loadouts[entity_id] as Dictionary).duplicate(true)


func get_equipped_item(entity_id: String, slot_id: String) -> Dictionary:
	var loadout := get_equipment_loadout(entity_id)
	var normalized_slot := slot_id if slot_id.begins_with("slot.") else "slot.%s" % slot_id
	var item_value: Variant = (
		loadout.get("slots", {}) as Dictionary
	).get(normalized_slot)
	var item_instance_id := "" if item_value == null else str(item_value)
	return get_item(item_instance_id)


func get_chronicle_entries() -> Array:
	return chronicle_entries.duplicate(true)


func get_player_chronicle_entries() -> Array:
	var subject_id := str(get_player_value("id", "player"))
	var rows: Array = []
	for entry: Dictionary in chronicle_entries:
		if str(entry.get("subject_id", "")) == subject_id:
			rows.append(entry.duplicate(true))
	return rows


func get_investigation_leads() -> Array:
	return investigation_leads.duplicate(true)


func get_open_investigation_leads() -> Array:
	var rows: Array = []
	for lead: Dictionary in investigation_leads:
		if str(lead.get("status", "open")) == "open":
			rows.append(lead.duplicate(true))
	return rows


func get_investigation_lead(lead_id: String) -> Dictionary:
	for lead: Dictionary in investigation_leads:
		if str(lead.get("lead_id", "")) == lead_id:
			return lead.duplicate(true)
	return {}


func get_location_tags() -> Array:
	return (location.get("tags", []) as Array).duplicate(true)


func get_region_state_value(key: String, default_value: Variant = null) -> Variant:
	return region_state.get(key, default_value)


func get_institution_value(key: String, default_value: Variant = null) -> Variant:
	return institution.get(key, default_value)


func get_player_value(key: String, default_value: Variant = null) -> Variant:
	return player.get(key, default_value)


func get_character_progress() -> Dictionary:
	return character_progress.duplicate(true)


func get_talent_assignments(owner_id: String = "") -> Array:
	return _owned_character_features(talent_assignments, owner_id)


func get_trait_instances(owner_id: String = "") -> Array:
	return _owned_character_features(trait_instances, owner_id)


func get_mark_instances(owner_id: String = "") -> Array:
	return _owned_character_features(mark_instances, owner_id)


func get_skill_progress(owner_id: String = "") -> Array:
	return _owned_character_features(skill_progress, owner_id)


func to_dict() -> Dictionary:
	return {
		"fixture_id": fixture_id,
		"world_time": world_time.duplicate(true),
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
		"equipment_loadouts": equipment_loadouts.duplicate(true),
		"chronicle_entries": chronicle_entries.duplicate(true),
		"investigation_leads": investigation_leads.duplicate(true),
		"talent_assignments": talent_assignments.duplicate(true),
		"trait_instances": trait_instances.duplicate(true),
		"mark_instances": mark_instances.duplicate(true),
		"skill_progress": skill_progress.duplicate(true),
		"character_progress": character_progress.duplicate(true),
	}


func _owned_character_features(source: Array, owner_id: String) -> Array:
	var rows: Array = []
	for value: Dictionary in source:
		if owner_id == "" or str(value.get("owner_entity_id", "")) == owner_id:
			rows.append(value.duplicate(true))
	return rows
