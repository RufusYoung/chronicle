extends RefCounted

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const SLOT_NAMES := {"main_hand": "手持", "body_outer": "外衣", "utility": "随身用具"}


static func enabled(session: Variant) -> bool:
	return session.fixture_source_data.get("integration_rules", {}).get("version", 0) == 2


static func describe(item: Dictionary) -> String:
	var lines: Array[String] = []
	if item.get("condition", {}).has("durability"):
		lines.append("耐久 %d/%d" % [item.condition.durability, item.condition.maximum_durability])
		if int(item.condition.durability) <= 0:
			lines.append("已损坏，被动失效；修补次数与材料仍有限")
	elif item.get("durability", {}).has("maximum"):
		lines.append("耐久上限%d" % int(item.durability.maximum))
	for modifier: Dictionary in item.get("modifiers", []):
		var line := str(modifier.get("explain_text", ""))
		var label := str({"combat.attack": "进攻", "combat.guard": "防守", "combat.escape": "脱离"}.get(modifier.get("target"), ""))
		if label != "":
			line = label + ("+" if float(modifier.value) >= 0 else "") + str(int(modifier.value))
		for condition: Dictionary in modifier.get("when", []):
			if condition.get("kind") == "state":
				line += "（%s%s%s时）" % [{"health": "健康"}.get(condition.get("key"), condition.get("key")),
					{"lte": "≤", "gte": "≥"}.get(condition.get("operator"), "="), condition.get("value")]
			elif condition.get("kind") == "context_tag":
				line += "（%s）" % {"dim_light": "昏暗时", "freezing": "严寒时"}.get(condition.get("tag"), condition.get("tag"))
			elif condition.get("kind") == "action_tag" and condition.get("tag") != "combat":
				line += "（%s）" % {"combat_melee": "近身进攻时", "combat_retreat": "撤离时"}.get(condition.get("tag"), condition.get("tag"))
		lines.append(line)
	return "；".join(lines)


static func options(session: Variant) -> Array:
	if not enabled(session):
		return []
	var id := str(session.context.actor_id)
	var state: Dictionary = session.stores.state_store.states.get(id, {})
	if state.get("daily_route_id", "") != "" or state.get("danger_opponent_id", "") != "":
		return []
	var rows: Array = []
	for item: Dictionary in session.stores.item_store.list_items_for_owner(id):
		if "equip" not in item.get("capabilities", []) or int(item.get("condition", {}).get("durability", 0)) <= 0:
			continue
		for slot: String in item.get("equip_slots", []):
			var old := str(session.stores.equipment_store.get_equipped_item_id(id, slot))
			if old == item.item_instance_id:
				continue
			var previous: Dictionary = session.stores.item_store.get_item(old)
			var hint := describe(item) + "。替换%s；旧装备仍留在行囊。" % previous.get("display_name", "空槽位")
			rows.append(_row("equip:" + str(item.item_instance_id) + ":" + slot, "装备" + str(item.display_name), hint, slot, str(item.item_instance_id)))
	for slot: String in SLOT_NAMES:
		var old := str(session.stores.equipment_store.get_equipped_item_id(id, slot))
		if old != "":
			rows.append(_row("unequip:" + slot, "取下" + str(session.stores.item_store.get_item(old).display_name),
				"空出%s，物品留在行囊，相关被动不再生效。" % SLOT_NAMES[slot], slot, ""))
	return rows


static func _row(id: String, label: String, hint: String, slot: String, item: String) -> Dictionary:
	return {"action_id": id, "event_type": "player_life", "label": label, "hint": hint,
		"hours": 1, "cost": "整理装备需1小时", "known_effect": hint, "tradeoff": "途中或交锋中不能换装。",
		"can_execute": true, "blocked_reason": "", "action_type": "life", "life_group": "gear", "slot_id": slot, "item_instance_id": item}


static func execute(session: Variant, option: Dictionary) -> Dictionary:
	var result := Result.new()
	var actor := str(session.context.actor_id)
	var fact_id := "fact.player_equipped.%d" % session.elapsed_hours_since_start
	var clear: bool = str(option.item_instance_id) == ""
	result.add_fact({"fact_id": fact_id, "fact_type": "player_equipment_changed", "actor_id": actor,
		"day": session.current_day, "hour": session.current_hour, "location_id": session.context.location_id,
		"item_instance_id": option.item_instance_id, "slot_id": option.slot_id, "summary": option.label + "。" + option.hint})
	var change := {"operation": "equipment_clear" if clear else "equipment_set", "entity_id": actor,
		"slot_id": option.slot_id, "source_fact_ids": [fact_id]}
	if not clear:
		change["item_instance_id"] = option.item_instance_id
	result.add_equipment_change(change)
	result.mark_resolved("player_equipment_changed")
	if not session.writer.apply_result(result, session.stores):
		return {"success": false, "error": result.error_reason}
	var response: Dictionary = session.advance_time(1, "player_equipment")
	response["player_life_feedback"] = {"title": option.label, "body": option.hint, "details": [], "summary_details": []}
	return response


static func journal(session: Variant) -> Dictionary:
	if not enabled(session):
		return {}
	var actor := str(session.context.actor_id)
	var items: Array = []
	for item: Dictionary in session.stores.item_store.list_items_for_owner(actor):
		if item.item_def_id == "item.copper_coin":
			continue
		var slots: Array[String] = []
		for slot: String in SLOT_NAMES:
			if session.stores.equipment_store.get_equipped_item_id(actor, slot) == item.item_instance_id:
				slots.append(SLOT_NAMES[slot])
		items.append({"id": item.item_instance_id, "definition_id": item.item_def_id, "name": item.display_name, "quantity": item.quantity,
			"equipped": "、".join(slots), "description": describe(item)})
	var features: Array = []
	var store: Variant = session.stores.character_feature_store
	for definition: Dictionary in session.fixture_source_data.integration_rules.feature_defs.skill:
		var xp := 0
		var rank := 0
		for progress: Dictionary in store.list_skill_progress(actor):
			if progress.skill_def_id == definition.skill_def_id:
				xp = int(progress.practice_xp)
				rank = int(progress.rank)
		var thresholds: Array = definition.rank_thresholds
		var progress_label := "%d/%d经验" % [xp, int(thresholds[rank + 1])] if rank + 1 < thresholds.size() else "已熟练 · %d经验" % xp
		features.append({"id": definition.skill_def_id, "kind": "skill", "rank": rank, "xp": xp,
			"name": definition.display_name, "state": "%d级 · %s" % [rank, progress_label], "description": definition.description})
	for definition: Dictionary in session.fixture_source_data.integration_rules.feature_defs.trait:
		var acquired: bool = store.list_trait_instances(actor).any(func(t: Dictionary) -> bool:
			return t.trait_def_id == definition.trait_def_id and t.status == "active")
		features.append({"id": definition.trait_def_id, "kind": "trait", "acquired": acquired,
			"name": definition.display_name, "state": "已形成" if acquired else "尚未形成",
			"description": definition.description})
	var catalog: Array = []
	for definition: Dictionary in session.fixture_source_data.integration_rules.item_defs:
		var recipe: Dictionary = session.fixture_source_data.integration_rules.recipes.filter(func(r: Dictionary) -> bool:
			return r.products.any(func(p: Dictionary) -> bool: return p.item_def_id == definition.item_def_id))[0]
		var skill: Dictionary = recipe.work_recipe.get("required_skill", {})
		catalog.append({"name": definition.display_name, "definition_id": definition.item_def_id,
			"state": "基础制作" if skill.is_empty() else "编织%d级制作" % int(skill.rank),
			"description": describe(definition) + "。\n工棚制作%d小时，耗当地苇材与绳具耐久；也可向有余货的人购买。" % int(recipe.work_interval_hours)})
	var note := "编织经验打开更复杂的装备；仍需材料、时间和工具。穿戴才有被动；途中与交锋中不能换装。"
	if session.fixture_source_data.integration_rules.get("combat_wear_version") == 1:
		note += "随身用具每轮交锋磨损1耐久，归零即失效并卸下。"
	return {"items": items, "features": features, "catalog": catalog, "actions": options(session), "note": note}
