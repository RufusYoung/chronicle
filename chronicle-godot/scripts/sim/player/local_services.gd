extends RefCounted

const Journey = preload("res://scripts/sim/player/journey_events.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")


static func options(session: Variant) -> Array:
	if not Journey.enabled(session):
		return []
	var place: Dictionary = session.context.location
	var host := str(place.get("journey_host_id", ""))
	if host == "":
		return []
	var reason := ""
	if not Journey.host_present(session, host):
		reason = "主人不在场；尚未付费，不能借宿"
	elif not Journey.within_hours(int(session.current_hour), [17, 9]):
		reason = "白天房间用于家事；17时至次日9时接待住宿"
	elif Treasury.new(session.get_snapshot()).balance(str(session.context.actor_id)) < 3:
		reason = "住宿需3枚铜币"
	var rows: Array = [{"action_id": "service:bed", "event_type": "player_life", "label": "付3铜币，住下歇四小时",
		"hours": 4, "cost": "4小时 / 3铜币", "known_effect": "床铺每小时额外减1疲劳；不附送食物，伤后恢复仍按身体规则。",
		"hint": "主人当面收款，钱进入其实际库存。你也可以免费在外休息。", "tradeoff": "世界继续运转；夜里也可探路或与在场者交谈。",
		"can_execute": reason == "", "blocked_reason": reason, "action_type": "life", "life_group": "rest"}]
	var drink_reason := ""
	if not Journey.host_present(session, host):
		drink_reason = "主人不在场"
	elif not Journey.within_hours(int(session.current_hour), [17, 24]):
		drink_reason = "小酒馆17时开火，午夜后只接待住宿"
	elif Journey.available(session, host, "item.hearth_malt_drink") < 1:
		drink_reason = "这家的麦饮已卖完；不会凭空补货"
	elif Treasury.new(session.get_snapshot()).balance(str(session.context.actor_id)) < 2:
		drink_reason = "一碗麦饮需2枚铜币"
	rows.append({"action_id": "service:drink", "event_type": "player_life", "label": "花2铜币，坐下喝碗麦饮",
		"hours": 1, "cost": "1小时 / 2铜币", "known_effect": "消耗主人一份麦饮，疲劳降低1；不是一餐，不能代替口粮。",
		"hint": "每日第一次同席增加1点信任；反复点单不再增加。", "tradeoff": "铜币交给主人，麦饮库存有限。",
		"can_execute": drink_reason == "", "blocked_reason": drink_reason, "action_type": "life", "life_group": "talk"})
	return rows


static func execute(session: Variant, id: String) -> Dictionary:
	var rows := options(session).filter(func(row: Dictionary) -> bool: return row.action_id == id)
	if rows.is_empty() or not rows[0].can_execute:
		return {"success": false, "error": "guesthouse_unavailable"}
	if id == "service:drink":
		return _drink(session)
	var actor := str(session.context.actor_id)
	var host := str(session.context.location.journey_host_id)
	var before := int(session.stores.state_store.get_state(actor, "fatigue", 0))
	var fact_id := "fact.guesthouse.%d" % session.elapsed_hours_since_start
	var result := Result.new()
	result.add_fact({"fact_id": fact_id, "fact_type": "guesthouse_paid", "actor_id": actor, "target_id": host,
		"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
		"amount": 3, "summary": "你当面支付3枚铜币，借用客舍床铺四小时。"})
	if not Treasury.new(session.get_snapshot()).append_payment(result, actor, host, 3, fact_id, int(session.elapsed_hours_since_start)):
		return {"success": false, "error": "guesthouse_payment_failed"}
	result.mark_resolved("guesthouse_paid")
	if not session.writer.apply_result(result, session.stores):
		return {"success": false, "error": result.error_reason}
	var elapsed := 0
	for index: int in range(4):
		var recovered: Dictionary = session.recover_from_danger()
		if not recovered.get("success", false):
			return recovered
		elapsed += 1
		var comfort := Result.new()
		comfort.add_state_change({"entity_id": actor, "key": "fatigue", "to": maxi(0, int(session.stores.state_store.get_state(actor, "fatigue", 0)) - 1)})
		comfort.mark_resolved("guesthouse_comfort")
		if not session.writer.apply_result(comfort, session.stores):
			return {"success": false, "error": comfort.error_reason}
	return {"success": true, "hours": elapsed, "player_life_feedback": {"title": "客舍的一觉",
		"body": "你在床铺上歇了%d小时。疲劳%d→%d，3枚铜币已经交给主人。窗外的人与事没有等你。" % [elapsed, before, session.stores.state_store.get_state(actor, "fatigue", 0)],
		"details": [], "summary_details": []}}


static func _drink(session: Variant) -> Dictionary:
	var actor := str(session.context.actor_id)
	var host := str(session.context.location.journey_host_id)
	var started_at := int(session.elapsed_hours_since_start)
	var fact_id := "fact.tavern.%d" % started_at
	var item: Dictionary = Journey.transferable_items(session, host, "item.hearth_malt_drink")[0]
	var first: bool = not session.stores.fact_store.list_facts().any(func(fact: Dictionary) -> bool:
		return fact.get("fact_type") == "tavern_drink" and fact.get("actor_id") == actor and fact.get("target_id") == host and int(fact.get("day", -1)) == int(session.current_day))
	var result := Result.new()
	result.add_fact({"fact_id": fact_id, "fact_type": "tavern_drink", "actor_id": actor, "target_id": host,
		"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
		"amount": 2, "item_instance_id": item.item_instance_id, "summary": "你在灶火边喝下一碗麦饮；主人收下2枚铜币，余量少了一份。"})
	result.add_item_change({"operation": "consume", "item_instance_id": item.item_instance_id, "quantity": 1,
		"expected_holder": item.holder, "beneficiary_id": actor, "provider_id": host, "source_fact_ids": [fact_id]})
	if not Treasury.new(session.get_snapshot()).append_payment(result, actor, host, 2, fact_id, int(session.elapsed_hours_since_start)):
		return {"success": false, "error": "tavern_payment_failed"}
	result.add_state_change({"entity_id": actor, "key": "fatigue", "to": maxi(0, int(session.stores.state_store.get_state(actor, "fatigue", 0)) - 1)})
	if first:
		result.add_relationship_change({"source_id": host, "target_id": actor, "axis": "trust", "delta": 1})
	result.mark_resolved("tavern_drink")
	if not session.writer.apply_result(result, session.stores):
		return {"success": false, "error": result.error_reason}
	var response: Dictionary = session.advance_time(1, "tavern_drink")
	response["hours"] = int(session.elapsed_hours_since_start) - started_at
	response["player_life_feedback"] = {"title": "灶火边的一碗麦饮", "body": "你慢慢喝完，把空碗推回柜边。花费2铜币，麦饮消耗1份，疲劳降低1。" + ("主人记住了这次同席，信任增加1。" if first else "今天已经聊过，这次没有额外增加信任。"), "details": [], "summary_details": []}
	return response
