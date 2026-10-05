extends RefCounted
## Read-only overlaps. Selecting an information question is not evidence of an earlier travel plan.

const Equipment = preload("res://scripts/sim/player/player_equipment.gd")
const Treasury = preload("res://scripts/sim/economy/treasury_transfer_planner.gd")


static func apply(session: Variant, snapshot: Variant, view: Dictionary, result: Dictionary) -> void:
	var goal: Dictionary = result.selected
	var actor := str(session.context.actor_id)
	var stakes: Array = []
	var question: Dictionary = result.interest
	var route_overlap: bool = not question.is_empty() and question.get("relevance") == "danger" \
		and goal.get("intent_basis") == "destination" and goal.get("id") == question.id \
		and (not destination_reached(snapshot, goal) or question.get("question_status") == "resolved")
	var pending: bool = route_overlap and not destination_reached(snapshot, goal) and question.get("question_status") != "resolved"
	var local_danger: bool = route_overlap and view.get("risk", {}).get("encounter", false)
	if pending:
		for row: Dictionary in view.get("actions", []):
			if row.get("intent") == "wait" and row.get("minutes") == 10 and row.get("can_execute", false):
				result.alternatives.append({"id": row.action_id, "label": row.label, "enabled": true,
					"cost": row.cost, "cost_categories": ["time", "delay"], "role": "postpone_without_resolving"})
		for row: Dictionary in view.get("travel_options", []):
			if row.get("can_travel", false) and "visit:" + str(row.get("destination_id", "")) != goal.id:
				result.alternatives.append({"id": row.route_id, "label": row.get("destination_name", "改走别处"), "enabled": true,
					"cost": row.get("cost", ""), "cost_categories": ["time", "different_destination"], "role": "leave_original_plan"})
	var paths: Array = result.alternatives.filter(func(row: Dictionary) -> bool: return row.enabled)
	var path_ids: Array = paths.map(func(row: Dictionary) -> String: return str(row.id))
	var why := ""
	if route_overlap:
		var facts: Array = snapshot.get_facts_by_actor(actor)
		var testimony_index := -1
		for index: int in range(facts.size()):
			if facts[index].get("fact_id") == question.source:
				testimony_index = index
		var intention_first := goal.has("own_fact_cursor") and testimony_index >= int(goal.get("own_fact_cursor", 0))
		result["intention_before_testimony"] = intention_first
		why = ("你原本要去这里；" if intention_first else "你选定的目的地有一条已知消息：") \
			+ "%s%d小时前提过那里遇险，旧消息待核实。" % [snapshot.get_entity(str(question.subject)).get("display_name", "见证人"), question.age]
		if destination_reached(snapshot, goal):
			why = "这是你选定的目的地；这趟行程已有到场记录。"
		stakes.append(_stake(str(question.subject), "ROUTE_ACCESS", str(goal.id), str(question.source),
			"按自己的打算抵达；也可推迟或改道", "若危险仍在，进入后可能需要交锋或脱离；消息本身不代表道路封闭",
			"current" if pending or local_danger else "answered", str(question.uncertainty), path_ids, "selected_destination_and_learned_testimony"))
		if pending or local_danger:
			var outer: Dictionary = snapshot.get_equipped_item(actor, "body_outer")
			var protection := Equipment.describe(outer) if not outer.is_empty() else "没有穿外衣，外衣槽不提供防守加成"
			if outer.is_empty() and not _unreplaced_gift(snapshot.get_facts_by_actor(actor)).is_empty():
				protection = "外衣已赠出，原有防护不再生效"
			why += "\n自己的防护：" + protection + "。"
			stakes.append(_stake(actor, "SELF_SURVIVAL", str(outer.get("item_instance_id", "body_outer")), str(question.source),
				"装备加成按实际耐久和适用条件进入战斗检定", "若交锋失利，正式结算会影响身体、疲劳和装备耐久；不保证一定受伤",
				"current", "旧消息不能证明眼下仍有威胁", path_ids, "own_loadout_and_formal_combat_consumer"))
	var preparation: bool = (pending or local_danger or goal.get("id") == "replace_outerwear")
	if preparation:
		var loss: Dictionary = _unreplaced_gift(snapshot.get_facts_by_actor(actor))
		if not loss.is_empty() and snapshot.get_equipped_item(actor, "body_outer").is_empty():
			stakes.append(_stake(str(loss.target_id), "OWNERSHIP", str(loss.get("item_instance_id", "body_outer")), str(loss.fact_id),
				"重新取得并穿戴装备后才恢复相应加成", "已经交出的外衣不再为自己提供防护；赠出不等于建立深厚关系",
				"current", "对方后来的使用情况须当面获知", path_ids, "native_equipment_given_and_current_empty_slot"))
		var balance := Treasury.new(snapshot).balance(actor)
		for offer: Dictionary in result.alternatives:
			var price := int(offer.get("price", 0))
			if not str(offer.id).begins_with("buy:") or price <= 0:
				continue
			stakes.append(_stake(actor, "MONEY", "money.copper_coin", str(offer.id),
				"买入这件相关装备，仍需实际穿戴", "现有%d铜币；该项%d铜币%s" % [balance, price,
				"，买后余%d铜币" % (balance - price) if balance >= price else "，目前付不起"],
				"current", "只代表当前当面报价，不保证对方后来仍有货；未声明其他服务一定无法支付", path_ids,
				"native_treasury_and_current_equipment_offer"))
	for interest: Dictionary in result.interests:
		var matching: Array = stakes.filter(func(s: Dictionary) -> bool: return s.linked_fact == interest.source and interest.get("relevance") == "danger")
		interest["promoted"] = not matching.is_empty()
		interest["why_it_matters_to_you"] = why if interest.promoted else ""
		interest["personal_stakes"] = matching
	result["personal_stakes"] = stakes
	result["goal_status"] = "unselected" if goal.is_empty() else ("arrived" if destination_reached(snapshot, goal) else "active")
	result["why_it_matters_to_you"] = why
	result["stake_diagnostic"] = "NO_PERSONAL_STAKE" if stakes.is_empty() else "WEAK_STAKE"
	result["motivation_validation"] = "requires_play_evidence"
	# A bounded factual overlap never certifies desire, significance, or enjoyment.
	if why != "" and (pending or local_danger):
		result.pressure = why
	for row: Dictionary in view.get("actions", []):
		if row.get("intent") not in ["pursue", "aftermath", "whereabouts"]:
			continue
		var relevant: bool = result.interests.any(func(i: Dictionary) -> bool:
			return i.get("promoted", false) and (i.id == "visit:" + str(row.get("destination_id", "")) \
				or i.id == "followup:" + str(row.get("subject_id", ""))))
		row["interest_promoted"] = relevant
		if relevant and row.get("intent") == "pursue":
			row["label"] = "继续按原定方向出发"
		if not relevant:
			row["goal_priority"] = 0


static func destination_reached(snapshot: Variant, goal: Dictionary) -> bool:
	if goal.get("intent_basis") != "destination" or not goal.has("own_fact_cursor"):
		return false
	var target := str(goal.get("id", "")).trim_prefix("visit:")
	var facts: Array = snapshot.get_facts_by_actor(str(snapshot.player.id))
	return facts.slice(int(goal.own_fact_cursor)).any(func(f: Dictionary) -> bool:
		return f.get("fact_type") in ["actor_arrived", "situation_place_observed"] and f.get("location_id") == target)


static func _stake(subject: String, kind: String, asset: String, fact: String, gain: String, loss: String,
		immediacy: String, uncertainty: String, paths: Array, provenance: String) -> Dictionary:
	return {"subject": subject, "stake_type": kind, "player_asset": asset, "linked_fact": fact,
		"possible_gain": gain, "possible_loss": loss, "immediacy": immediacy, "uncertainty": uncertainty,
		"intervention_paths": paths.duplicate(), "provenance": provenance}


static func _unreplaced_gift(facts: Array) -> Dictionary:
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if fact.get("fact_type") == "player_equipment_changed" and str(fact.get("slot_id", "")).trim_prefix("slot.") == "body_outer":
			return {}
		if fact.get("fact_type") == "equipment_given" and fact.get("cleared_slots", []).any(func(slot: String) -> bool: return slot.trim_prefix("slot.") == "body_outer"):
			return fact
	return {}
