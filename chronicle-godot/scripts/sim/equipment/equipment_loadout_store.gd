extends RefCounted
class_name V5EquipmentLoadoutStore

const OPERATION_SET := "equipment_set"
const OPERATION_CLEAR := "equipment_clear"

var loadouts: Dictionary = {}
var slot_defs: Dictionary = {}
var entity_store: Variant = null
var item_store: Variant = null
var fact_store: Variant = null
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var last_error: String = ""


func configure(
		definitions: Dictionary,
		source_entity_store: Variant,
		source_item_store: Variant,
		source_fact_store: Variant
) -> void:
	slot_defs = definitions.duplicate(true)
	entity_store = source_entity_store
	item_store = source_item_store
	fact_store = source_fact_store
	clear()


func load_initial_loadouts(source: Variant) -> Dictionary:
	clear()
	var rows: Array = []
	if source is Array:
		rows = (source as Array).duplicate(true)
	elif source is Dictionary:
		for entity_id: String in (source as Dictionary).keys():
			var value: Variant = (source as Dictionary)[entity_id]
			if value is Dictionary:
				var row := (value as Dictionary).duplicate(true)
				row["entity_id"] = entity_id
				rows.append(row)
	else:
		_reject("initial_loadouts_not_collection")
		return get_contract_report()
	for row_value: Variant in rows:
		if not row_value is Dictionary:
			_reject("initial_loadout_not_dictionary")
			continue
		_load_initial_loadout(row_value)
	return get_contract_report()


func apply_equipment_change(change: Dictionary) -> bool:
	last_error = ""
	match str(change.get("operation", "")):
		OPERATION_SET:
			return _set_slot(change)
		OPERATION_CLEAR:
			return _clear_slot(change)
	return _reject("unknown_equipment_operation:%s" % change.get("operation", ""))


func get_loadout(entity_id: String) -> Dictionary:
	if not loadouts.has(entity_id):
		return _empty_loadout(entity_id)
	return (loadouts[entity_id] as Dictionary).duplicate(true)


func ensure_loadout(entity_id: String) -> bool:
	if loadouts.has(entity_id):
		return true
	if entity_id == "" or entity_store == null or not entity_store.has_entity(entity_id):
		return _reject("%s:invalid_loadout_entity" % entity_id)
	loadouts[entity_id] = _empty_loadout(entity_id)
	return true


func list_loadouts() -> Dictionary:
	return loadouts.duplicate(true)


func get_equipped_item_id(entity_id: String, slot_id: String) -> String:
	var loadout := get_loadout(entity_id)
	return _slot_item_id((loadout.get("slots", {}) as Dictionary).get(
		_normalize_slot_id(slot_id),
		null
	))


func get_item_equipment_refs(item_instance_id: String) -> Array:
	var rows: Array = []
	for entity_id: String in loadouts.keys():
		var slots: Dictionary = (loadouts[entity_id] as Dictionary).get("slots", {})
		for slot_id: String in slots.keys():
			if _slot_item_id(slots.get(slot_id)) == item_instance_id:
				rows.append({"entity_id": entity_id, "slot_id": slot_id})
	return rows


func validate_integrity() -> Dictionary:
	var errors: Array[String] = []
	for entity_id: String in loadouts.keys():
		var seen_items: Dictionary = {}
		var seen_groups: Dictionary = {}
		var slots: Dictionary = (loadouts[entity_id] as Dictionary).get("slots", {})
		for slot_id: String in slots.keys():
			var item_instance_id := _slot_item_id(slots.get(slot_id))
			if item_instance_id == "":
				continue
			var error := _equipment_reference_error(
				entity_id,
				slot_id,
				item_instance_id,
				seen_items,
				seen_groups
			)
			if error != "":
				errors.append(error)
	return {"ok": errors.is_empty(), "errors": errors}


func get_contract_report() -> Dictionary:
	var integrity := validate_integrity()
	var errors: Array = validation_errors.duplicate()
	errors.append_array((integrity.get("errors", []) as Array).duplicate())
	return {
		"ok": errors.is_empty(),
		"loadout_count": loadouts.size(),
		"registered_slot_definition_count": slot_defs.size(),
		"errors": errors,
		"warnings": validation_warnings.duplicate(),
	}


func fork_for_preflight(
		preview_item_store: Variant,
		preview_fact_store: Variant
) -> Variant:
	var clone = get_script().new()
	clone.slot_defs = slot_defs.duplicate(true)
	clone.entity_store = entity_store
	clone.item_store = preview_item_store
	clone.fact_store = preview_fact_store
	clone.loadouts = loadouts.duplicate(true)
	return clone


func clear() -> void:
	loadouts.clear()
	validation_errors.clear()
	validation_warnings.clear()
	last_error = ""


func _load_initial_loadout(value: Dictionary) -> bool:
	var entity_id := str(value.get("entity_id", ""))
	if entity_id == "" or entity_store == null or not entity_store.has_entity(entity_id):
		return _reject("%s:invalid_loadout_entity" % entity_id)
	if loadouts.has(entity_id):
		return _reject("%s:duplicate_loadout" % entity_id)
	var source_slots: Variant = value.get("slots", {})
	if not source_slots is Dictionary:
		return _reject("%s:slots_not_dictionary" % entity_id)
	var loadout := _empty_loadout(entity_id)
	var slots: Dictionary = loadout["slots"]
	for slot_key: Variant in (source_slots as Dictionary).keys():
		var slot_id := _normalize_slot_id(str(slot_key))
		if not slot_defs.has(slot_id):
			return _reject("%s:unknown_slot:%s" % [entity_id, slot_id])
		var item_instance_id := _slot_item_id(
			(source_slots as Dictionary).get(slot_key)
		)
		slots[slot_id] = null if item_instance_id == "" else item_instance_id
	loadout["slots"] = slots
	loadout["updated_tick"] = int(value.get("updated_tick", 0))
	loadouts[entity_id] = loadout
	var integrity := validate_integrity()
	if not bool(integrity.get("ok", false)):
		loadouts.erase(entity_id)
		return _reject(str((integrity.get("errors", []) as Array)[0]))
	return true


func _set_slot(change: Dictionary) -> bool:
	var identity := _change_identity(change)
	var entity_id := str(identity.get("entity_id", ""))
	var slot_id := str(identity.get("slot_id", ""))
	var item_instance_id := str(change.get("item_instance_id", ""))
	var source_fact_ids := _source_fact_ids(change, entity_id)
	if source_fact_ids.is_empty():
		return false
	if not _base_identity_is_valid(entity_id, slot_id):
		return false
	if item_instance_id == "":
		return _reject("%s:%s:missing_item_instance_id" % [entity_id, slot_id])
	var loadout := get_loadout(entity_id)
	var slots: Dictionary = (loadout.get("slots", {}) as Dictionary).duplicate(true)
	var previous_item_id := _slot_item_id(slots.get(slot_id))
	if previous_item_id == item_instance_id:
		return _reject("%s:%s:equipment_unchanged" % [entity_id, slot_id])
	slots[slot_id] = item_instance_id
	loadout["slots"] = slots
	loadout["updated_tick"] = _source_tick(source_fact_ids, change)
	var previous: Variant = loadouts.get(entity_id)
	loadouts[entity_id] = loadout
	var integrity := validate_integrity()
	if not bool(integrity.get("ok", false)):
		_restore_loadout(entity_id, previous)
		return _reject(str((integrity.get("errors", []) as Array)[0]))
	if previous_item_id != "" and not _append_item_history(
		previous_item_id,
		"unequipped",
		entity_id,
		slot_id,
		source_fact_ids,
		change
	):
		_restore_loadout(entity_id, previous)
		return false
	if not _append_item_history(
		item_instance_id,
		"equipped",
		entity_id,
		slot_id,
		source_fact_ids,
		change
	):
		_restore_loadout(entity_id, previous)
		return false
	return true


func _clear_slot(change: Dictionary) -> bool:
	var identity := _change_identity(change)
	var entity_id := str(identity.get("entity_id", ""))
	var slot_id := str(identity.get("slot_id", ""))
	var source_fact_ids := _source_fact_ids(change, entity_id)
	if source_fact_ids.is_empty():
		return false
	if not _base_identity_is_valid(entity_id, slot_id):
		return false
	var loadout := get_loadout(entity_id)
	var slots: Dictionary = (loadout.get("slots", {}) as Dictionary).duplicate(true)
	var previous_item_id := _slot_item_id(slots.get(slot_id))
	if previous_item_id == "":
		return _reject("%s:%s:slot_already_clear" % [entity_id, slot_id])
	var previous: Variant = loadouts.get(entity_id)
	slots[slot_id] = null
	loadout["slots"] = slots
	loadout["updated_tick"] = _source_tick(source_fact_ids, change)
	loadouts[entity_id] = loadout
	if not _append_item_history(
		previous_item_id,
		"unequipped",
		entity_id,
		slot_id,
		source_fact_ids,
		change
	):
		_restore_loadout(entity_id, previous)
		return false
	return true


func _equipment_reference_error(
		entity_id: String,
		slot_id: String,
		item_instance_id: String,
		seen_items: Dictionary,
		seen_groups: Dictionary
) -> String:
	if not slot_defs.has(slot_id):
		return "%s:unknown_slot:%s" % [entity_id, slot_id]
	if seen_items.has(item_instance_id):
		return "%s:item_in_multiple_slots:%s" % [entity_id, item_instance_id]
	var slot_def: Dictionary = slot_defs[slot_id]
	var group := str(slot_def.get("exclusive_group", ""))
	if group != "" and seen_groups.has(group):
		return "%s:exclusive_group_conflict:%s" % [entity_id, group]
	if item_store == null or not item_store.is_held_by(item_instance_id, entity_id):
		return "%s:%s:item_not_held:%s" % [entity_id, slot_id, item_instance_id]
	var item: Dictionary = item_store.get_item(item_instance_id)
	if item.is_empty():
		return "%s:%s:unknown_item:%s" % [entity_id, slot_id, item_instance_id]
	var allowed_slots: Array = item.get("equip_slots", [])
	if (
		slot_id not in allowed_slots
		and _short_slot_id(slot_id) not in allowed_slots
	):
		return "%s:%s:item_slot_not_allowed:%s" % [entity_id, slot_id, item_instance_id]
	if "equip" not in (item.get("capabilities", []) as Array):
		return "%s:%s:item_not_equippable:%s" % [entity_id, slot_id, item_instance_id]
	var accepted_tags: Array = slot_def.get("accepts_item_tags_any", [])
	if not _arrays_intersect(accepted_tags, item.get("tags", [])):
		return "%s:%s:item_tags_not_accepted:%s" % [entity_id, slot_id, item_instance_id]
	var condition: Dictionary = item.get("condition", {})
	if condition.has("durability") and int(condition.get("durability", 0)) <= 0:
		return "%s:%s:item_fully_broken:%s" % [entity_id, slot_id, item_instance_id]
	seen_items[item_instance_id] = slot_id
	if group != "":
		seen_groups[group] = slot_id
	return ""


func _base_identity_is_valid(entity_id: String, slot_id: String) -> bool:
	if entity_id == "" or entity_store == null or not entity_store.has_entity(entity_id):
		return _reject("%s:invalid_equipment_entity" % entity_id)
	if not slot_defs.has(slot_id):
		return _reject("%s:unknown_slot:%s" % [entity_id, slot_id])
	return true


func _source_fact_ids(change: Dictionary, entity_id: String) -> Array:
	var value: Variant = change.get("source_fact_ids", [])
	if not value is Array:
		_reject("%s:source_fact_ids_not_array" % entity_id)
		return []
	var ids: Array = (value as Array).duplicate(true)
	if ids.is_empty():
		_reject("%s:equipment_change_requires_source_fact" % entity_id)
		return []
	for fact_id: Variant in ids:
		if fact_store == null or fact_store.get_fact(str(fact_id)).is_empty():
			_reject("%s:unknown_source_fact:%s" % [entity_id, fact_id])
			return []
	return ids


func _append_item_history(
		item_instance_id: String,
		event_type: String,
		entity_id: String,
		slot_id: String,
		source_fact_ids: Array,
		change: Dictionary
) -> bool:
	if item_store == null:
		return _reject("%s:item_store_missing" % item_instance_id)
	var applied: bool = item_store.apply_item_change({
		"operation": "append_history",
		"item_instance_id": item_instance_id,
		"history_entry": {
			"event_type": event_type,
			"entity_id": entity_id,
			"slot_id": slot_id,
			"fact_id": str(source_fact_ids[0]),
			"transaction_id": str(change.get("transaction_id", "")),
		},
		"updated_tick": _source_tick(source_fact_ids, change),
	})
	if not applied:
		return _reject("%s:item_history_failed:%s" % [
			item_instance_id,
			str(item_store.last_error),
		])
	return true


func _empty_loadout(entity_id: String) -> Dictionary:
	var slots: Dictionary = {}
	for slot_id: String in slot_defs.keys():
		slots[slot_id] = null
	return {"entity_id": entity_id, "slots": slots, "updated_tick": 0}


func _change_identity(change: Dictionary) -> Dictionary:
	return {
		"entity_id": str(change.get("entity_id", "")),
		"slot_id": _normalize_slot_id(str(change.get("slot_id", ""))),
	}


func _normalize_slot_id(value: String) -> String:
	return value if value.begins_with("slot.") else "slot.%s" % value


func _short_slot_id(value: String) -> String:
	return value.trim_prefix("slot.")


func _slot_item_id(value: Variant) -> String:
	return "" if value == null else str(value)


func _source_tick(source_fact_ids: Array, change: Dictionary) -> int:
	if change.has("updated_tick"):
		return int(change.get("updated_tick", 0))
	var fact: Dictionary = fact_store.get_fact(str(source_fact_ids[0]))
	if fact.has("tick"):
		return int(fact.get("tick", 0))
	return int(fact.get("day", 0)) * 24 + int(fact.get("hour", 0))


func _restore_loadout(entity_id: String, previous: Variant) -> void:
	if previous is Dictionary:
		loadouts[entity_id] = (previous as Dictionary).duplicate(true)
	else:
		loadouts.erase(entity_id)


func _arrays_intersect(left: Array, right_value: Variant) -> bool:
	if not right_value is Array:
		return false
	for value: Variant in left:
		if value in (right_value as Array):
			return true
	return false


func _reject(message: String) -> bool:
	last_error = message
	validation_errors.append(message)
	return false
