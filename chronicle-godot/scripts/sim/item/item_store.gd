extends RefCounted
class_name V5ItemStore

const HOLDER_KINDS := ["entity", "location", "container", "escrow", "destroyed"]

var items: Dictionary = {}
var item_defs: Dictionary = {}
var entity_store: Variant = null
var fact_store: Variant = null
var location_ids: Dictionary = {}
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var last_error: String = ""


func configure(
		definitions: Dictionary,
		source_entity_store: Variant,
		source_locations: Variant,
		source_fact_store: Variant
) -> void:
	item_defs = definitions.duplicate(true)
	entity_store = source_entity_store
	fact_store = source_fact_store
	location_ids.clear()
	if source_locations is Dictionary:
		for location_id: Variant in source_locations.keys():
			location_ids[str(location_id)] = true
	elif source_locations is Array:
		for location: Dictionary in source_locations:
			var location_id := str(location.get("id", ""))
			if location_id != "":
				location_ids[location_id] = true
	clear()


func load_initial_items(source_items: Array) -> Dictionary:
	clear()
	for source: Dictionary in source_items:
		var item := source.duplicate(true)
		_create_item(item, [], true)
	return get_contract_report()


func apply_item_change(change: Dictionary) -> bool:
	last_error = ""
	match str(change.get("operation", "")):
		"create":
			var item: Variant = change.get("item", {})
			if not item is Dictionary:
				return _reject("create:item_not_dictionary")
			var source_fact_value: Variant = change.get("source_fact_ids", [])
			if not source_fact_value is Array:
				return _reject("create:source_fact_ids_not_array")
			return create_item(
				item,
				(source_fact_value as Array).duplicate(true)
			)
		"append_history":
			return _append_history(change)
		"transfer":
			return _transfer_item(change)
		"consume":
			return _consume_item(change)
		"adjust_durability":
			return _adjust_durability(change)
		"split_stack":
			return _split_stack(change)
	return _reject("unknown_item_operation:%s" % change.get("operation", ""))


func create_item(item: Dictionary, source_fact_ids: Array = []) -> bool:
	return _create_item(item, source_fact_ids, false)


func _create_item(
		item: Dictionary,
		source_fact_ids: Array,
		allow_initial_fixture: bool
) -> bool:
	last_error = ""
	var item_instance_id := str(
		item.get("item_instance_id", item.get("item_id", item.get("id", "")))
	)
	var item_def_id := str(item.get("item_def_id", ""))
	if item_instance_id == "" or item_def_id == "":
		return _reject("invalid_item_identity")
	if items.has(item_instance_id):
		return _reject("%s:duplicate_item_instance_id" % item_instance_id)
	if not item_defs.has(item_def_id):
		return _reject("%s:unknown_item_definition:%s" % [
			item_instance_id,
			item_def_id,
		])
	var holder := _normalized_holder(item)
	if not _holder_is_valid(holder, item_instance_id):
		return _reject("%s:invalid_holder" % item_instance_id)
	var definition: Dictionary = item_defs[item_def_id]
	var quantity_value: Variant = item.get("quantity", 1)
	if not _is_whole_number(quantity_value):
		return _reject("%s:quantity_not_integer" % item_instance_id)
	var quantity := int(quantity_value)
	if not _quantity_is_valid(quantity, holder, definition):
		return _reject("%s:invalid_quantity" % item_instance_id)
	if not _condition_is_valid(item, definition):
		return _reject("%s:invalid_condition" % item_instance_id)
	var history_value: Variant = item.get("history", [])
	if not history_value is Array:
		return _reject("%s:history_not_array" % item_instance_id)
	if not allow_initial_fixture and not (history_value as Array).is_empty():
		return _reject("%s:runtime_create_has_prefilled_history" % item_instance_id)
	if not item.get("provenance", {}) is Dictionary:
		return _reject("%s:provenance_not_dictionary" % item_instance_id)
	if not item.get("custom_tags", []) is Array or not item.get("tags", []) is Array:
		return _reject("%s:tags_not_array" % item_instance_id)
	if source_fact_ids.is_empty() and not allow_initial_fixture:
		return _reject("%s:create_requires_source_fact" % item_instance_id)
	if not _facts_exist(source_fact_ids):
		return _reject("%s:unknown_source_fact" % item_instance_id)

	var normalized := item.duplicate(true)
	normalized.erase("id")
	normalized.erase("item_id")
	normalized.erase("owner_id")
	normalized.erase("holder_id")
	normalized.erase("source_kind")
	normalized["item_instance_id"] = item_instance_id
	normalized["item_def_id"] = item_def_id
	normalized["holder"] = holder
	normalized["quantity"] = quantity
	normalized["custom_tags"] = _custom_tags(item, definition)
	normalized.erase("tags")
	normalized.erase("item_type")
	normalized["condition"] = _normalized_condition(item, definition)
	normalized["provenance"] = (
		item.get("provenance", {}) as Dictionary
	).duplicate(true)
	if not source_fact_ids.is_empty():
		var provenance: Dictionary = normalized["provenance"]
		provenance["created_by_fact_id"] = str(source_fact_ids[0])
		normalized["provenance"] = provenance
	normalized["history"] = (history_value as Array).duplicate(true)
	normalized["created_tick"] = int(item.get("created_tick", 0))
	normalized["updated_tick"] = int(
		item.get("updated_tick", normalized["created_tick"])
	)
	items[item_instance_id] = normalized
	return true


func get_item(item_instance_id: String) -> Dictionary:
	if not items.has(item_instance_id):
		return {}
	return _project_item(items[item_instance_id])


func list_items() -> Array:
	var rows: Array = []
	for item_instance_id: String in items.keys():
		rows.append(_project_item(items[item_instance_id]))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_instance_id", "")) < str(
			b.get("item_instance_id", "")
		)
	)
	return rows


func list_item_records() -> Array:
	var rows: Array = []
	for item_instance_id: String in items.keys():
		rows.append((items[item_instance_id] as Dictionary).duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_instance_id", "")) < str(
			b.get("item_instance_id", "")
		)
	)
	return rows


func list_items_for_holder(holder: Dictionary) -> Array:
	var rows: Array = []
	for item: Dictionary in items.values():
		if _holders_equal(item.get("holder", {}), holder):
			rows.append(_project_item(item))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_instance_id", "")) < str(
			b.get("item_instance_id", "")
		)
	)
	return rows


func list_items_for_owner(owner_id: String) -> Array:
	return list_items_for_holder({"kind": "entity", "id": owner_id})


func is_held_by(item_instance_id: String, owner_id: String) -> bool:
	if not items.has(item_instance_id):
		return false
	return _holders_equal(
		(items[item_instance_id] as Dictionary).get("holder", {}),
		{"kind": "entity", "id": owner_id}
	)


func get_item_definition(item_def_id: String) -> Dictionary:
	if not item_defs.has(item_def_id):
		return {}
	return (item_defs[item_def_id] as Dictionary).duplicate(true)


func fork_for_preflight(preview_fact_store: Variant) -> Variant:
	var clone = get_script().new()
	clone.items = items.duplicate(true)
	clone.item_defs = item_defs.duplicate(true)
	clone.entity_store = entity_store
	clone.fact_store = preview_fact_store
	clone.location_ids = location_ids.duplicate(true)
	return clone


func get_contract_report() -> Dictionary:
	return {
		"ok": validation_errors.is_empty(),
		"item_instance_count": items.size(),
		"registered_item_definition_count": item_defs.size(),
		"errors": validation_errors.duplicate(),
		"warnings": validation_warnings.duplicate(),
	}


func clear() -> void:
	items.clear()
	validation_errors.clear()
	validation_warnings.clear()
	last_error = ""


func _append_history(change: Dictionary) -> bool:
	var item_instance_id := _change_item_id(change)
	if not items.has(item_instance_id):
		return _reject("%s:unknown_item" % item_instance_id)
	var entry: Variant = change.get("history_entry", {})
	if not entry is Dictionary:
		return _reject("%s:history_entry_not_dictionary" % item_instance_id)
	var source_fact_id := str((entry as Dictionary).get(
		"fact_id",
		(entry as Dictionary).get("source_fact_id", "")
	))
	if source_fact_id == "" or not _fact_exists(source_fact_id):
		return _reject("%s:history_requires_source_fact" % item_instance_id)
	var stored: Dictionary = items[item_instance_id]
	var history: Array = (stored.get("history", []) as Array).duplicate(true)
	var normalized_entry := (entry as Dictionary).duplicate(true)
	normalized_entry["fact_id"] = source_fact_id
	normalized_entry.erase("source_fact_id")
	history.append(normalized_entry)
	stored["history"] = history
	stored["updated_tick"] = int(change.get(
		"updated_tick",
		_fact_tick(fact_store.get_fact(source_fact_id))
	))
	items[item_instance_id] = stored
	return true


func _transfer_item(change: Dictionary) -> bool:
	var item_instance_id := _change_item_id(change)
	if not items.has(item_instance_id):
		return _reject("%s:unknown_item" % item_instance_id)
	var source_fact_value: Variant = change.get("source_fact_ids", [])
	if not source_fact_value is Array:
		return _reject("%s:source_fact_ids_not_array" % item_instance_id)
	var source_fact_ids: Array = (source_fact_value as Array).duplicate(true)
	if source_fact_ids.is_empty() or not _facts_exist(source_fact_ids):
		return _reject("%s:transfer_requires_source_fact" % item_instance_id)
	var holder: Variant = change.get("new_holder", {})
	if not holder is Dictionary or not _holder_is_valid(holder, item_instance_id):
		return _reject("%s:invalid_transfer_holder" % item_instance_id)
	if str((holder as Dictionary).get("kind", "")) == "destroyed":
		return _reject("%s:transfer_cannot_destroy" % item_instance_id)
	var stored: Dictionary = items[item_instance_id]
	if _is_destroyed(stored):
		return _reject("%s:item_destroyed" % item_instance_id)
	if _holders_equal(stored.get("holder", {}), holder):
		return _reject("%s:holder_unchanged" % item_instance_id)
	var previous_holder: Dictionary = (
		stored.get("holder", {}) as Dictionary
	).duplicate(true)
	stored["holder"] = (holder as Dictionary).duplicate(true)
	stored["updated_tick"] = _source_tick(source_fact_ids, change)
	_append_generated_history(stored, "transferred", source_fact_ids, {
		"from_holder": previous_holder,
		"to_holder": (holder as Dictionary).duplicate(true),
	})
	items[item_instance_id] = stored
	return true


func _consume_item(change: Dictionary) -> bool:
	var item_instance_id := _change_item_id(change)
	if not items.has(item_instance_id):
		return _reject("%s:unknown_item" % item_instance_id)
	var source_fact_value: Variant = change.get("source_fact_ids", [])
	if not source_fact_value is Array:
		return _reject("%s:source_fact_ids_not_array" % item_instance_id)
	var source_fact_ids: Array = (source_fact_value as Array).duplicate(true)
	if source_fact_ids.is_empty() or not _facts_exist(source_fact_ids):
		return _reject("%s:consume_requires_source_fact" % item_instance_id)
	var stored: Dictionary = items[item_instance_id]
	var definition: Dictionary = item_defs.get(str(stored.get("item_def_id", "")), {})
	if "consume" not in (definition.get("capabilities", []) as Array):
		return _reject("%s:item_not_consumable" % item_instance_id)
	var quantity_value: Variant = change.get("quantity", 0)
	if not _is_whole_number(quantity_value):
		return _reject("%s:consume_quantity_not_integer" % item_instance_id)
	var quantity := int(quantity_value)
	var current_quantity := int(stored.get("quantity", 0))
	if quantity < 1 or quantity > current_quantity:
		return _reject("%s:invalid_consume_quantity" % item_instance_id)
	stored["quantity"] = current_quantity - quantity
	if int(stored["quantity"]) == 0:
		stored["holder"] = {"kind": "destroyed", "id": ""}
	stored["updated_tick"] = _source_tick(source_fact_ids, change)
	_append_generated_history(stored, "consumed", source_fact_ids, {
		"quantity": quantity,
	})
	items[item_instance_id] = stored
	return true


func _adjust_durability(change: Dictionary) -> bool:
	var item_instance_id := _change_item_id(change)
	if not items.has(item_instance_id):
		return _reject("%s:unknown_item" % item_instance_id)
	var source_fact_value: Variant = change.get("source_fact_ids", [])
	if not source_fact_value is Array:
		return _reject("%s:source_fact_ids_not_array" % item_instance_id)
	var source_fact_ids: Array = (source_fact_value as Array).duplicate(true)
	if source_fact_ids.is_empty() or not _facts_exist(source_fact_ids):
		return _reject("%s:durability_requires_source_fact" % item_instance_id)
	var stored: Dictionary = items[item_instance_id]
	if _is_destroyed(stored):
		return _reject("%s:item_destroyed" % item_instance_id)
	var condition: Dictionary = (stored.get("condition", {}) as Dictionary).duplicate(true)
	var maximum := int(condition.get("maximum_durability", 0))
	if maximum < 1:
		return _reject("%s:item_has_no_durability" % item_instance_id)
	var current := int(condition.get("durability", maximum))
	var next := current
	if change.has("to"):
		var to_value: Variant = change.get("to", current)
		if not _is_whole_number(to_value):
			return _reject("%s:durability_not_integer" % item_instance_id)
		next = int(to_value)
	elif change.has("delta"):
		var delta_value: Variant = change.get("delta", 0)
		if not _is_whole_number(delta_value):
			return _reject("%s:durability_delta_not_integer" % item_instance_id)
		next = current + int(delta_value)
	else:
		return _reject("%s:missing_durability_operation" % item_instance_id)
	if next < 0 or next > maximum:
		return _reject("%s:durability_out_of_range" % item_instance_id)
	condition["durability"] = next
	stored["condition"] = condition
	stored["updated_tick"] = _source_tick(source_fact_ids, change)
	_append_generated_history(stored, "durability_changed", source_fact_ids, {
		"from": current,
		"to": next,
	})
	items[item_instance_id] = stored
	return true


func _split_stack(change: Dictionary) -> bool:
	var item_instance_id := _change_item_id(change)
	var new_id := str(change.get("new_item_instance_id", ""))
	if not items.has(item_instance_id) or new_id == "" or items.has(new_id):
		return _reject("%s:invalid_split_identity" % item_instance_id)
	var source_fact_value: Variant = change.get("source_fact_ids", [])
	if not source_fact_value is Array:
		return _reject("%s:source_fact_ids_not_array" % item_instance_id)
	var source_fact_ids: Array = (source_fact_value as Array).duplicate(true)
	if source_fact_ids.is_empty() or not _facts_exist(source_fact_ids):
		return _reject("%s:split_requires_source_fact" % item_instance_id)
	var stored: Dictionary = items[item_instance_id]
	var definition: Dictionary = item_defs.get(str(stored.get("item_def_id", "")), {})
	if not bool(definition.get("stackable", false)):
		return _reject("%s:item_not_stackable" % item_instance_id)
	var quantity_value: Variant = change.get("quantity", 0)
	if not _is_whole_number(quantity_value):
		return _reject("%s:split_quantity_not_integer" % item_instance_id)
	var quantity := int(quantity_value)
	var current_quantity := int(stored.get("quantity", 0))
	if quantity < 1 or quantity >= current_quantity:
		return _reject("%s:invalid_split_quantity" % item_instance_id)
	var new_holder: Variant = change.get("new_holder", stored.get("holder", {}))
	if not new_holder is Dictionary or not _holder_is_valid(new_holder, new_id):
		return _reject("%s:invalid_split_holder" % item_instance_id)
	stored["quantity"] = current_quantity - quantity
	stored["updated_tick"] = _source_tick(source_fact_ids, change)
	_append_generated_history(stored, "stack_split", source_fact_ids, {
		"quantity": quantity,
		"new_item_instance_id": new_id,
	})
	var split := stored.duplicate(true)
	split["item_instance_id"] = new_id
	split["holder"] = (new_holder as Dictionary).duplicate(true)
	split["quantity"] = quantity
	split["history"] = []
	var provenance: Dictionary = (
		split.get("provenance", {}) as Dictionary
	).duplicate(true)
	provenance["created_by_fact_id"] = str(source_fact_ids[0])
	provenance["parent_item_instance_ids"] = [item_instance_id]
	split["provenance"] = provenance
	split["created_tick"] = _source_tick(source_fact_ids, change)
	split["updated_tick"] = split["created_tick"]
	_append_generated_history(split, "split_from", source_fact_ids, {
		"source_item_instance_id": item_instance_id,
		"quantity": quantity,
	})
	items[item_instance_id] = stored
	items[new_id] = split
	return true


func _project_item(value: Dictionary) -> Dictionary:
	var item := value.duplicate(true)
	var item_instance_id := str(item.get("item_instance_id", ""))
	var definition: Dictionary = item_defs.get(str(item.get("item_def_id", "")), {})
	item["item_id"] = item_instance_id
	item["id"] = item_instance_id
	item["item_type"] = str(definition.get("item_kind", ""))
	if str(item.get("display_name", "")) == "":
		item["display_name"] = str(
			definition.get("display_name", item.get("item_def_id", ""))
		)
	item["equip_slots"] = (definition.get("equip_slots", []) as Array).duplicate(true)
	item["capabilities"] = (
		definition.get("capabilities", []) as Array
	).duplicate(true)
	item["base_mass"] = float(definition.get("base_mass", 0.0))
	item["base_value"] = float(definition.get("base_value", 0.0))
	item["modifiers"] = (definition.get("modifiers", []) as Array).duplicate(true)
	var tags: Array = (definition.get("tags", []) as Array).duplicate(true)
	for tag: Variant in item.get("custom_tags", []):
		if tag not in tags:
			tags.append(tag)
	item["tags"] = tags
	var holder: Dictionary = item.get("holder", {})
	item["owner_id"] = (
		str(holder.get("id", ""))
		if str(holder.get("kind", "")) == "entity"
		else ""
	)
	return item


func _normalized_holder(item: Dictionary) -> Dictionary:
	var holder: Variant = item.get("holder", {})
	if holder is Dictionary and not (holder as Dictionary).is_empty():
		return (holder as Dictionary).duplicate(true)
	var owner_id := str(item.get("owner_id", ""))
	if owner_id != "":
		return {"kind": "entity", "id": owner_id}
	var location_id := str(item.get("location_id", ""))
	if location_id != "":
		return {"kind": "location", "id": location_id}
	return {}


func _holder_is_valid(holder: Dictionary, item_instance_id: String) -> bool:
	var kind := str(holder.get("kind", ""))
	var holder_id := str(holder.get("id", ""))
	if kind not in HOLDER_KINDS:
		return false
	match kind:
		"entity":
			return holder_id != "" and entity_store != null and entity_store.has_entity(holder_id)
		"location":
			return holder_id != "" and location_ids.has(holder_id)
		"container":
			return _container_holder_is_valid(item_instance_id, holder_id)
		"escrow":
			return holder_id != ""
		"destroyed":
			return holder_id == ""
	return false


func _container_holder_is_valid(item_instance_id: String, container_id: String) -> bool:
	if container_id == "" or container_id == item_instance_id or not items.has(container_id):
		return false
	var current_id := container_id
	var visited: Dictionary = {}
	while current_id != "":
		if current_id == item_instance_id or visited.has(current_id):
			return false
		visited[current_id] = true
		if not items.has(current_id):
			return false
		var holder: Dictionary = (items[current_id] as Dictionary).get("holder", {})
		if str(holder.get("kind", "")) != "container":
			return true
		current_id = str(holder.get("id", ""))
	return false


func _quantity_is_valid(
		quantity: int,
		holder: Dictionary,
		definition: Dictionary
) -> bool:
	if str(holder.get("kind", "")) == "destroyed":
		return quantity == 0
	if quantity < 1 or quantity > int(definition.get("max_stack", 1)):
		return false
	return bool(definition.get("stackable", false)) or quantity == 1


func _normalized_condition(item: Dictionary, definition: Dictionary) -> Dictionary:
	var condition: Dictionary = (item.get("condition", {}) as Dictionary).duplicate(true)
	var durability_def: Dictionary = definition.get("durability", {})
	if durability_def.is_empty():
		condition.erase("durability")
		condition.erase("maximum_durability")
		return condition
	var maximum := int(durability_def.get("maximum", 0))
	condition["maximum_durability"] = maximum
	condition["durability"] = clampi(
		int(condition.get("durability", maximum)),
		0,
		maximum
	)
	condition["quality"] = str(condition.get("quality", "serviceable"))
	return condition


func _condition_is_valid(item: Dictionary, definition: Dictionary) -> bool:
	var condition: Variant = item.get("condition", {})
	if not condition is Dictionary:
		return false
	var durability_def: Dictionary = definition.get("durability", {})
	if durability_def.is_empty():
		return not (condition as Dictionary).has("durability") and not (
			condition as Dictionary
		).has("maximum_durability")
	var maximum := int(durability_def.get("maximum", 0))
	if (
		(condition as Dictionary).has("maximum_durability")
	):
		var supplied_maximum: Variant = (condition as Dictionary).get(
			"maximum_durability",
			0
		)
		if (
			not _is_whole_number(supplied_maximum)
			or int(supplied_maximum) != maximum
		):
			return false
	var durability: Variant = (condition as Dictionary).get("durability", maximum)
	return (
		_is_whole_number(durability)
		and int(durability) >= 0
		and int(durability) <= maximum
	)


func _custom_tags(item: Dictionary, definition: Dictionary) -> Array:
	var tags: Array = (item.get("custom_tags", []) as Array).duplicate(true)
	var definition_tags: Array = definition.get("tags", [])
	for tag: Variant in item.get("tags", []):
		if tag not in definition_tags and tag not in tags:
			tags.append(tag)
	return tags


func _append_generated_history(
		stored: Dictionary,
		event_type: String,
		source_fact_ids: Array,
		extra: Dictionary
) -> void:
	var history: Array = (stored.get("history", []) as Array).duplicate(true)
	var entry := extra.duplicate(true)
	entry["event_type"] = event_type
	entry["fact_id"] = str(source_fact_ids[0])
	history.append(entry)
	stored["history"] = history


func _change_item_id(change: Dictionary) -> String:
	return str(change.get("item_instance_id", change.get("item_id", "")))


func _is_destroyed(item: Dictionary) -> bool:
	return str((item.get("holder", {}) as Dictionary).get("kind", "")) == "destroyed"


func _holders_equal(a: Variant, b: Variant) -> bool:
	if not a is Dictionary or not b is Dictionary:
		return false
	return (
		str((a as Dictionary).get("kind", ""))
			== str((b as Dictionary).get("kind", ""))
		and str((a as Dictionary).get("id", ""))
			== str((b as Dictionary).get("id", ""))
	)


func _facts_exist(fact_ids: Array) -> bool:
	for fact_id: Variant in fact_ids:
		if not _fact_exists(str(fact_id)):
			return false
	return true


func _fact_exists(fact_id: String) -> bool:
	return fact_id != "" and fact_store != null and not fact_store.get_fact(fact_id).is_empty()


func _is_whole_number(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_equal_approx(float(value), roundf(float(value)))
	)


func _source_tick(source_fact_ids: Array, change: Dictionary) -> int:
	if change.has("updated_tick"):
		return int(change.get("updated_tick", 0))
	return _fact_tick(fact_store.get_fact(str(source_fact_ids[0])))


func _fact_tick(fact: Dictionary) -> int:
	if fact.has("tick"):
		return int(fact.get("tick", 0))
	return int(fact.get("day", 0)) * 24 + int(fact.get("hour", 0))


func _reject(message: String) -> bool:
	last_error = message
	validation_errors.append(message)
	return false
