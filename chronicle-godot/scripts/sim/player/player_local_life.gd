extends RefCounted

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Market = preload("res://scripts/sim/economy/market_service.gd")
const Sources = preload("res://scripts/sim/item/item_causal_sources.gd")
const Danger = preload("res://scripts/sim/combat/world_danger_system.gd")
const INFO_HOURS := 12


static func enabled(session: Variant) -> bool:
	return session.fixture_source_data.get("player_life", {}).get("version", 0) == 2


static func handles(id: String) -> bool:
	return id in ["rest_block", "journey_block"] or id.begins_with("ask_local:") or id.begins_with("sell_food:") or id.begins_with("give_food:")


static func action_group(id: String) -> String:
	if id.begins_with("inquire:") or id.begins_with("ask_local:"):
		return "talk"
	if id.begins_with("buy:") or id.begins_with("sell_food:") or id.begins_with("give_food:"):
		return "trade"
	if id.begins_with("gather:") or id.begins_with("help:") or id.begins_with("work:") or id.begins_with("repair:"):
		return "work"
	return "rest"


static func present(view: Variant, player: Dictionary) -> Array:
	return view.get_entities_by_type("person").filter(func(person: Dictionary) -> bool:
		return person.id != player.id and "generated_resident" in person.get("tags", []) \
			and person.states.get("location_id") == player.states.location_id \
			and person.states.get("daily_route_id", "") == "" and person.states.get("danger_opponent_id", "") == "" \
			and person.states.get("alive", true) and person.states.get("life_status", "alive") == "alive")


static func wants_food(view: Variant, person: Dictionary) -> bool:
	if person.states.get("hunger", "none") not in ["medium", "high", "extreme"] \
			or Food.food_quantity(view.get_items_for_holder(str(person.id)), str(person.id)) > 0:
		return false
	var depot := Storage.stock_holder(view, str(person.id))
	return depot == "" or view.get_entity_state(depot, "location_id", "") != person.states.location_id \
		or Food.food_quantity(view.get_items_for_holder(depot), depot) == 0


static func options(session: Variant, view: Variant, player: Dictionary) -> Array:
	if not enabled(session):
		return []
	var rows: Array = []
	var remaining := int(player.states.get("daily_travel_remaining", 0))
	if remaining > 0:
		if remaining > 1:
			rows.append(session.PlayerLife.row("journey_block", "走完这段路", "逐小时赶路，抵达即停；路上仍会变饿，不跳过世界结算。", "", remaining))
		return rows
	if not session.get_combat_encounter_options().is_empty():
		return []
	var rest_hours := mini(6, posmod(6 - int(session.current_hour), 24))
	if (session.current_hour >= 18 or session.current_hour < 6) and rest_hours > 1 and player.states.get("hunger") not in ["high", "extreme"]:
		rows.append(session.PlayerLife.row("rest_block", "歇一阵，等天亮", "最多休息%d小时；饥饿达到严重、遇险或天亮即停。世界逐小时变化，伤后恢复照常耗粮。" % rest_hours, "", rest_hours))
	var food_config: Dictionary = session.fixture_source_data.resident_daily_life.food_access
	for person: Dictionary in present(view, player):
		if wants_food(view, person):
			for item: Dictionary in view.get_items_for_holder(str(player.id)):
				if not Food.is_food(item):
					continue
				var gift: Dictionary = session.PlayerLife.row("give_food:%s:%s" % [person.id, item.item_instance_id],
					"分1份%s给%s" % [item.display_name, person.display_name],
					"对方缺少口粮；当面交出自己的1份食物，不收钱、不保证回报。" + ("这是你最后一份口粮。" if int(view.player.food_count) == 1 else ""))
				gift.merge({"recipient_id": person.id, "item_id": item.item_instance_id, "quantity": 1})
				rows.append(gift)
			if person.states.get("hunger") in ["high", "extreme"] and int(person.states.get("age_years", 0)) >= 18:
				for offer: Dictionary in Food.new()._seller_offers(view, player, str(person.id), str(player.id),
						str(player.states.location_id), food_config, session.stores, {}, false, view.world_time):
					var affordable := int(Food.balance(view.get_items_for_holder(str(person.id)), str(person.id)) / int(offer.unit_price))
					var quantity := mini(2, mini(int(offer.surplus), affordable))
					var sale: Dictionary = session.PlayerLife.row("sell_food:%s:%s" % [person.id, offer.item_instance_id],
						"售%s给%s" % [offer.display_name, person.display_name],
						"%d份换%d铜币，双方当面交货；为你保留至少%d份口粮。" % [quantity, quantity * int(offer.unit_price), food_config.seller_retained_portions] if quantity > 0 else "对方缺粮，但买不起这份食物。可以选择无偿分粮，或保留自己的口粮。",
						"对方买不起" if quantity == 0 else "")
					sale.merge({"recipient_id": person.id, "item_id": offer.item_instance_id, "quantity": quantity, "offer": offer})
					rows.append(sale)
		if int(person.states.get("age_years", 0)) < 18:
			continue
		var info := local_statement(session, view, player, person)
		if not info_available(view, str(player.id), str(person.id), info, Danger.hour(view.world_time)):
			continue
		var ask: Dictionary = session.PlayerLife.row("ask_local:" + str(person.id), "问%s：这里怎么谋生？" % person.display_name,
			"问本人做什么、在哪儿开工和眼下能否买卖；消息会过时，不保证到场仍有货。")
		ask.merge({"speaker_id": person.id, "statement": info})
		rows.append(ask)
	return rows


static func local_statement(session: Variant, view: Variant, player: Dictionary, person: Dictionary) -> Dictionary:
	var workplaces: Array = []
	for profile: Dictionary in session.npc_livelihood_profiles:
		if profile.get("occupation_id") != person.states.get("occupation_id") or profile.get("workplace_id") != person.states.get("workplace_id"):
			continue
		workplaces.append({"location_id": profile.workplace_id, "label": profile.label, "hours": profile.work_interval_hours})
	var stock: Array = []
	for offer: Dictionary in session.PlayerLife.offers(view, player, session.fixture_source_data.resident_daily_life.food_access, session.stores, session.npc_livelihood_profiles):
		if offer.policy.seller_entity_id == person.id:
			stock.append({"item_id": offer.item_instance_id, "name": offer.display_name, "quantity": offer.surplus, "price": offer.unit_price})
	return {"workplaces": workplaces, "stock": stock, "needs_food": wants_food(view, person), "location_id": person.states.location_id}


static func info_available(view: Variant, player: String, speaker: String, statement: Dictionary, now: int) -> bool:
	var facts: Array = view.get_facts_by_actor(player)
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if fact.get("fact_type") == "player_local_information" and fact.get("speaker_id") == speaker:
			return not same_information(fact.get("statement", {}), statement) or now - int(fact.observed_hour) >= INFO_HOURS
	return true


static func same_information(a: Variant, b: Variant) -> bool:
	# Native JSON restores numbers as floats; that is not a new quote.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))


static func statement_text(session: Variant, person: Dictionary, info: Dictionary) -> String:
	var lines: Array[String] = ["%s告诉你：" % person.display_name]
	for work: Dictionary in info.workplaces:
		lines.append("我平常在%s做%s，一轮要%d小时；有料有工具、身体撑得住才做得完。" % [
			session.context.locations.get(str(work.location_id), {}).get("display_name", "本地作业地"), work.label, work.hours])
	if info.workplaces.is_empty():
		lines.append("我眼下没有固定的生产作业可以介绍。白天去本地泊台或公用作业地，也可以自己采口粮。")
	if info.stock.is_empty():
		lines.append("我眼下没有能卖给你的余货。你可以另找在场的人；等在这里不保证有货。")
	else:
		for stock: Dictionary in info.stock:
			lines.append("我现在能卖%s，余量%d，每份%d铜币；不替你预留。" % [stock.name, stock.quantity, stock.price])
	if info.needs_food:
		lines.append("我现在也缺口粮；有钱才买得起，你不必替我承担。")
	return "\n".join(lines)


static func execute(session: Variant, selected: Dictionary) -> Dictionary:
	var id := str(selected.action_id)
	if id in ["rest_block", "journey_block"]:
		return advance_block(session, selected)
	var view: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var actor := str(session.context.actor_id)
	var fact_id := "fact.player_local.%d" % session.elapsed_hours_since_start
	var result := Result.new()
	var summary := ""
	if id.begins_with("ask_local:"):
		var person: Dictionary = view.get_entity(str(selected.speaker_id))
		summary = statement_text(session, person, selected.statement)
		result.add_fact({"fact_id": fact_id, "fact_type": "player_local_information", "actor_id": actor,
			"speaker_id": person.id, "location_id": session.context.location_id,
			"day": session.current_day, "hour": session.current_hour, "observed_hour": Danger.hour(view.world_time),
			"expires_hour": Danger.hour(view.world_time) + INFO_HOURS, "statement": selected.statement,
			"summary": summary, "source_kind": "first_hand_conversation"})
		result.mark_resolved("player_local_information")
	elif id.begins_with("sell_food:"):
		var offer: Dictionary = selected.offer
		var policy: Dictionary = offer.policy.duplicate(true)
		policy["fact_type"] = "player_food_sold"
		var name: String = view.get_entity(str(selected.recipient_id)).display_name
		summary = "你把%d份%s卖给%s，收到%d铜币。对方已经拿到食物，之后如何使用由其自行决定。" % [selected.quantity, offer.display_name, name, int(selected.quantity) * int(offer.unit_price)]
		var trade: Dictionary = Market.new().plan_trade(policy, {"buyer_entity_id": selected.recipient_id,
			"item_instance_id": selected.item_id, "quantity": selected.quantity, "quoted_unit_price": offer.unit_price,
			"exchange_id": "exchange.player_sale.%d" % session.elapsed_hours_since_start, "summary": summary,
			"trace_goods_sources": true}, session.stores, session.get_time_summary())
		if not trade.get("success", false):
			return trade
		result = trade.transaction
		result.facts_added[0]["contributor_id"] = actor
		result.facts_added[0]["hour"] = session.current_hour
	else:
		var item: Dictionary = session.stores.item_store.get_item(str(selected.item_id))
		var sources: Array = []
		Sources.append_to(sources, item)
		summary = "你把1份%s交给%s，自己少了一份口粮，没有收钱。食物已在对方手中，不保证换来回报。" % [item.display_name, view.get_entity(str(selected.recipient_id)).display_name]
		result.add_fact({"fact_id": fact_id, "fact_type": "player_food_given", "actor_id": actor,
			"target_id": selected.recipient_id, "contributor_id": actor, "location_id": session.context.location_id,
			"day": session.current_day, "hour": session.current_hour, "source_fact_ids": sources,
			"item_instance_id": item.item_instance_id, "quantity": 1, "summary": summary})
		Market.new()._add_stack_transfer(result, item, 1, str(selected.recipient_id), "food", fact_id, fact_id, session.elapsed_hours_since_start)
		result.item_changes.back()["expected_holder"] = {"kind": "entity", "id": actor}
		result.mark_resolved("player_food_given")
	if not session.writer.apply_result(result, session.stores):
		return {"success": false, "error": result.error_reason}
	return session.PlayerLife.feedback(session.advance_time(1, "player_local_exchange"), summary)


static func advance_block(session: Variant, selected: Dictionary) -> Dictionary:
	var before: Variant = session.get_snapshot()
	var count := 0
	var stop := "预定时间已到"
	for index: int in range(int(selected.hours)):
		var step: Dictionary = session.recover_from_danger() if selected.action_id == "rest_block" else session.advance_time(1, "player_journey")
		if not step.get("success", false):
			return step
		count += 1
		var current: Variant = session.get_snapshot()
		if not session.get_combat_encounter_options(current).is_empty():
			stop = "遇到了危险，需要你作决定"
			break
		if selected.action_id == "journey_block" and int(current.player.daily_travel_remaining) == 0:
			stop = "已抵达" + str(session.context.location.get("display_name", "目的地"))
			break
		if selected.action_id == "rest_block" and current.player.hunger in ["high", "extreme"]:
			stop = "已经很饿，需要先考虑食物"
			break
	var after: Variant = session.get_snapshot()
	return session.PlayerLife.feedback({"success": true, "hours": count}, "%d小时过去，%s。疲劳%d→%d，健康%d→%d，食物%d→%d。" % [
		count, stop, before.player.fatigue, after.player.fatigue, before.player.health, after.player.health, before.player.food_count, after.player.food_count])


static func known_information(session: Variant) -> Array:
	var rows: Array = []
	if not enabled(session):
		return rows
	var now := Danger.hour(session.get_time_summary())
	var seen := {}
	var facts: Array = session.stores.fact_store.list_facts()
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if fact.get("fact_type") != "player_local_information" or fact.get("actor_id") != str(session.context.actor_id) or seen.has(fact.speaker_id):
			continue
		seen[fact.speaker_id] = true
		rows.append({"fact_id": fact.fact_id, "speaker_id": fact.speaker_id, "age_hours": now - int(fact.observed_hour),
			"expired": now >= int(fact.expires_hour), "statement": fact.statement,
			"text": "%s（%d小时前；%s）\n%s" % [session.stores.entity_store.get_entity(str(fact.speaker_id)).get("display_name", "熟人"),
				now - int(fact.observed_hour), "已过时，只作线索" if now >= int(fact.expires_hour) else "到场须重新确认", fact.summary]})
	return rows


static func destination_guide(session: Variant, location: String) -> String:
	if not enabled(session):
		return ""
	var place: Dictionary = session.context.locations.get(location, {})
	var home: String = session.stores.state_store.get_state(str(session.context.actor_id), "settlement_id", "")
	var profiles: Array = session.npc_livelihood_profiles.filter(func(profile: Dictionary) -> bool: return profile.get("workplace_id") == location)
	var settlement: String = str(profiles[0].settlement_id) if not profiles.is_empty() else str(place.get("generation_source", {}).get("settlement_id", ""))
	if settlement != home:
		return "邻地，需到场打听生计与供给"
	if profiles.any(func(profile: Dictionary) -> bool: return profile.get("work_output_food", false)):
		return "白天可采口粮；短工须雇主在场有钱"
	if profiles.any(func(profile: Dictionary) -> bool: return profile.has("work_recipe") and not profile.get("products", []).is_empty()):
		return "工具作坊；购买看现货，作业需材料"
	return "道路与居民往来处；不是固定商店"


static func aftermath_text(session: Variant, person: Dictionary, fact: Dictionary, contribution: String, heard: bool = true) -> String:
	var origin: Dictionary = session.stores.fact_store.get_fact(contribution)
	var context := "你先前补充的食物"
	if origin.get("fact_type") == "world_danger_round":
		context = "你参与交锋后，威胁暂时退开；这次作业发生在退避期间"
	elif origin.get("fact_type") == "player_food_sold":
		context = "你先前出售的那批食物"
	elif origin.get("fact_type") == "player_food_given":
		context = "你先前分出的那份食物"
	return "%s%s（%s）：第%d天 %02d:00，%s" % [person.display_name,
		"谈起后来的情况" if heard else "在你面前完成了作业", context, fact.day, fact.get("hour", 0), fact.summary]


static func aftermath_brief(person: Dictionary, fact: Dictionary) -> String:
	if fact.has("danger_clearance_source_id"):
		return "第%d天，%s在危险退避期间完成了作业。你参与过交锋，完整经过见记录。" % [fact.day, person.display_name]
	var action: String = {"npc_self_meal": "吃下了一份留存食物", "npc_household_shared_food": "给家人分了一份食物",
		"household_pantry_stored": "把食物存进了粮柜", "household_food_delivered": "把食物带给了家人"}.get(str(fact.fact_type), "用到了留存食物")
	return "第%d天，%s%s。这批库存有你的补充。" % [fact.day, person.display_name, action]
