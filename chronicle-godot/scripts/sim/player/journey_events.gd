extends RefCounted

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Sources = preload("res://scripts/sim/item/item_causal_sources.gd")


static func enabled(session: Variant) -> bool:
	return session.fixture_source_data.get("journey_rules", {}).get("version") == 1


static func knowledge(session: Variant) -> Dictionary:
	var found := {"marks": [], "closed": []}
	for fact: Dictionary in session.stores.fact_store.list_facts():
		if fact.get("actor_id") != str(session.context.actor_id):
			continue
		if fact.get("fact_type") == "journey_learned" and fact.target_id not in found.marks:
			found.marks.append(fact.target_id)
		elif fact.get("fact_type") == "journey_choice" and fact.get("closed", false):
			found.closed.append(fact.event_id)
	return found


static func current(session: Variant) -> Dictionary:
	if not enabled(session) or session.stores.state_store.get_state(str(session.context.actor_id), "daily_route_id", "") != "" or not session.get_combat_encounter_options().is_empty():
		return {}
	var known := knowledge(session)
	var bindings: Dictionary = session.fixture_source_data.journey_generated.bindings
	for event: Dictionary in session.fixture_source_data.journey_rules.events:
		if event.id in known.closed or str(bindings.get(event.location, event.location)) != str(session.context.location_id):
			continue
		if not event.get("requires", []).all(func(mark: String) -> bool: return mark in known.marks) \
				or not event.get("requires_done", []).all(func(id: String) -> bool: return id in known.closed):
			continue
		if event.has("window") and not within_hours(int(session.current_hour), event.window):
			continue
		if event.has("host") and not host_present(session, str(bindings[event.host + "_actor"])):
			continue
		return event
	return {}


static func within_hours(hour: int, window: Array) -> bool:
	return hour >= int(window[0]) and hour < int(window[1]) if window[0] < window[1] else hour >= int(window[0]) or hour < int(window[1])


static func host_present(session: Variant, id: String) -> bool:
	var states: Dictionary = session.stores.state_store.list_states(id)
	return states.get("location_id") == str(session.context.location_id) and states.get("alive", true) \
		and states.get("daily_route_id", "") == "" and states.get("danger_opponent_id", "") == ""


static func options(session: Variant) -> Array:
	var event := current(session)
	if event.is_empty():
		return []
	var known := knowledge(session)
	var rows: Array = []
	for choice: Dictionary in event.choices:
		var reason := denial(session, event, choice, known)
		var hint := str(choice.hint)
		if choice.has("check"):
			var value := int(session.stores.state_store.get_state(str(session.context.actor_id), str(choice.check.attribute), 0))
			var chance := clampi(7 - (int(choice.check.difficulty) - value), 0, 6)
			hint += " d6+%d 对 %d，成功机会%d/6。" % [value, choice.check.difficulty, chance]
		rows.append({"action_id": "adventure:" + str(event.id) + ":" + str(choice.id), "event_type": "player_life",
			"label": choice.label, "hint": hint, "known_effect": hint, "hours": int(choice.hours),
			"cost": "不耗时" if int(choice.hours) == 0 else "%d小时" % int(choice.hours),
			"tradeoff": "", "can_execute": reason == "", "blocked_reason": reason,
			"action_type": "life", "life_group": "adventure"})
	return rows


static func denial(session: Variant, event: Dictionary, choice: Dictionary, known: Dictionary) -> String:
	if not choice.get("requires", []).all(func(mark: String) -> bool: return mark in known.marks):
		return "尚不知道这条安全路线"
	var actor := str(session.context.actor_id)
	if choice.has("check") and int(session.stores.state_store.get_state(actor, "health", 100)) < 20:
		return "伤势太重，先休养或选择避险路线"
	if choice.has("tool_tag") and tool(session, choice).is_empty():
		return "缺少耐久足够的绳具"
	if choice.has("give") and available(session, actor, str(choice.give.item_def_id)) < int(choice.give.quantity):
		return "缺少可交出的物品；穿戴中的装备须先卸下"
	var payment := int(choice.get("payment", 0))
	if payment != 0:
		var host := str(session.fixture_source_data.journey_generated.bindings[event.host + "_actor"])
		if Treasury.new(session.get_snapshot()).balance(actor if payment > 0 else host) < absi(payment):
			return "你没有足够的铜币" if payment > 0 else "对方现在付不起这笔钱；稍后再来或选择保留物品"
	for outcome: Dictionary in [choice.success, choice.get("failure", {})]:
		for loot: Dictionary in outcome.get("loot", []):
			if available(session, "journey_cache." + str(event.cache), str(loot.item_def_id)) < int(loot.quantity):
				return "这里剩下的物品已经不够"
	return ""


static func available(session: Variant, owner: String, definition: String) -> int:
	var quantity := 0
	for item: Dictionary in transferable_items(session, owner, definition):
		quantity += int(item.quantity)
	return quantity


static func transferable_items(session: Variant, owner: String, definition: String) -> Array:
	var rows: Array = []
	for item: Dictionary in session.stores.item_store.list_items_for_owner(owner):
		if item.item_def_id != definition:
			continue
		var equipped := false
		for slot: String in item.get("equip_slots", []):
			if session.stores.equipment_store.get_equipped_item_id(owner, slot) == item.item_instance_id:
				equipped = true
		if not equipped:
			rows.append(item)
	return rows


static func tool(session: Variant, choice: Dictionary) -> Dictionary:
	for item: Dictionary in session.stores.item_store.list_items_for_owner(str(session.context.actor_id)):
		if choice.get("tool_tag", "") in item.get("tags", []) and int(item.get("condition", {}).get("durability", 0)) >= int(choice.get("tool_wear", 1)):
			return item
	return {}


static func execute(session: Variant, id: String) -> Dictionary:
	var event := current(session)
	if event.is_empty():
		return {"success": false, "error": "journey_no_current_event"}
	var selected: Array = event.choices.filter(func(c: Dictionary) -> bool: return id == "adventure:" + str(event.id) + ":" + str(c.id))
	if selected.is_empty() or denial(session, event, selected[0], knowledge(session)) != "":
		return {"success": false, "error": "journey_option_unavailable"}
	var choice: Dictionary = selected[0]
	var actor := str(session.context.actor_id)
	var tick := int(session.elapsed_hours_since_start)
	var fact_id := "fact.journey.%s.%s.%d.%d" % [event.id, choice.id, tick, session.stores.fact_store.list_facts().size()]
	var rng_before: int = session.challenge_rng.state
	var roll := 0
	var won := true
	var check_text := ""
	if choice.has("check"):
		roll = session.challenge_rng.randi_range(1, 6)
		var value := int(session.stores.state_store.get_state(actor, str(choice.check.attribute), 0))
		won = roll + value >= int(choice.check.difficulty)
		check_text = "掷骰%d + 属性%d / 难度%d：%s。\n" % [roll, value, choice.check.difficulty, "成功" if won else "失败"]
	var outcome: Dictionary = choice.success if won else choice.failure
	var result := Result.new()
	var body := check_text + str(outcome.text)
	var loot_text: Array[String] = []
	for loot: Dictionary in outcome.get("loot", []):
		transfer(session, result, "journey_cache." + str(event.cache), actor, str(loot.item_def_id), int(loot.quantity), fact_id, tick)
		loot_text.append("%s×%d" % [session.registry.get_definition("item", str(loot.item_def_id)).display_name, loot.quantity])
	if not loot_text.is_empty():
		body += "\n收入行囊：" + "、".join(loot_text) + "。"
	var host := str(session.fixture_source_data.journey_generated.bindings.get(str(event.get("host", "")) + "_actor", ""))
	if choice.has("give"):
		transfer(session, result, actor, host, str(choice.give.item_def_id), int(choice.give.quantity), fact_id, tick)
	var payment := int(choice.get("payment", 0))
	if payment != 0 and not Treasury.new(session.get_snapshot()).append_payment(result, actor if payment > 0 else host, host if payment > 0 else actor, absi(payment), fact_id, tick):
		session.challenge_rng.state = rng_before
		return {"success": false, "error": "journey_payment_changed"}
	if choice.has("trust"):
		result.add_relationship_change({"source_id": host, "target_id": actor, "axis": "trust", "delta": int(choice.trust)})
	if choice.has("tool_tag"):
		var item := tool(session, choice)
		var tool_id := str(item.item_instance_id)
		if int(item.quantity) > 1:
			tool_id = fact_id + ".tool"
			result.add_item_change({"operation": "split_stack", "item_instance_id": item.item_instance_id,
				"quantity": 1, "new_item_instance_id": tool_id, "expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
		var remaining := int(item.condition.durability) - int(choice.tool_wear)
		result.add_item_change({"operation": "adjust_durability", "item_instance_id": tool_id,
			"to": remaining, "expected_holder": item.holder, "source_fact_ids": [fact_id], "updated_tick": tick})
		body += "\n%s磨损%d，剩余耐久%d。" % [item.display_name, choice.tool_wear, remaining]
	if int(outcome.get("health", 0)) < 0:
		var health := int(session.stores.state_store.get_state(actor, "health", 100))
		var after := maxi(1, health + int(outcome.health))
		result.add_state_change({"entity_id": actor, "key": "health", "to": after})
		body += "\n健康%d→%d；休养仍需食物。" % [health, after]
	result.add_fact({"fact_id": fact_id, "fact_type": "journey_choice", "event_id": event.id, "choice_id": choice.id,
		"actor_id": actor, "location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
		"closed": not outcome.get("keep_open", false), "passed": won, "roll": roll, "summary": body})
	if choice.has("give"):
		result.facts_added.back()["contributor_id"] = actor
		result.facts_added.back()["recipient_id"] = host
	for mark: String in outcome.get("marks", []):
		result.add_fact({"fact_id": fact_id + ".learned." + mark, "fact_type": "journey_learned", "actor_id": actor,
			"target_id": mark, "source_fact_ids": [fact_id], "day": session.current_day, "hour": session.current_hour, "summary": outcome.text})
	result.mark_resolved("journey_choice")
	if not session.writer.apply_result(result, session.stores):
		session.challenge_rng.state = rng_before
		return {"success": false, "error": result.error_reason}
	var response: Dictionary = {"success": true, "hours": 0}
	if int(choice.hours) > 0:
		response = session.advance_time(int(choice.hours), "journey_choice")
	response["hours"] = int(session.elapsed_hours_since_start) - tick
	response["player_life_feedback"] = {"title": event.title, "body": body, "details": [], "summary_details": []}
	return response


static func transfer(session: Variant, result: Variant, from: String, to: String, definition: String, quantity: int, fact_id: String, tick: int) -> void:
	var remaining := quantity
	for item: Dictionary in transferable_items(session, from, definition):
		var amount := mini(remaining, int(item.quantity))
		if amount <= 0:
			break
		Market.new()._add_stack_transfer(result, item, amount, to, "journey_" + str(result.item_changes.size()), fact_id, fact_id, tick)
		result.item_changes.back()["expected_holder"] = item.holder
		Sources.append_to(result.item_changes.back().source_fact_ids, item)
		remaining -= amount


static func journal(session: Variant) -> Array:
	if not enabled(session):
		return []
	var entries: Array = []
	for fact: Dictionary in session.stores.fact_store.list_facts():
		if fact.get("fact_type") == "journey_choice" and fact.get("actor_id") == str(session.context.actor_id):
			entries.append({"day": fact.day, "hour": fact.hour, "text": fact.summary, "event_id": fact.event_id})
	return entries
