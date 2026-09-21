extends RefCounted

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")


static func enabled(actor: Dictionary) -> bool:
	return actor.get("states", {}).get("equipment_autonomy_version") == 1


static func danger_sources(snapshot: Variant, actor: Dictionary) -> Array:
	var sources: Array = []
	for memory: Dictionary in snapshot.get_memories(str(actor.id)):
		if memory.get("memory_type") == "world_danger_seen" and memory.get("danger_present", false):
			var fact := str(memory.get("source_fact_id", ""))
			if fact != "":
				sources.append(fact)
	return sources.slice(-1)


static func rating(item: Dictionary, slot: String) -> float:
	if slot not in item.get("equip_slots", []) or "equip" not in item.get("capabilities", []) \
			or int(item.get("condition", {}).get("durability", 0)) <= 0:
		return 0
	var score := 0.0
	for modifier: Dictionary in item.get("modifiers", []):
		if modifier.get("operation") == "add" and modifier.get("target") in ["combat.attack", "combat.guard", "combat.escape"]:
			score += maxf(float(modifier.get("value", 0)), 0)
	return score


static func owned(snapshot: Variant, actor: Dictionary) -> Array:
	var items: Array = snapshot.get_items_for_holder(str(actor.id))
	var depot: Dictionary = snapshot.get_entity(Storage.depot_id(str(actor.id)))
	if not depot.is_empty() and depot.get("stock_location_id") == actor.states.get("location_id") and actor.states.get("daily_route_id", "") == "":
		items.append_array(snapshot.get_items_for_holder(str(depot.id)))
	return items


static func need(snapshot: Variant, actor: Dictionary) -> Dictionary:
	if not enabled(actor) or int(actor.states.get("age_years", 0)) < 18:
		return {}
	var sources := danger_sources(snapshot, actor)
	if sources.is_empty():
		return {}
	var items := owned(snapshot, actor)
	for slot: String in ["body_outer", "main_hand"]:
		var adequate := false
		for item: Dictionary in items:
			if rating(item, slot) <= 0:
				continue
			if int(item.condition.durability) >= 4:
				adequate = true
			else:
				Recipe._add_item_sources(sources, item)
		if not adequate:
			return {"query": {"tags_all": ["armor_outer" if slot == "body_outer" else "melee_weapon"], "capabilities_all": ["equip"]},
				"quantity": 1, "minimum_durability": 4, "source_fact_ids": sources,
				"recipe_id": "equipment:" + slot, "intent_id": "work_supply:equipment:" + slot}
	return {}


static func equip(snapshot: Variant, actor: Dictionary, tick: Dictionary) -> Variant:
	var result := Result.new()
	if not enabled(actor) or actor.states.get("daily_route_id", "") != "" \
			or actor.states.get("danger_opponent_id", "") != "" or not actor.states.get("alive", true):
		return result
	var items := owned(snapshot, actor)
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.item_instance_id) < str(b.item_instance_id))
	var loadout: Dictionary = snapshot.get_equipment_loadout(str(actor.id)).get("slots", {})
	for slot: String in ["body_outer", "main_hand", "utility"]:
		var current: Dictionary = snapshot.get_item(str(loadout.get("slot." + slot, "")))
		var best := current
		for item: Dictionary in items:
			if rating(item, slot) > rating(best, slot) or (rating(item, slot) > 0 and rating(item, slot) == rating(best, slot) \
					and int(item.condition.durability) > int(best.get("condition", {}).get("durability", 0))):
				best = item
		if best.is_empty() or best.get("item_instance_id") == current.get("item_instance_id"):
			continue
		var id := "fact.resident_equipped.%s.%d.%s" % [actor.id, int(tick.day) * 24 + int(tick.hour), slot]
		var sources: Array = []
		Recipe._add_item_sources(sources, best)
		if best.holder.id != actor.id:
			result.add_item_change({"operation": "transfer", "item_instance_id": best.item_instance_id,
				"expected_holder": best.holder, "new_holder": {"kind": "entity", "id": actor.id}, "source_fact_ids": [id]})
		result.add_fact({"fact_id": id, "fact_type": "resident_equipped", "actor_id": actor.id, "day": tick.day, "hour": tick.hour,
			"location_id": actor.states.location_id, "item_instance_id": best.item_instance_id, "slot_id": slot, "source_fact_ids": sources,
			"summary": "%s穿戴了自己实际拥有的%s，准备应对下一次危险。" % [actor.display_name, best.display_name]})
		result.add_equipment_change({"operation": "equipment_set", "entity_id": actor.id, "slot_id": slot,
			"item_instance_id": best.item_instance_id, "source_fact_ids": [id]})
	result.mark_resolved("resident_equipment")
	return result
