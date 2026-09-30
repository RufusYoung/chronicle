extends RefCounted
## Presentation only. Every executable row retains its public control choice_id.

const LICENSED := {
	"1088": "res://art/licensed_temporary/life_in_adventure/sprite_1088.png",
	"1184": "res://art/licensed_temporary/life_in_adventure/sprite_1184.png",
	"2782": "res://art/licensed_temporary/life_in_adventure/sprite_2782.png",
	"2906": "res://art/licensed_temporary/life_in_adventure/sprite_2906.png",
	"2959": "res://art/licensed_temporary/life_in_adventure/sprite_2959.png",
	"3217": "res://art/licensed_temporary/life_in_adventure/sprite_3217.png",
	"3239": "res://art/licensed_temporary/life_in_adventure/sprite_3239.png",
	"3268": "res://art/licensed_temporary/life_in_adventure/sprite_3268.png",
	"3423": "res://art/licensed_temporary/life_in_adventure/sprite_3423.png",
	"3457": "res://art/licensed_temporary/life_in_adventure/sprite_3457.png",
	"3518": "res://art/licensed_temporary/life_in_adventure/sprite_3518.png",
	"3536": "res://art/licensed_temporary/life_in_adventure/sprite_3536.png",
	"3841": "res://art/licensed_temporary/life_in_adventure/sprite_3841.png",
}


static func build(response: Dictionary, page: String = "scene", focus_subject: String = "") -> Dictionary:
	var view: Dictionary = response.get("observation", {})
	var choices: Array = response.get("choices", [])
	var location: Dictionary = view.get("location", {})
	var event: Dictionary = view.get("journey_event", {})
	var combat: Array = choices.filter(func(c: Dictionary) -> bool: return c.kind == "combat_encounter")
	var situations: Array = view.get("situations", [])
	var result := {"title": location.get("title", "镜湖北岸"), "body": location.get("description", ""),
		"eyebrow": "自由漫游", "art": art(view), "choices": [], "page": page, "empty": ""}
	match page:
		"scene":
			if not combat.is_empty():
				result.merge({"title": view.risk.title, "body": str(view.risk.decision_evidence) + "\n进攻、防守或脱离都会占去这一轮。脱离后仍需选路离开。",
					"eyebrow": "交锋仍在继续", "choices": combat}, true)
			elif view.get("situation_mode", false):
				result.eyebrow = "眼前的局面"
				var selected_subject := focus_subject
				if not situations.is_empty():
					var current: Dictionary = situations[0]
					for other: Dictionary in situations:
						if other.subject_id == focus_subject:
							current = other
					result.title = current.title
					result.body = current.body
					if selected_subject == "":
						selected_subject = str(current.subject_id)
					result.choices = choices.filter(func(c: Dictionary) -> bool: return c.get("subject_id") == current.subject_id and c.get("life_group") == "situation")
				else:
					result.body = "眼下没有可交谈的人。可以原地等候，也可以沿道路离开。"
				var notices: Array = view.get("situation_notices", [])
				if not notices.is_empty() and situations.is_empty():
					result.body += "\n" + str(notices.back().text)
				result.choices.append_array(choices.filter(func(c: Dictionary) -> bool:
					return c.kind == "travel" or c.id in ["continue", "journey_block"] \
						or (c.get("intent") in ["follow", "pursue", "read_notice"] and (situations.is_empty() or c.get("subject_id") == selected_subject)) \
						or (c.get("intent") == "wait" and c.get("minutes") == 10)))
				result.empty = "可以查看地图、交谈或原地等候。没有强制的剧情入口。"
			elif not event.is_empty():
				result.merge({"title": event.title, "body": event.body, "eyebrow": "旅途中的一件事",
					"choices": choices.filter(func(c: Dictionary) -> bool: return str(c.id).begins_with("adventure:"))}, true)
			else:
				result.choices = choices.filter(func(c: Dictionary) -> bool:
					return c.kind == "travel" or c.id == "continue" or str(c.id).begins_with("incident:"))
				result.choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return int(a.get("lead_priority", 5)) < int(b.get("lead_priority", 5)))
				result.empty = "这里没有新的遭遇。可以找人交谈、休整，或在地图选择来路。"
		"map":
			result.title = "从这里出发"
			result.eyebrow = "镜湖北岸 · 可走的路"
			result.body = "当前位置：" + str(location.get("title", "")) + "\n道路只说明去向，不保证远处有人等你。"
			result.choices = choices.filter(func(c: Dictionary) -> bool: return c.kind == "travel" or c.id == "continue")
			if view.get("situation_continuity", false):
				result.choices = choices.filter(func(c: Dictionary) -> bool: return c.get("intent") in ["pursue", "follow", "read_notice"]) + result.choices
				result.body = "循着亲见或听到的消息去找人，也可以另选道路。消息会过时，抵达后须重新确认。"
			result.choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("lead_priority", 5)) < int(b.get("lead_priority", 5)))
			result.empty = "交锋尚未脱离，先回到现场处理眼前威胁。"
		"talk":
			result.title = "和这里的人说说话"
			result.eyebrow = "当面交谈"
			var names: Array = view.get("visible_people", []).map(func(p: Dictionary) -> String: return str(p.get("name", p.get("display_name", ""))))
			result.body = "在场：" + "、".join(names) if not names.is_empty() else "眼下没有可交谈的人。不必守着空屋，可以先走另一条路。"
			result.choices = choices.filter(func(c: Dictionary) -> bool: return c.get("life_group") == "talk")
			if view.get("situation_mode", false):
				result.body = "在场：" + "、".join(situations.map(func(s: Dictionary) -> String: return str(s.title))) if not situations.is_empty() else "眼下没有人在场，可以原地等候或离开。"
				result.choices.append_array(choices.filter(func(c: Dictionary) -> bool: return c.get("life_group") == "situation"))
			result.empty = "暂时没有新的话题。已问到的信息保存在旅途记录。"
		"trade":
			result.art = LICENSED["3457"]
			result.title = "当面买卖"
			result.eyebrow = "真实现货 · 当场付款"
			result.body = "选择买入、卖出或送出。钱和物品会交到对方手中；无人或无钱时不能成交。"
			result.choices = choices.filter(func(c: Dictionary) -> bool: return c.get("life_group") == "trade" or c.get("intent") in ["sell", "give", "fund"])
			result.empty = "目前没有可交易的现货或买方。已有的食物可以留作旅粮，不必继续采集。"
		"rest":
			result.title = "歇一会儿，还是继续走"
			result.eyebrow = "休整"
			result.body = "一餐能支持几小时行路；只在身体需要时停下来。"
			result.choices = choices.filter(func(c: Dictionary) -> bool: return c.get("life_group") == "rest" or c.kind in ["recovery", "wait"])
			result.empty = "现在无法休整，先处理现场的威胁或走完当前路程。"
		"work":
			result.title = "在这里谋生"
			result.eyebrow = "自选生活道路"
			result.body = "长活会占去半天。冒险无需先做这些，缺钱或想留下生活时再考虑。"
			result.choices = choices.filter(func(c: Dictionary) -> bool: return c.get("life_group") == "work")
			result.empty = "这里现在没有能做的工作。"
	var seen := {}
	result.choices = result.choices.filter(func(c: Dictionary) -> bool:
		var id := str(c.choice_id)
		if seen.has(id):
			return false
		seen[id] = true
		return true)
	return result


static func art(view: Dictionary) -> String:
	if view.get("risk", {}).get("enemy_id") == "world_threat.field_boar":
		return LICENSED["3841"]
	var event: Dictionary = view.get("journey_event", {})
	if event.get("art", "") != "":
		return LICENSED.get(str(event.art), LICENSED["1184"])
	var place := str(view.get("location", {}).get("id", ""))
	if "forest" in place:
		return LICENSED["3536"]
	if "bridge" in place:
		return LICENSED["3268"]
	if "waystone" in place:
		return LICENSED["3518"]
	if "cave" in place:
		return "res://art/environments/mirror_lake_cave_pixel_v1.png"
	if "beacon" in place or "watch_post" in place:
		return "res://art/environments/mirror_lake_beacon_pixel_v1.png"
	if "guesthouse" in str(view.get("location", {}).get("context", "")) or "客舍" in str(view.get("location", {}).get("title", "")):
		return LICENSED["3239"]
	if "road_yard" in place:
		return LICENSED["1088"]
	if int(view.get("time", {}).get("hour", 8)) >= 18 or int(view.get("time", {}).get("hour", 8)) < 6:
		return LICENSED["2906"]
	return LICENSED["1184"] if "landing" in place else LICENSED["2782"]


static func family(row: Dictionary) -> String:
	if row.get("action_type") == "situation":
		if row.get("intent") == "give" and row.has("clear_slots"):
			return "让出身上的装备"
		return {"give": "赠送备用装备", "sell": "出售备用装备", "fund": "资助在场的人", "ask": "询问近况", "caution": "劝对方谨慎", "repair": "帮忙维修", "wait": "原地等候", "follow": "随人同行", "pursue": "循着线索出发", "whereabouts": "打听认识的人", "aftermath": "听听后来的事", "read_notice": "看看在此留下的口信"}.get(str(row.get("intent", "")), "")
	var prefix := str(row.id).get_slice(":", 0)
	return {"eat": "吃一份食物", "buy": "买点东西", "sell_food": "出售食物", "give_food": "分一份食物", "sell_work": "出售制品", "ask_local": "问问本地消息", "inquire": "问问后来怎样了"}.get(prefix, "")


static func scene_rank(row: Dictionary) -> int:
	if row.get("kind") == "combat_encounter":
		return 0
	return {"aftermath": 0, "read_notice": 5, "ask": 10, "give": 20, "fund": 21, "repair": 22, "caution": 23,
		"sell": 24, "follow": 30, "pursue": 40, "whereabouts": 60, "wait": 90}.get(str(row.get("intent", "")), 50)
