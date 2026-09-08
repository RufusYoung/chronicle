extends RefCounted
class_name V5WorkRecipeService

const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const ItemSources = preload("res://scripts/sim/item/item_causal_sources.gd")
const QUERY_KEYS := ["item_def_id", "tags_all", "tags_any", "capabilities_all"]

var snapshot: Variant
var registry: Variant
var consumed: Dictionary = {}
var worn: Dictionary = {}


func _init(source_snapshot: Variant = null, source_registry: Variant = null) -> void:
	snapshot = source_snapshot
	registry = source_registry


static func enabled(profile: Dictionary) -> bool:
	var recipe: Variant = profile.get("work_recipe", {})
	return recipe is Dictionary and recipe.get("version", 0) == 1


static func matches(item: Dictionary, query: Dictionary) -> bool:
	if query.has("item_def_id") and item.get("item_def_id") != query.item_def_id:
		return false
	for key: String in ["tags_all", "capabilities_all"]:
		var values: Array = item.get("tags" if key == "tags_all" else "capabilities", [])
		for value: String in query.get(key, []):
			if value not in values:
				return false
	var any_tags: Array = query.get("tags_any", [])
	return any_tags.is_empty() or any_tags.any(func(tag: String) -> bool: return tag in item.get("tags", []))


static func validate_profile(profile: Dictionary, definitions: Variant) -> String:
	var value: Variant = profile.get("work_recipe", {})
	if not value is Dictionary:
		return "work_recipe_not_dictionary"
	if value.is_empty():
		return ""
	if value.get("version") != 1 or not _integer(value.get("version"), 1):
		return "unsupported_work_recipe_version"
	for key: String in value:
		if key not in ["version", "recipe_id", "item_inputs", "tools", "repairs"]:
			return "unknown_work_recipe_field:" + key
	if not value.get("recipe_id") is String or str(value.recipe_id).strip_edges() == "":
		return "missing_work_recipe_id"
	if not _integer(profile.get("work_interval_hours"), 1):
		return "invalid_work_recipe_hours"
	if not value.get("repairs", []) is Array:
		return "invalid_work_recipe_repairs"
	if not profile.get("products") is Array or (profile.products.is_empty() and value.get("repairs", []).is_empty()):
		return "work_recipe_requires_products"
	for product: Variant in profile.products:
		if not product is Dictionary or not _integer(product.get("quantity"), 1):
			return "invalid_work_recipe_product"
		var definition: Dictionary = definitions.get_definition("item", str(product.get("item_def_id", "")))
		if definition.is_empty() or definition.get("item_kind") == "currency":
			return "unknown_or_currency_work_recipe_product"
	if not profile.get("resource_inputs", []) is Array:
		return "invalid_work_recipe_resources"
	var stock_ids: Array = []
	for input: Variant in profile.get("resource_inputs", []):
		if not input is Dictionary or str(input.get("stock_id", "")) == "" \
				or not (input.get("amount_per_cycle") is int or input.get("amount_per_cycle") is float) \
				or not is_finite(float(input.amount_per_cycle)) or float(input.amount_per_cycle) <= 0:
			return "invalid_work_recipe_resource"
		if input.stock_id in stock_ids:
			return "duplicate_work_recipe_resource"
		stock_ids.append(input.stock_id)
	for collection: String in ["item_inputs", "tools", "repairs"]:
		if not value.get(collection, []) is Array:
			return "invalid_work_recipe_" + collection
		for input: Variant in value.get(collection, []):
			if not input is Dictionary:
				return "invalid_work_recipe_input"
			for key: String in input:
				if key not in (["query", "restore", "maximum_repairs"] if collection == "repairs" else ["query", "quantity", "wear"]):
					return "unknown_work_recipe_input_field:" + key
			if not input.get("query") is Dictionary or input.query.is_empty():
				return "missing_work_recipe_query"
			for key: String in input.query:
				if key not in QUERY_KEYS:
					return "unknown_work_recipe_query:" + key
				if key == "item_def_id":
					if not definitions.has_definition("item", str(input.query[key])):
						return "unknown_work_recipe_item"
				elif not input.query[key] is Array or input.query[key].is_empty():
					return "invalid_work_recipe_query_values"
				else:
					for tag: Variant in input.query[key]:
						if not tag is String or str(tag).strip_edges() == "":
							return "invalid_work_recipe_query_value"
			var numeric_key := "quantity" if collection == "item_inputs" else ("restore" if collection == "repairs" else "wear")
			if not _integer(input.get(numeric_key), 1) or input.has("wear" if numeric_key == "quantity" else "quantity"):
				return "invalid_work_recipe_" + numeric_key
			if collection == "repairs" and not _integer(input.get("maximum_repairs"), 1):
				return "invalid_work_recipe_repair_limit"
			var suitable := false
			for definition: Dictionary in definitions.list_definitions("item").values():
				if matches(definition, input.query) and definition.get("item_kind") != "currency":
					suitable = suitable or ("consume" in definition.get("capabilities", []) if collection == "item_inputs" \
						else int(definition.get("durability", {}).get("maximum", 0)) >= int(input.get("wear", 1)))
			if not suitable:
				return "work_recipe_query_has_no_usable_definition"
	if profile.get("resource_inputs", []).is_empty() and value.get("item_inputs", []).is_empty():
		return "work_recipe_requires_material_input"
	return ""


func plan_inputs(profile: Dictionary, actor: String, fact_id: String, tick: int) -> Dictionary:
	if registry == null:
		return _blocked("missing_work_registry")
	var error := validate_profile(profile, registry)
	if error != "":
		return _blocked(error)
	var place := str(profile.get("workplace_id", ""))
	if place == "" or snapshot.get_entity_state(actor, "location_id", "") != place \
			or snapshot.get_entity_state(actor, "daily_route_id", "") != "":
		return _blocked("worker_not_at_worksite")
	var holders: Array = [actor]
	var depot: Dictionary = snapshot.get_entity(Storage.depot_id(actor))
	if depot.get("stock_custodian_id") == actor and depot.get("stock_location_id") == place \
			and snapshot.get_entity_state(str(depot.id), "location_id", "") == place:
		holders.append(str(depot.id))
	var items: Array = []
	for holder: String in holders:
		items.append_array(snapshot.get_items_for_holder(holder))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.item_instance_id) < str(b.item_instance_id))
	var next_consumed := consumed.duplicate()
	var next_worn := worn.duplicate()
	var changes: Array = []
	var inputs: Array = []
	var tools_used: Array = []
	var repaired: Array = []
	var sources: Array = []
	for spec: Dictionary in profile.work_recipe.get("item_inputs", []):
		var remaining := int(spec.quantity)
		for item: Dictionary in items:
			var id := str(item.item_instance_id)
			if not matches(item, spec.query) or "consume" not in item.capabilities or item.item_type == "currency":
				continue
			var amount := mini(remaining, maxi(int(item.quantity) - int(next_consumed.get(id, 0)), 0))
			if amount == 0:
				continue
			next_consumed[id] = int(next_consumed.get(id, 0)) + amount
			changes.append({"operation": "consume", "item_instance_id": id, "quantity": amount,
				"expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
			inputs.append({"item_instance_id": id, "item_def_id": item.item_def_id, "quantity": amount})
			_add_item_sources(sources, item)
			remaining -= amount
			if remaining == 0:
				break
		if remaining > 0:
			return _blocked("work_item_input_missing", {"query": spec.query, "missing_quantity": remaining})
	for spec: Dictionary in profile.work_recipe.get("tools", []):
		var selected := false
		for item: Dictionary in items:
			var id := str(item.item_instance_id)
			var durability := int(next_worn.get(id, item.get("condition", {}).get("durability", 0)))
			var available := int(item.quantity) - int(next_consumed.get(id, 0))
			if available < 1 or durability < int(spec.wear) or not matches(item, spec.query) or item.item_type == "currency":
				continue
			var tool_id := id
			# Wear one physical tool, not every rope in its stack.
			if available > 1:
				tool_id = "%s.tool.%d" % [fact_id, tools_used.size()]
				changes.append({"operation": "split_stack", "item_instance_id": id, "quantity": 1,
					"new_item_instance_id": tool_id, "expected_holder": item.holder,
					"source_fact_ids": [fact_id], "updated_tick": tick})
				next_consumed[id] = int(next_consumed.get(id, 0)) + 1
			else:
				# One tool may fulfill only one role in a work cycle.
				next_consumed[id] = int(next_consumed.get(id, 0)) + 1
			changes.append({"operation": "adjust_durability", "item_instance_id": tool_id,
				"to": durability - int(spec.wear), "expected_holder": item.holder,
				"source_fact_ids": [fact_id], "updated_tick": tick})
			next_worn[tool_id] = durability - int(spec.wear)
			tools_used.append({"item_instance_id": tool_id, "source_item_instance_id": id,
				"item_def_id": item.item_def_id, "wear": spec.wear, "remaining_durability": next_worn[tool_id]})
			_add_item_sources(sources, item)
			selected = true
			break
		if not selected:
			return _blocked("work_tool_missing_or_worn", {"query": spec.query, "required_durability": spec.wear})
	for spec: Dictionary in profile.work_recipe.get("repairs", []):
		var selected := false
		for item: Dictionary in items:
			var id := str(item.item_instance_id)
			if int(next_consumed.get(id, 0)) >= int(item.quantity) or not repairable(item, spec, snapshot):
				continue
			var target := id
			if int(item.quantity) - int(next_consumed.get(id, 0)) > 1:
				target = "%s.repair.%d" % [fact_id, repaired.size()]
				changes.append({"operation": "split_stack", "item_instance_id": id, "quantity": 1,
					"new_item_instance_id": target, "expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
			var after := mini(int(item.condition.maximum_durability), int(item.condition.durability) + int(spec.restore))
			changes.append({"operation": "adjust_durability", "item_instance_id": target, "to": after,
				"expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
			next_consumed[id] = int(next_consumed.get(id, 0)) + 1
			repaired.append({"item_instance_id": target, "source_item_instance_id": id, "item_def_id": item.item_def_id,
				"before": item.condition.durability, "after": after})
			_add_item_sources(sources, item)
			selected = true
			break
		if not selected:
			return _blocked("no_repairable_owned_tool")
	return {"ok": true, "changes": changes, "inputs": inputs, "tools": tools_used,
		"repairs": repaired, "source_fact_ids": sources, "consumed": next_consumed, "worn": next_worn}


static func repairable(item: Dictionary, spec: Dictionary, source_snapshot: Variant) -> bool:
	if int(item.get("quantity", 0)) < 1 or not matches(item, spec.query) \
			or int(item.get("condition", {}).get("durability", -1)) != 0 \
			or int(item.get("condition", {}).get("maximum_durability", 0)) < 1:
		return false
	var repairs := 0
	for fact: Dictionary in source_snapshot.get_facts_by_type("npc_work_maintained"):
		for row: Dictionary in fact.get("repairs", []):
			if row.get("item_instance_id") == item.item_instance_id:
				repairs += 1
	return repairs < int(spec.maximum_repairs)


func append_inputs(result: Variant, plan: Dictionary) -> void:
	for change: Dictionary in plan.changes:
		result.add_item_change(change)
	consumed = plan.consumed
	worn = plan.worn


func append_products(result: Variant, profile: Dictionary, actor: String, storage_config: Dictionary, fact_id: String, tick: int) -> Array:
	var rows: Array = []
	var ordinal := 0
	# Aggregate duplicate product rows before filling stacks.
	var amounts := {}
	for product: Dictionary in profile.products:
		amounts[product.item_def_id] = int(amounts.get(product.item_def_id, 0)) + int(product.quantity)
	for definition_id: String in amounts:
		var holder := Storage.production_holder(snapshot, actor, definition_id, storage_config)
		var remaining := int(amounts[definition_id])
		var definition: Dictionary = registry.get_definition("item", definition_id)
		var maximum := int(definition.get("max_stack", 1)) if definition.get("stackable", false) else 1
		rows.append({"item_def_id": definition_id, "quantity": remaining})
		for item: Dictionary in snapshot.get_items_for_holder(holder):
			if item.item_def_id != definition_id or int(consumed.get(str(item.item_instance_id), 0)) > 0 \
					or not definition.get("stackable", false):
				continue
			# New output cannot rejuvenate an already worn tool stack.
			if not definition.get("durability", {}).is_empty():
				continue
			var amount := mini(remaining, maximum - int(item.quantity))
			if amount <= 0:
				continue
			result.add_item_change({"operation": "increase_quantity", "item_instance_id": item.item_instance_id,
				"quantity": amount, "expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
			remaining -= amount
			if remaining == 0:
				break
		while remaining > 0:
			var amount := mini(remaining, maximum)
			result.add_item_change({"operation": "create", "source_fact_ids": [fact_id], "item": {
				"item_instance_id": "%s.output.%d" % [fact_id, ordinal], "item_def_id": definition_id,
				"holder": {"kind": "entity", "id": holder}, "quantity": amount,
				"condition": {}, "custom_tags": ["livelihood_product"],
				"provenance": {"producer_id": actor, "recipe_id": profile.work_recipe.recipe_id},
				"history": [], "created_tick": tick, "updated_tick": tick}})
			remaining -= amount
			ordinal += 1
	return rows


static func _integer(value: Variant, minimum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and int(value) >= minimum


static func _blocked(reason: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "changes": [], "missing": {"label": "作业材料或工具", "denial": reason, "details": details}}


static func _add_item_sources(sources: Array, item: Dictionary) -> void:
	ItemSources.append_to(sources, item)
