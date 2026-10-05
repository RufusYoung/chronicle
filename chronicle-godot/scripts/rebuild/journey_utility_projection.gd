extends RefCounted

const Utility = preload("res://scripts/sim/player/journey_utility.gd")
const Stakes = preload("res://scripts/rebuild/personal_stake_projection.gd")
const Gear = preload("res://scripts/sim/equipment/resident_equipment.gd")
const Equipment = preload("res://scripts/sim/player/player_equipment.gd")


static func apply(session: Variant, snapshot: Variant, view: Dictionary, result: Dictionary) -> void:
	if not Utility.enabled(session.fixture_source_data):
		return
	var fatigue := int(snapshot.player.fatigue)
	var actor := str(session.context.actor_id)
	var hand: Dictionary = snapshot.get_equipped_item(actor, "main_hand")
	if Gear.rating(hand, "main_hand") <= 0:
		result.candidates.append({"id": "prepare_main_hand", "title": "找件能用的手持装备", "source": "own_equipment", "intent_basis": "information"})
	if fatigue > 2:
		result.candidates.append({"id": "recover_energy", "title": "恢复体力，留出赶路余地", "source": "own_body", "intent_basis": "information"})
	var goal: Dictionary = result.selected
	var rest: bool = goal.get("id") == "recover_energy"
	if goal.get("id") == "prepare_main_hand":
		_prepare_hand(session, snapshot, view, result, hand)
		return
	var relevant: Array = []
	if rest:
		result.goal_status = "satisfied" if fatigue <= 2 else "active"
		result.pressure = "疲劳已降至%d，可继续走，也可更换打算。" % fatigue if fatigue <= 2 else \
			"疲劳%d/10；超过7不能加快脚程。免费休息每小时减1，借床每小时减2并花1铜币；店主须在场，床位并非随时可用。" % fatigue
		for row: Dictionary in view.actions:
			if row.action_id in ["rest", "rest_block"] or str(row.action_id).begins_with("service:bed:"):
				row["goal_priority"] = 3 if fatigue > 2 else 0
				if str(row.action_id).begins_with("service:bed:"):
					row["goal_effect"] = "疲劳%d→%d；同样时间免费休息降至%d。" % [fatigue, maxi(0, fatigue - int(row.hours) * 2), maxi(0, fatigue - int(row.hours))]
				if fatigue > 2:
					relevant.append(row)
		for row: Dictionary in view.travel_options:
			if fatigue > 2 and session.context.locations.get(str(row.destination_id), {}).has("journey_host_id"):
				row["goal_priority"] = 2
				row["goal_effect"] = "客舍有床位用途；主人是否在场须抵达确认，也可直接在此免费休息。"
	else:
		for row: Dictionary in view.actions:
			if str(row.action_id).begins_with("rush:") and goal.get("id") == "visit:" + str(row.get("destination_id", "")) \
				and not Stakes.destination_reached(snapshot, goal):
				row["goal_priority"] = 3
				relevant.append(row)
				if result.get("why_it_matters_to_you", "") == "":
					result.pressure = "同一目的地：正常步行保留体力；加快脚程省1小时，但额外增加2疲劳。时间会影响谁还在场，不保证赶上。"
	for row: Dictionary in relevant:
		var id := str(row.action_id)
		var categories := ["time", "money"] if id.begins_with("service:") else ["time", "fatigue"]
		result.alternatives.append({"id": id, "label": row.label, "enabled": row.can_execute,
			"cost": row.cost, "cost_categories": categories, "blocked_reason": row.get("blocked_reason", "")})
		result.affected_affordances.append(id)
		for category: String in categories:
			if category not in result.cost_categories:
				result.cost_categories.append(category)
	if not relevant.is_empty():
		result.personal_stakes.append(Stakes._stake(str(session.context.actor_id), "SELF_SURVIVAL", "fatigue", "own_body",
			"恢复体力或在同一道路提早抵达", "加快脚程消耗有限体力；住宿实际付钱；免费休息多占时间",
			"current", "提前抵达不会保证碰到某人或免除危险", relevant.map(func(row: Dictionary) -> String: return row.action_id), "own_body_and_formal_journey_consumers"))
		result.stake_diagnostic = "WEAK_STAKE"
		if rest:
			result.why_it_matters_to_you = result.pressure
		result.breakpoint = "NO_TRADEOFF" if result.alternatives.filter(func(row: Dictionary) -> bool: return row.enabled).size() < 2 else ""


static func _prepare_hand(session: Variant, snapshot: Variant, view: Dictionary, result: Dictionary, hand: Dictionary) -> void:
	var ready := Gear.rating(hand, "main_hand") > 0
	result.goal_status = "satisfied" if ready else "active"
	result.pressure = "已经实际装备%s，可以更换或放下打算。" % hand.get("display_name", "手持装备") if ready else \
		"手持槽没有有效装备。先看自己的行囊或当面现货，买到后仍须穿戴；工棚可能无人或缺货，不必自己制作。"
	if ready:
		return
	var paths: Array = []
	var balance: int = preload("res://scripts/sim/economy/treasury_transfer_planner.gd").new(snapshot).balance(str(session.context.actor_id))
	for row: Dictionary in view.actions:
		var id := str(row.action_id)
		if not id.begins_with("buy:") and not id.begins_with("equip:") and not id.begins_with("shore_take:"):
			continue
		var item: Dictionary = snapshot.get_item(str(row.get("item_instance_id", "")))
		if "main_hand" not in item.get("equip_slots", []) or Gear.rating(item, "main_hand") <= 0:
			continue
		row["goal_priority"] = 4 if id.begins_with("equip:") else 3
		row["goal_effect"] = Equipment.describe(item) + ("；取得后仍须穿戴" if not id.begins_with("equip:") else "")
		var price := int(row.get("price", 0))
		var categories := ["time", "fatigue", "health", "equipment"] if id.begins_with("shore_take:") else (["time", "money"] if price > 0 else ["time", "equipment"])
		result.alternatives.append({"id": id, "label": row.label, "cost": row.cost, "enabled": row.can_execute,
			"cost_categories": categories, "price": price, "blocked_reason": row.get("blocked_reason", "")})
		for category: String in categories:
			if category not in result.cost_categories:
				result.cost_categories.append(category)
		result.affected_affordances.append(id)
		paths.append(id)
		if price > 0:
			result.personal_stakes.append(Stakes._stake(str(session.context.actor_id), "MONEY", "money.copper_coin", id,
				"取得可实际穿戴的手持装备", "现有%d铜币；这件%d铜币%s" % [balance, price, "，买后余%d" % (balance - price) if balance >= price else "，目前付不起"],
				"current", "只代表现在的当面现货，不保证稍后仍在", [id], "own_budget_and_formal_equipment_offer"))
	if paths.any(func(id: String) -> bool: return id.begins_with("shore_take:")):
		result.pressure = "已看见可用手持装备，但还在原处；先比较取物风险，也可等候或离开准备。取回后仍须穿戴。"
	for route: Dictionary in view.travel_options:
		var purpose: String = session.PlayerLife.Local.destination_guide(session, str(route.destination_id))
		if "工具作坊" in purpose:
			route["goal_priority"] = 2
			route["goal_effect"] = "这里有作坊用途，但卖家是否在场、有无装备须抵达确认。"
	result.personal_stakes.append(Stakes._stake(str(session.context.actor_id), "SELF_SURVIVAL", "main_hand", "own_equipment",
		"实际穿戴后才进入正式战斗加成；不保证遇险或获胜", "现有装备不能提供有效手持加成；备装可能花钱，也可能白跑一趟",
		"current", "不制造战斗来证明购买有用", paths, "own_loadout_and_formal_equipment_consumer"))
	result.why_it_matters_to_you = result.pressure
	result.stake_diagnostic = "WEAK_STAKE"
	result.breakpoint = "NO_LOCAL_OFFER" if paths.is_empty() else ""
