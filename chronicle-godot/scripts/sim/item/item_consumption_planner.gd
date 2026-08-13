extends RefCounted
class_name V5ItemConsumptionPlanner


func plan_owned_definition_consumption(
		snapshot: Variant,
		owner_entity_id: String,
		item_def_id: String,
		quantity: int,
		source_fact_ids: Array
) -> Dictionary:
	var remaining := quantity
	var available := 0
	var changes: Array = []
	if snapshot == null or not snapshot.has_method("get_items"):
		return {
			"supported": false,
			"ok": false,
			"available_quantity": 0,
			"missing_quantity": maxi(quantity, 0),
			"changes": changes,
		}
	if owner_entity_id == "" or item_def_id == "" or quantity < 1:
		return {
			"supported": true,
			"ok": false,
			"available_quantity": 0,
			"missing_quantity": maxi(quantity, 0),
			"changes": changes,
		}

	var items: Array = snapshot.get_items()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("item_instance_id", "")) < str(
			b.get("item_instance_id", "")
		)
	)
	for item: Dictionary in items:
		var holder: Dictionary = item.get("holder", {})
		if (
			str(item.get("item_def_id", "")) != item_def_id
			or str(holder.get("kind", "")) != "entity"
			or str(holder.get("id", "")) != owner_entity_id
		):
			continue
		var item_quantity := int(item.get("quantity", 0))
		available += item_quantity
		if remaining <= 0 or item_quantity <= 0:
			continue
		var consumed := mini(item_quantity, remaining)
		changes.append({
			"operation": "consume",
			"item_instance_id": str(item.get("item_instance_id", "")),
			"item_def_id": item_def_id,
			"display_name": str(item.get("display_name", "")),
			"quantity": consumed,
			"source_fact_ids": source_fact_ids.duplicate(true),
		})
		remaining -= consumed

	return {
		"supported": true,
		"ok": remaining == 0,
		"available_quantity": available,
		"missing_quantity": maxi(remaining, 0),
		"changes": changes,
	}
