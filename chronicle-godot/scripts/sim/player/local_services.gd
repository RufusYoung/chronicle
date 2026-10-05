extends RefCounted

const Journey = preload("res://scripts/sim/player/journey_events.gd")
const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")
const Utility = preload("res://scripts/sim/player/journey_utility.gd")
const Brief = preload("res://scripts/sim/player/brief_actions.gd")


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
	if Utility.enabled(session.fixture_source_data):
		rows = _bed_options(session, host)
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
	if Utility.enabled(session.fixture_source_data):
		return _bed(session, rows[0])
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


static func _bed_options(session: Variant, host: String) -> Array:
	var rows: Array = []
	var snapshot: Variant = session.get_snapshot()
	var money := Treasury.new(snapshot).balance(str(session.context.actor_id))
	var fatigue := int(snapshot.player.fatigue)
	var minute := int(session.get_time_summary().get("minute", 0))
	var until_close := posmod(9 - int(session.current_hour), 24) * 60 - minute
	for hours: int in Utility.PROFILE.bed_durations:
		var price := hours * int(Utility.PROFILE.bed_hourly_price)
		var reason := ""
		if not Journey.host_present(session, host):
			reason = "主人不在场；尚未付费，不能借宿"
		elif not Journey.within_hours(int(session.current_hour), [17, 9]):
			reason = "17时至次日9时接待住宿；可以原地等候"
		elif hours * 60 > until_close:
			reason = "9时房间要用于家事，剩余时间不足；可选更短住宿或免费休息"
		elif money < price:
			reason = "随身铜币不足%d枚；仍可免费休息" % price
		rows.append({"action_id": "service:bed:%d" % hours, "event_type": "player_life", "action_type": "life", "life_group": "rest",
			"label": "借床歇%d小时" % hours, "hours": hours, "price": price,
			"cost": "%d小时 / 最多%d铜币" % [hours, price],
			"known_effect": "疲劳%d→%d；同样时间免费休息降至%d。只为已用小时付费，每小时1铜币。" % [fatigue, maxi(0, fatigue - hours * 2), maxi(0, fatigue - hours)],
			"hint": "疲劳%d→%d；同样时间免费休息降至%d。不送食物，遇险或严重饥饿提前结束，未用小时不收费。" % [fatigue, maxi(0, fatigue - hours * 2), maxi(0, fatigue - hours)],
			"tradeoff": "省下的体力可用于加快脚程；花钱不保证赶得上远处的人。",
			"can_execute": reason == "", "blocked_reason": reason})
	return rows


static func _bed(session: Variant, selected: Dictionary) -> Dictionary:
	var actor := str(session.context.actor_id)
	var host := str(session.context.location.journey_host_id)
	var before: Variant = session.get_snapshot()
	var elapsed := 0
	var stop := "预定休整已结束"
	var price := int(Utility.PROFILE.bed_hourly_price)
	for index: int in range(int(selected.hours)):
		var fact_id := "fact.guesthouse." + Brief.stamp(session)
		var payment := Result.new()
		payment.add_fact({"fact_id": fact_id, "fact_type": "guesthouse_paid", "actor_id": actor, "target_id": host,
			"location_id": session.context.location_id, "day": session.current_day, "hour": session.current_hour,
			"amount": price, "reserved_hours": int(selected.hours), "used_hour": index + 1,
			"summary": "你为本小时床位支付%d铜币，主人仍按自己的打算生活。" % price})
		if not Treasury.new(session.get_snapshot()).append_payment(payment, actor, host, price, fact_id, int(session.elapsed_hours_since_start)):
			stop = "余钱不足，未再支付下一小时"
			break
		payment.mark_resolved("guesthouse_paid")
		if not session.writer.apply_result(payment, session.stores):
			return {"success": false, "error": payment.error_reason, "hours": elapsed}
		var recovered: Dictionary = session.recover_from_danger()
		if not recovered.get("success", false):
			return recovered
		elapsed += 1
		var comfort := Result.new()
		comfort.add_state_change({"entity_id": actor, "key": "fatigue", "to": maxi(0, int(session.stores.state_store.get_state(actor, "fatigue", 0)) - 1)})
		comfort.mark_resolved("guesthouse_comfort")
		if not session.writer.apply_result(comfort, session.stores):
			return {"success": false, "error": comfort.error_reason, "hours": elapsed}
		var after: Variant = session.get_snapshot()
		if not session.get_combat_encounter_options().is_empty():
			stop = "出现危险，先处理现场"
			break
		if after.player.hunger in ["high", "extreme"]:
			stop = "已经很饿，先考虑食物"
			break
		if int(after.player.health) < int(before.player.health):
			stop = "身体状况下降，先停下来"
			break
	return {"success": elapsed > 0, "hours": elapsed, "player_life_feedback": {"title": "借床休整之后",
		"body": "%s。住了%d小时，支付%d铜币；疲劳%d→%d。人和货物仍在随时间变化。" % [stop, elapsed, elapsed * price, before.player.fatigue, session.get_snapshot().player.fatigue],
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
