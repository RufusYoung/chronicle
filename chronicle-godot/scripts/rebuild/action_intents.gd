extends RefCounted

const LABELS := {"give_food": "分一份食物", "sell_food": "出售食物", "buy": "购买物品",
	"eat": "吃一份食物", "ask_local": "问问本地人", "work": "制作与加工", "equip": "更换装备"}


static func family(action: Dictionary) -> String:
	if action.get("event_type") != "player_life":
		return ""
	var prefix := str(action.get("action_id", "")).get_slice(":", 0)
	return prefix if LABELS.has(prefix) else ""


static func project(actions: Array, opened: String = "") -> Array:
	if opened != "":
		return actions.filter(func(action: Dictionary) -> bool: return family(action) == opened)
	var groups := {}
	for action: Dictionary in actions:
		var key := family(action)
		if key != "":
			if not groups.has(key):
				groups[key] = []
			groups[key].append(action)
	var rows: Array = []
	var added := {}
	for action: Dictionary in actions:
		var key := family(action)
		if key == "" or groups[key].size() < 2:
			rows.append(action)
			continue
		if added.has(key):
			continue
		added[key] = true
		var count: int = groups[key].filter(func(row: Dictionary) -> bool: return row.get("can_execute", true)).size()
		rows.append({"action_id": "intent:" + key, "event_type": "intent", "intent_family": key,
			"label": LABELS[key], "life_group": action.get("life_group", ""), "kind": "选择具体做法",
			"cost": "展开不耗时", "can_execute": true, "action_type": action.get("action_type", "normal"),
			"known_effect": "%d 个具体选择可用；展开后选择对象、物品和代价。" % count, "tradeoff": "",
			"hint": "只展开选择，不执行行动、不消耗物品或时间。"})
	return rows
