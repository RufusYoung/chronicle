extends RefCounted
## Legal intents change native truth; there is no success/failure story table.

const Intents = preload("res://scripts/sim/situation/equipment_intents.gd")
const Brief = preload("res://scripts/sim/player/brief_actions.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")


static func row(intent: String, subject: String, label: String, hint: String, object: String = "") -> Dictionary:
	return {"action_id": "situation:%s:%s:%s" % [intent, subject, object], "intent": intent, "subject_id": subject,
		"event_type": "player_life", "action_type": "situation", "label": label, "hint": hint, "known_effect": hint,
		"hours": 0, "minutes": 10, "cost": "10分钟", "can_execute": true, "blocked_reason": "", "life_group": "situation",
		"requires_confirmation": intent in ["give", "fund", "repair", "sell"]}


static func options(session: Variant) -> Array:
	var rows: Array = []
	for situation: Dictionary in session.Situations.build(session):
		rows.append_array(situation.affordances)
	var player: Dictionary = session.get_snapshot().player
	if player.get("daily_route_id", "") != "" or not session.get_combat_encounter_options().is_empty():
		return rows
	for notice: Dictionary in session.Situations.notices(session):
		if notice.departure_to == "" or notice.witness_id != session.context.actor_id or int(notice.created_hour) != Intents.now(session.get_time_summary()):
			continue
		for route: Dictionary in session.get_travel_options():
			if route.get("to_location_id") != notice.departure_to or not route.get("can_travel", false):
				continue
			var person: Dictionary = session.stores.entity_store.get_entity(str(notice.actor_id))
			var follow := row("follow", str(notice.actor_id), "跟上刚出发的%s" % person.get("display_name", "那个人"),
				"走同一条真实道路；各自承担时间与危险，不保证对方等待，也没有护送报酬。", str(route.route_id))
			follow.merge({"route_id": route.route_id, "cost": route.get("cost", "沿路行进"), "hours": route.get("hours", 1), "minutes": int(route.get("hours", 1)) * 60}, true)
			rows.append(follow)
	for minutes: int in [10, 60]:
		var wait := row("wait", str(minutes), "在这里等%s" % ("十分钟" if minutes == 10 else "一小时"), "不移动；有人到来、局面改变或危险出现时停下，让你重新决定。")
		wait.merge({"minutes": minutes, "cost": "%d分钟" % minutes, "life_group": "rest"}, true)
		rows.append(wait)
	var clock: Dictionary = session.get_time_summary()
	var current := int(clock.hour) * 60 + int(clock.get("minute", 0))
	var target := 17 * 60 if current < 17 * 60 else 24 * 60 + 6 * 60
	var timed := row("wait", str(target - current), "原地等到%s" % ("17:00" if current < 17 * 60 else "明早06:00"), "这是等待上限，不保证主人回来或有货；可见变化会提前打断。")
	if target - current not in [10, 60]:
		timed.merge({"minutes": target - current, "cost": "至多%d分钟" % (target - current), "life_group": "rest"}, true)
		rows.append(timed)
	return rows


static func execute(session: Variant, selected: Dictionary) -> Dictionary:
	if selected.intent == "wait":
		return wait_here(session, int(selected.minutes))
	if selected.intent == "repair":
		return session.PlayerLife.work(session, str(selected.action_id), selected)
	if selected.intent == "follow":
		return session.PlayerLife.feedback(session.travel(str(selected.route_id)), "你沿刚看见的出发方向跟了上去。对方仍按自己的计划行动，没有保证会等你。")
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var actor := str(session.context.actor_id)
	var person: Dictionary = snapshot.get_entity(str(selected.subject_id))
	if not Intents.present(person, str(session.context.location_id)):
		return {"success": false, "error": "person_no_longer_here"}
	var tick: Dictionary = session.get_time_summary()
	var id := "fact.situation." + Brief.stamp(session)
	var result := Result.new()
	var fact := {"fact_id": id, "fact_type": "situation_" + str(selected.intent), "actor_id": actor,
		"subject_id": person.id, "target_id": person.id, "location_id": session.context.location_id,
		"day": tick.day, "hour": tick.hour, "absolute_hour": Intents.now(tick), "source_fact_ids": selected.get("sources", [])}
	match selected.intent:
		"ask":
			fact.fact_type = "situation_inquiry"
			var declaration := Intents.declaration(snapshot, person, tick, session.context.locations, true)
			if not declaration.is_empty():
				for key: String in ["query", "goal", "danger_location_id", "source_fact_ids"]:
					fact[key] = declaration[key]
				fact["statement"] = declaration.summary
			else:
				var goal := str(person.states.get("daily_goal_id", ""))
				var place := str(session.context.locations.get(goal, {}).get("display_name", ""))
				var activity := str(person.states.get("daily_activity_reason", ""))
				fact["goal"] = activity if activity != "" else "暂时留在这里"
				fact["statement"] = "%s说：%s%s。" % [person.display_name, fact.goal, "，眼下打算去" + place if place != "" and goal != session.context.location_id else ""]
				var source := str(person.states.get("daily_departure_fact_id", ""))
				if source != "":
					fact.source_fact_ids.append(source)
			fact.summary = fact.statement
			result.add_fact(fact)
		"give":
			var item: Dictionary = snapshot.get_item(str(selected.item_id))
			result = Intents.gift(snapshot, actor, str(person.id), item, id, tick, selected.get("sources", []))
			fact = result.facts_added[0]
		"sell":
			var trade: Dictionary = Intents.Market.new().plan_trade(selected.policy, {"buyer_entity_id": person.id,
				"item_instance_id": selected.item_id, "quantity": 1, "quoted_unit_price": selected.price,
				"exchange_id": "exchange.situation." + Brief.stamp(session), "source_fact_ids": selected.sources,
				"trace_goods_sources": true, "trace_payment_sources": true,
				"summary": "你把%s卖给%s，收到%d枚实际铜币。" % [snapshot.get_item(selected.item_id).display_name, person.display_name, selected.price]}, session.stores, tick)
			if not trade.get("success", false):
				return trade
			result = trade.transaction
			fact = result.facts_added[0]
			Intents.append_trace(result, fact, fact.summary)
		"fund":
			if not Treasury.new(snapshot).append_payment(result, actor, str(person.id), int(selected.amount), id, Intents.now(tick)):
				return {"success": false, "error": "payment_unavailable"}
			fact["amount"] = selected.amount
			fact.summary = "你把%d枚铜币交给%s。这不是欠款；如何使用由对方接下来决定。" % [selected.amount, person.display_name]
			result.add_fact(fact)
			Intents.append_trace(result, fact, fact.summary)
			result.add_relationship_change({"source_id": person.id, "target_id": actor, "axis": "trust", "delta": 1})
			result.add_memory({"memory_id": "memory." + id, "owner_id": person.id, "memory_type": "equipment_help", "source_fact_id": id, "summary": fact.summary})
		"caution":
			fact.fact_type = "situation_advice"
			fact.summary = "你劝%s先避开先前遇险的地方。对方听见了，但没有答应按你的意思行动。" % person.display_name
			result.add_fact(fact)
		_:
			return {"success": false, "error": "unknown_situation_intent"}
	Brief.append(result, session)
	result.mark_resolved("situation_action")
	if not session.writer.apply_result(result, session.stores):
		return {"success": false, "error": "situation_write_rejected:" + str(session.writer.last_report)}
	return session.PlayerLife.feedback(Brief.advance(session, "situation_action"), str(fact.summary))


static func repair_options(session: Variant, snapshot: Variant, person: Dictionary) -> Array:
	var rows: Array = []
	var actor := str(session.context.actor_id)
	if not session.PlayerLife.work_denial(session, snapshot.get_entity(actor)).is_empty():
		return rows
	# Only visibly worn equipment is offered. Inventory contents remain private.
	for id: Variant in snapshot.get_equipment_loadout(str(person.id)).get("slots", {}).values():
		var item: Dictionary = snapshot.get_item(str(id))
		for profile: Dictionary in session.fixture_source_data.resident_daily_life.get("maintenance_profiles", []):
			if profile.workplace_id != session.context.location_id or not Intents.Recipe.repairable(item, profile.work_recipe.repairs[0], snapshot):
				continue
			var recipe: Variant = Intents.Recipe.new(snapshot, session.registry)
			var materials: Dictionary = recipe.plan_inputs(profile, actor, "preview", 0, str(id))
			var stocks := {}
			for input: Dictionary in profile.get("resource_inputs", []):
				stocks[input.stock_id] = snapshot.get_resource_stock(input.stock_id).get("current", 0)
			var resources: Dictionary = session.PlayerLife.Livelihood.new()._resource_plan(profile, stocks, snapshot, actor)
			if not materials.ok or not resources.ok:
				continue
			var repair := row("repair", str(person.id), "替%s修补%s" % [person.display_name, item.display_name],
				"使用自己的材料和现场资源；对方离开或危险发生时中断，已经用掉的时间不退回。" + Intents.Recipe.input_summary(profile, session.registry), str(id))
			var own := profile.duplicate(true)
			own["actor_tags_all"] = ["player_controlled"]
			repair.merge({"profile": own, "item_id": id, "hours": profile.work_interval_hours,
				"minutes": int(profile.work_interval_hours) * 60, "cost": "%d小时" % profile.work_interval_hours}, true)
			rows.append(repair)
	return rows


static func repair_still_present(snapshot: Variant, actor: String, service: Dictionary) -> bool:
	var person: Dictionary = snapshot.get_entity(service.subject_id)
	return Intents.present(person, str(snapshot.get_entity_state(actor, "location_id", ""))) \
		and person.states.get("danger_opponent_id", "") == "" \
		and snapshot.get_item(service.item_id).get("holder", {}).get("id") == service.subject_id


static func sale_options(session: Variant, snapshot: Variant, person: Dictionary, item: Dictionary, sources: Array) -> Array:
	var actor := str(session.context.actor_id)
	var policy := {"market_policy_id": "situation." + actor, "seller_entity_id": actor, "stock_entity_id": actor,
		"location_id": session.context.location_id, "sellable_item_tags_any": [],
		"accepted_currency_item_def_ids": [Intents.Food.CURRENCY], "fact_type": "equipment_purchased", "exchange_type": "equipment_purchase"}
	for offer: Dictionary in Intents.Market.new().build_stock_view(policy, session.stores, str(person.id)).get("offers", []):
		if offer.item_instance_id != item.item_instance_id or int(offer.unit_price) > Intents.Food.balance(snapshot.get_items_for_holder(str(person.id)), str(person.id)):
			continue
		var sale := row("sell", str(person.id), "以%d铜币向%s出售%s" % [offer.unit_price, person.display_name, item.display_name],
			"对方正需要这类装备且能付这笔价钱；钱物当面交割。", str(item.item_instance_id))
		sale.merge({"policy": policy, "item_id": item.item_instance_id, "price": offer.unit_price, "sources": sources})
		return [sale]
	return []


static func visible_signature(session: Variant) -> String:
	var rows: Array = []
	for situation: Dictionary in session.Situations.build(session):
		rows.append([situation.subject_id, situation.body, situation.get("related_items", [])])
	for service: Dictionary in session.PlayerLife.Services.options(session):
		if service.get("can_execute", true):
			rows.append([service.get("action_id", "")])
	return JSON.stringify(rows)


static func wait_here(session: Variant, minutes: int) -> Dictionary:
	var before := visible_signature(session)
	var passed := 0
	var reason := "到了预定的时间，眼前暂时没有新的动静"
	var start_notices: Array = session.Situations.notices(session)
	var start_player: Dictionary = session.get_snapshot().player
	while passed < minutes:
		var step := mini(10, minutes - passed)
		var result := Result.new()
		Brief.append(result, session, step)
		result.mark_resolved("situation_wait")
		if not session.writer.apply_result(result, session.stores):
			return {"success": false, "error": "wait_clock_rejected"}
		var advanced := Brief.advance(session, "player_waiting", step)
		if not advanced.get("success", false):
			return advanced
		passed += step
		var player: Dictionary = session.get_snapshot().player
		if int(player.get("health", 100)) < int(start_player.get("health", 100)) or (player.get("hunger") == "extreme" and start_player.get("hunger") != "extreme"):
			reason = "身体状况已经吃紧，先停下来决定是否进食或休养"
			break
		if not session.get_combat_encounter_options().is_empty():
			reason = "危险来到近前，等待中断"
			break
		if visible_signature(session) != before or session.Situations.notices(session) != start_notices:
			reason = "眼前的人或消息发生变化，先停下来看看"
			break
	return session.PlayerLife.feedback({"success": true, "minutes": passed, "wait_interrupted": passed < minutes},
		"你在原地等了%d分钟。%s。" % [passed, reason])
