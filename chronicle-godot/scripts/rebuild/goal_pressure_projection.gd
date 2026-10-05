extends RefCounted
## Intent is presentation state. Only public knowledge and existing legal offers inform its alternatives.

const Gear = preload("res://scripts/sim/equipment/resident_equipment.gd")
const Continuity = preload("res://scripts/sim/situation/situation_continuity.gd")
const Equipment = preload("res://scripts/sim/player/player_equipment.gd")


static func build(session: Variant, view: Dictionary, selected: Dictionary) -> Dictionary:
	var snapshot: Variant = session.PlayerLife.snapshot(session.context, session.stores, session.get_time_summary())
	var actor := str(session.context.actor_id)
	var facts: Array = snapshot.get_facts_by_actor(actor)
	var outer_missing := Gear.rating(snapshot.get_equipped_item(actor, "body_outer"), "body_outer") <= 0
	var gifts: Array = facts.filter(func(f: Dictionary) -> bool: return f.get("fact_type") == "equipment_given")
	var known := Continuity.knowledge(session, snapshot)
	var candidates: Array = []
	for row: Dictionary in view.get("actions", []):
		if row.get("intent") == "pursue" and row.get("lead_kind") == "danger":
			var destination := str(row.destination_id)
			_add(candidates, "visit:" + destination, "确认%s现在的情况" % session.context.locations[destination].display_name, str(row.source_fact_id))
	if outer_missing:
		_add(candidates, "replace_outerwear", "补一件能上路的外衣", "own_equipment")
	if not gifts.is_empty():
		var recipient := str(gifts.back().get("target_id", ""))
		if recipient != "":
			_add(candidates, "followup:" + recipient, "再见%s，问问后来怎样" % snapshot.get_entity(recipient).get("display_name", "受赠者"), str(gifts.back().fact_id))
	for row: Dictionary in view.get("actions", []):
		if row.get("intent") == "ask":
			var subject := str(row.get("subject_id", ""))
			_add(candidates, "understand:" + subject, "问%s眼下有什么打算" % snapshot.get_entity(subject).get("display_name", "眼前的人"), str(row.action_id))
			break
	for row: Dictionary in view.get("travel_options", []):
		if row.get("can_travel", false):
			_add(candidates, "visit:" + str(row.get("destination_id", "")), "前往%s看看" % row.get("destination_name", "邻地"), str(row.route_id))
		if candidates.size() >= 6:
			break
	var goal := selected.duplicate(true)
	for candidate: Dictionary in candidates:
		if candidate.id == selected.get("id"):
			goal = candidate.duplicate(true)
	var result := {"selected": goal, "candidates": candidates, "pressure": "", "affected_affordances": [],
		"alternatives": [], "cost_categories": [], "urgency": "none", "evidence": [],
		"provenance": "player_intent_plus_public_world_projection", "breakpoint": "NO_GOAL", "validation": "unverified"}
	if goal.is_empty():
		return result
	var kind := str(goal.id).get_slice(":", 0)
	var target := str(goal.id).get_slice(":", 1)
	var arrived: bool = kind == "visit" and view.location.id == target
	var danger: Dictionary = {}
	for row: Dictionary in known:
		if row.kind == "danger" and row.location_id == target:
			danger = row
			break
	var exposed: bool = outer_missing and (kind == "replace_outerwear" or (kind == "visit" and not danger.is_empty() and (not arrived or view.get("risk", {}).get("encounter", false))))
	var reasons: Array[String] = []
	if kind == "visit":
		if arrived:
			reasons.append("已经抵达。以眼前情况为准；可更换打算，也可留在这里行动。")
		elif not danger.is_empty():
			reasons.append("%s%d小时前提过危险，现况未确认。" % [danger.name, danger.age_hours])
			result.evidence.append(danger.source_fact_id)
		else:
			reasons.append("道路已知，远处情况尚未确认。路途与准备都会占去时间。")
	if exposed:
		var loss := "外衣已无有效防护。"
		var cause := _outer_gift(facts) if snapshot.get_equipped_item(actor, "body_outer").is_empty() else {}
		if not cause.is_empty():
			result.evidence.append(cause.fact_id)
			loss = "外衣已赠出，原有防护不再生效。"
		reasons.append(loss + "继续出发保留钱；准备装备要花钱或时间。")
	elif kind == "replace_outerwear":
		reasons.append("外衣已有有效装备；可以查看行囊，或换一个打算。")
	if kind == "understand":
		var available: bool = view.actions.any(func(row: Dictionary) -> bool: return row.get("intent") == "ask" and row.get("subject_id") == target)
		reasons.append("当面听取本人的打算；回答不会保证后来一定如此。" if available else "眼下没有新的答复可问；已知消息留在记录中，可以换一个打算。")
	if kind == "followup":
		var here: bool = view.get("visible_people", []).any(func(p: Dictionary) -> bool: return p.get("id") == target)
		reasons.append("人在现场；后续只来自本人的真实经历。" if here else "此人不在眼前。已知去向会过时；打听与追寻都可能扑空。")
	var route_id := ""
	for row: Dictionary in view.get("actions", []):
		var score := 0
		var costs: Array = []
		var id := str(row.action_id)
		if kind == "visit" and not arrived and row.get("intent") == "pursue" and row.get("destination_id") == target:
			score = 3
			route_id = str(row.route_id)
			costs = ["time", "safety"] if exposed else ["time"]
		elif kind == "followup" and ((row.get("subject_id") == target and row.get("intent") in ["aftermath", "pursue", "follow"]) or (row.get("wanted_id") == target and row.get("intent") == "whereabouts")):
			score = 3 if row.get("intent") == "aftermath" else 2
			costs = ["time"]
		elif kind == "understand" and row.get("subject_id") == target and row.get("intent") == "ask":
			score = 3
			costs = ["time"]
		if exposed:
			if id.begins_with("equip:") and _improves(snapshot, actor, snapshot.get_item(str(row.get("item_instance_id", ""))), kind == "replace_outerwear"):
				score = 4
				costs = ["equipment"]
			elif id.begins_with("buy:") and _improves(snapshot, actor, snapshot.get_item(str(row.get("item_instance_id", ""))), kind == "replace_outerwear"):
				score = 3
				costs = ["money", "time"]
			elif row.get("output_item_def_ids", []).any(func(def_id: String) -> bool: return "body_outer" in session.registry.get_definition("item", def_id).get("equip_slots", [])):
				score = 2
				costs = ["materials", "time"]
			elif id.begins_with("ask_local:"):
				score = 1
				costs = ["time"]
		row["goal_priority"] = score
		if score >= 3 and (id.begins_with("buy:") or id.begins_with("equip:")):
			var item: Dictionary = snapshot.get_item(str(row.get("item_instance_id", ""))).duplicate(true)
			item["modifiers"] = item.get("modifiers", []).filter(func(m: Dictionary) -> bool: return str(m.get("target", "")).begins_with("combat."))
			item.erase("condition")
			row["goal_effect"] = Equipment.describe(item) + ("；买入后还需穿戴" if id.begins_with("buy:") else "")
			if "body_outer" not in item.get("equip_slots", []):
				row.goal_effect += "；不补回外衣防护"
		if score > 0:
			_record(result, row, id, costs, bool(row.get("can_execute", false)))
	for row: Dictionary in view.get("travel_options", []):
		var relevant: bool = kind == "visit" and not arrived and row.get("destination_id") == target and route_id == ""
		row["goal_priority"] = 3 if relevant else 0
		if relevant:
			_record(result, row, str(row.route_id), ["time", "safety"] if exposed else ["time"], bool(row.get("can_travel", false)))
	result.pressure = " ".join(reasons)
	result.urgency = "current" if exposed else "none"
	var legal: Array = result.alternatives.filter(func(row: Dictionary) -> bool: return row.enabled and not str(row.id).begins_with("ask_local:"))
	result.breakpoint = "NO_PRESSURE" if not exposed else ("NO_SURFACE" if result.alternatives.is_empty() else ("NO_TRADEOFF" if legal.size() < 2 else ""))
	return result


static func _outer_gift(facts: Array) -> Dictionary:
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if fact.get("fact_type") == "player_equipment_changed" and str(fact.get("slot_id", "")).trim_prefix("slot.") == "body_outer":
			return {}
		if fact.get("fact_type") == "equipment_given" and fact.get("cleared_slots", []).any(func(slot: String) -> bool: return slot.trim_prefix("slot.") == "body_outer"):
			return fact
	return {}


static func _improves(snapshot: Variant, actor: String, item: Dictionary, outer_only: bool) -> bool:
	for slot: String in item.get("equip_slots", []):
		if outer_only and slot != "body_outer":
			continue
		if Gear.rating(item, slot) > Gear.rating(snapshot.get_equipped_item(actor, slot), slot):
			return true
	return false


static func _add(rows: Array, id: String, title: String, source: String) -> void:
	if not rows.any(func(row: Dictionary) -> bool: return row.id == id):
		rows.append({"id": id, "title": title, "source": source})


static func _record(result: Dictionary, row: Dictionary, id: String, costs: Array, enabled: bool) -> void:
	result.affected_affordances.append(id)
	result.alternatives.append({"id": id, "label": row.get("label", row.get("destination_name", "")),
		"enabled": enabled, "cost_categories": costs, "cost": row.get("cost", ""), "price": row.get("price", 0),
		"blocked_reason": row.get("blocked_reason", ""), "source_fact_id": row.get("source_fact_id", "")})
	for cost: String in costs:
		if cost not in result.cost_categories:
			result.cost_categories.append(cost)
