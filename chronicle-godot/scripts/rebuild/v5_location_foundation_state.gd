extends RefCounted
class_name V5LocationFoundationState

const DATA_PATH := "res://data/rebuild/lake_town_location_foundation.json"
const LOCATION_ACTION_IDS := {
	"lake_town": [
		"approach_chen_mi",
		"inspect_price_notice",
		"ask_market_grain_price",
		"go_abandoned_granary",
		"stay_one_month",
		"leave_lake_town",
	],
	"old_chen_shop": [
		"approach_chen_mi",
		"inspect_price_notice",
		"knock_old_chen",
		"observe_shop_traces",
		"return_lake_town",
	],
	"market": [
		"ask_market_grain_price",
		"observe_grain_buyers",
		"ask_vendor",
		"return_lake_town",
	],
	"dock": [
		"inspect_docked_ships",
		"ask_north_caravan",
		"observe_guard_patrol",
		"return_lake_town",
	],
	"guard_post": [
		"ask_night_patrol",
		"report_abnormal_to_guard",
		"inspect_guard_notice_board",
		"return_lake_town",
	],
	"abandoned_granary": [
		"inspect_granary_door_gap",
		"inspect_gray_grain_powder",
		"enter_granary",
		"return_lake_town",
	],
}
const EXTRA_ACTIONS := [
	{
		"id": "knock_old_chen",
		"type": "normal",
		"prefix": "普通",
		"label": "敲门找老陈",
		"time_cost": "",
	},
	{
		"id": "observe_shop_traces",
		"type": "normal",
		"prefix": "普通",
		"label": "观察门口痕迹",
		"time_cost": "",
	},
	{
		"id": "observe_grain_buyers",
		"type": "normal",
		"prefix": "普通",
		"label": "观察买粮的人",
		"time_cost": "",
	},
	{
		"id": "ask_vendor",
		"type": "normal",
		"prefix": "普通",
		"label": "询问摊贩",
		"time_cost": "",
	},
	{
		"id": "inspect_docked_ships",
		"type": "normal",
		"prefix": "普通",
		"label": "查看停靠商船",
		"time_cost": "",
	},
	{
		"id": "ask_north_caravan",
		"type": "clue",
		"prefix": "线索",
		"label": "打听北路商队",
		"time_cost": "",
	},
	{
		"id": "observe_guard_patrol",
		"type": "normal",
		"prefix": "普通",
		"label": "观察守卫巡逻",
		"time_cost": "",
	},
	{
		"id": "ask_night_patrol",
		"type": "normal",
		"prefix": "普通",
		"label": "询问夜巡情况",
		"time_cost": "",
	},
	{
		"id": "report_abnormal_to_guard",
		"type": "dialogue",
		"prefix": "对话",
		"label": "向守卫报告异常",
		"time_cost": "",
	},
	{
		"id": "inspect_guard_notice_board",
		"type": "normal",
		"prefix": "普通",
		"label": "查看告示栏",
		"time_cost": "",
	},
	{
		"id": "inspect_granary_door_gap",
		"type": "danger",
		"prefix": "危险",
		"label": "检查门缝",
		"time_cost": "",
	},
	{
		"id": "inspect_gray_grain_powder",
		"type": "clue",
		"prefix": "线索",
		"label": "查看灰白粮粉",
		"time_cost": "",
	},
	{
		"id": "enter_granary",
		"type": "danger",
		"prefix": "危险",
		"label": "进入粮仓",
		"time_cost": "",
	},
]
const CONTEXT_ACTION_TEXT := {
	"knock_old_chen": {
		"title": "敲门找老陈",
		"text": "你敲了敲半掩的铺门。门后没有人回答，只传来木板轻轻晃动的声音。",
		"people": [],
		"traces": ["半掩的铺门", "没有回应的屋内"],
	},
	"observe_shop_traces": {
		"title": "门口痕迹",
		"text": "门口的雨水把粮粉冲成浅浅的灰线。台阶边有小脚印，又很快被来往的人踩乱。",
		"people": [],
		"traces": ["灰白粮粉", "小脚印", "被踩乱的台阶"],
	},
	"observe_grain_buyers": {
		"title": "买粮的人",
		"text": "买粮的人都把声音压得很低。他们先看价格牌，再看守卫，最后才摸自己的钱袋。",
		"people": ["买粮人"],
		"traces": ["压低的声音", "被反复看的价格牌"],
	},
	"ask_vendor": {
		"title": "询问摊贩",
		"text": "摊贩说今天先不赊账。他没有解释原因，只把袋口重新扎紧。",
		"people": ["摊贩"],
		"traces": ["扎紧的干粮袋"],
	},
	"inspect_docked_ships": {
		"title": "停靠商船",
		"text": "码头边只有几条小船靠着，真正装粮的大船没有出现。脚夫们把空货箱摞在棚下。",
		"people": ["码头脚夫"],
		"traces": ["空货箱", "没有靠岸的大船"],
	},
	"ask_north_caravan": {
		"title": "北路商队",
		"text": "有人说北路商队迟了三天，也有人说他们绕去了更安全的路。没人愿意把话说死。",
		"people": ["码头脚夫"],
		"traces": ["北路传闻", "空货箱"],
		"clue_id": "north_caravan_late",
	},
	"observe_guard_patrol": {
		"title": "守卫巡逻",
		"text": "两个守卫沿码头走了一圈，在仓库方向停得比别处久一些。",
		"people": ["守卫"],
		"traces": ["仓库方向的停留", "夜巡靴印"],
	},
	"ask_night_patrol": {
		"title": "夜巡情况",
		"text": "守卫说夜巡只是例行安排，但他没有否认仓库方向最近多了脚印。",
		"people": ["守卫"],
		"traces": ["夜巡表", "仓库方向脚印"],
	},
	"report_abnormal_to_guard": {
		"title": "报告异常",
		"text": "守卫把你说的话记在木板背面，只说会让夜巡多看一眼废弃粮仓。",
		"people": ["守卫"],
		"traces": ["木板背面的记录"],
	},
	"inspect_guard_notice_board": {
		"title": "告示栏",
		"text": "告示栏上多是夜巡和市场秩序的旧告示，最新一张把仓库方向划成了重点巡查区。",
		"people": [],
		"traces": ["重点巡查区", "夜巡告示"],
	},
	"inspect_granary_door_gap": {
		"title": "粮仓门缝",
		"text": "门缝比远看时更宽。里面没有灯，只有一股潮湿的霉味从黑处漫出来。",
		"people": [],
		"traces": ["裂开的门板", "潮湿霉味"],
	},
	"inspect_gray_grain_powder": {
		"title": "灰白粮粉",
		"text": "灰白色粮粉黏在门槛和泥里，像是从旧麻袋底部漏出来的。霉味让人不太放心。",
		"people": [],
		"traces": ["灰白色粮粉", "旧麻袋痕迹"],
		"clue_id": "granary_gray_powder",
	},
	"enter_granary": {
		"title": "进入粮仓",
		"text": "你侧身进了粮仓。里面没有整袋新粮，只有被翻动过的麻袋、潮湿木板和更重的霉味。",
		"people": [],
		"traces": ["被翻动过的麻袋", "潮湿木板", "霉味"],
		"clue_id": "granary_gray_powder",
	},
}

var source_data: Dictionary = {}
var character: Dictionary = {}
var region_statuses: Dictionary = {}
var locations: Dictionary = {}
var clues: Dictionary = {}
var actions: Dictionary = {}
var discovered_clue_ids: Array[String] = []
var available_action_ids: Array[String] = []
var action_history: Array[Dictionary] = []
var life_panel: Dictionary = {}
var current_location_id := "lake_town"
var scene_title := "湖湾镇"
var scene_text := ""
var visible_people: Array[String] = []
var visible_traces: Array[String] = []
var scene_hint := "地点局面"


func _init(path: String = DATA_PATH) -> void:
	load_static_data(path)


func load_static_data(path: String = DATA_PATH) -> bool:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("[V5LocationFoundationState] Failed to load data: %s" % path)
		return false
	source_data = (parsed as Dictionary).duplicate(true)
	character = (source_data.get("character", {}) as Dictionary).duplicate(true)
	current_location_id = str(character.get("current_location_id", "lake_town"))
	var region := source_data.get("region", {}) as Dictionary
	region_statuses = _index_by_id(region.get("statuses", []) as Array)
	locations = _index_by_id(source_data.get("locations", []) as Array)
	clues = _index_by_id(source_data.get("clues", []) as Array)
	actions = _index_by_id(source_data.get("actions", []) as Array)
	_add_extra_actions()
	discovered_clue_ids = []
	action_history = []
	life_panel = (source_data.get("life_panel", {}) as Dictionary).duplicate(true)
	_set_scene_from_location(current_location_id)
	_set_available_actions_for_location(current_location_id)
	return true


func apply_action(action_id: String) -> Dictionary:
	var before_location := current_location_id
	match action_id:
		"approach_chen_mi":
			_apply_approach_chen_mi()
		"inspect_price_notice":
			_apply_inspect_price_notice()
		"ask_market_grain_price":
			_apply_ask_market_grain_price()
		"go_abandoned_granary":
			_apply_go_abandoned_granary()
		"stay_one_month":
			_apply_stay_one_month()
		"leave_lake_town":
			_apply_leave_lake_town()
		"give_food_to_chen_mi":
			_apply_give_food_to_chen_mi()
		"ask_chen_mi_about_grain":
			_apply_ask_chen_mi_about_grain()
		"ignore_chen_mi":
			_apply_ignore_chen_mi()
		"return_lake_town":
			_apply_return_lake_town()
		"shelve_clue":
			_apply_shelve_clue()
		_:
			if actions.has(action_id):
				_apply_contextual_action(action_id)
			else:
				return {
					"ok": false,
					"action_id": action_id,
					"message": "未知行动：%s" % action_id,
				}
	_record_action(action_id, before_location)
	return {
		"ok": true,
		"action_id": action_id,
		"current_location_id": current_location_id,
		"scene_title": scene_title,
	}


func get_character() -> Dictionary:
	return character.duplicate(true)


func get_region_statuses() -> Array:
	var rows: Array[Dictionary] = []
	for status_id: Variant in region_statuses:
		rows.append((region_statuses[status_id] as Dictionary).duplicate(true))
	return rows


func get_location(location_id: String) -> Dictionary:
	return (locations.get(location_id, {}) as Dictionary).duplicate(true)


func get_locations() -> Array:
	var rows: Array[Dictionary] = []
	for location_id: Variant in locations:
		rows.append((locations[location_id] as Dictionary).duplicate(true))
	return rows


func get_current_location_id() -> String:
	return current_location_id


func get_current_scene() -> Dictionary:
	return {
		"location_id": current_location_id,
		"title": scene_title,
		"text": scene_text,
		"visible_people": visible_people.duplicate(),
		"visible_traces": visible_traces.duplicate(),
		"child_location_ids": (
			(locations.get(current_location_id, {}) as Dictionary).get(
				"child_location_ids",
				[]
			) as Array
		).duplicate(),
		"hint": scene_hint,
	}


func get_discovered_clues() -> Array:
	var rows: Array[Dictionary] = []
	for clue_id: String in discovered_clue_ids:
		var clue := clues.get(clue_id, {}) as Dictionary
		if not clue.is_empty():
			rows.append(clue.duplicate(true))
	return rows


func has_clue(clue_id: String) -> bool:
	return clue_id in discovered_clue_ids


func get_clue(clue_id: String) -> Dictionary:
	return (clues.get(clue_id, {}) as Dictionary).duplicate(true)


func get_available_actions() -> Array:
	var rows: Array[Dictionary] = []
	for action_id: String in available_action_ids:
		var action := actions.get(action_id, {}) as Dictionary
		if not action.is_empty():
			rows.append(action.duplicate(true))
	return rows


func get_life_panel() -> Dictionary:
	return life_panel.duplicate(true)


func get_action_history() -> Array:
	return action_history.duplicate(true)


func set_current_location(location_id: String) -> void:
	if not locations.has(location_id):
		return
	current_location_id = location_id
	_set_character_location(location_id)
	_set_scene_from_location(location_id)
	_set_available_actions_for_location(location_id)


func _apply_approach_chen_mi() -> void:
	scene_title = "陈米"
	scene_text = (
		"你走近时，陈米把旧布袋抱得更紧。她没有立刻逃开，只是抬头看了你一眼。"
		+ "\n\n布袋口露出一点灰白色粉末，她的手指冻得发红。"
	)
	visible_people = ["陈米"]
	visible_traces = ["旧布袋", "灰白色粉末", "发红的手指"]
	scene_hint = "人物近景"
	available_action_ids = [
		"give_food_to_chen_mi",
		"ask_chen_mi_about_grain",
		"ignore_chen_mi",
	]


func _apply_inspect_price_notice() -> void:
	scene_title = "涨价告示"
	scene_text = (
		"告示上的字被雨水泡皱，但最后一行还能看清：明日起，干粮再涨一次。"
		+ "\n\n旁边有人用指甲划过旧价格，划痕很深。"
	)
	visible_people = []
	visible_traces = ["涨价告示", "被划掉的旧价格"]
	scene_hint = "调查结果"
	_discover_clue("price_rise_tomorrow")
	_ensure_action("ask_market_grain_price")


func _apply_ask_market_grain_price() -> void:
	set_current_location("market")
	scene_title = "市场粮价"
	scene_text = (
		"市场摊主没有直接回答你，只把干粮袋往身后挪了挪。"
		+ "\n\n有人低声说，北路商队迟了三天，下一批粮什么时候到没人知道。"
	)
	visible_people = ["摊主", "买粮人"]
	visible_traces = ["压低的谈话声", "扎紧的干粮袋"]
	scene_hint = "线索行动"
	_update_region_status(
		"food",
		"紧张",
		"市场上的干粮涨了一次价。有人低声说，北路商队迟了三天。"
	)
	_discover_clue("north_caravan_late")


func _apply_go_abandoned_granary() -> void:
	set_current_location("abandoned_granary")
	scene_title = "废弃粮仓"
	scene_text = (
		"你推开半裂的门板，霉味立刻从缝里涌出来。地上的灰白色粮粉一路拖到墙边。"
		+ "\n\n这里没有新粮，只有潮湿、脚印和被翻动过的麻袋。"
	)
	visible_people = []
	visible_traces = ["灰白色粮粉", "被翻动过的麻袋", "潮湿霉味"]
	scene_hint = "危险地点"
	_discover_clue("granary_gray_powder")
	available_action_ids = [
		"ask_market_grain_price",
		"return_lake_town",
		"stay_one_month",
		"leave_lake_town",
	]


func _apply_stay_one_month() -> void:
	scene_title = "在湖湾镇停留一月"
	scene_text = (
		"一个月过去，湖湾镇没有真正恢复。老陈铺子偶尔开半日，市场的粮袋仍然扎得很紧。"
		+ "\n\n你熟悉了夜巡的脚步，也学会在买粮前先看一眼价格牌。"
	)
	visible_people = ["守卫", "买粮人"]
	visible_traces = ["半开的铺门", "反复改写的价格牌"]
	scene_hint = "月度摘要"
	_adjust_stat("energy", -8)
	_adjust_stat("hunger", 12)
	_adjust_stat("sanity", -4)
	_update_region_status(
		"morale",
		"低沉",
		"一个月后，市场里仍少有人大声说话，买粮的人会先看守卫。"
	)
	var completed := life_panel.get("completed_experiences", []) as Array
	if "在湖湾镇停留一月" not in completed:
		completed.append("在湖湾镇停留一月")
	life_panel["completed_experiences"] = completed


func _apply_leave_lake_town() -> void:
	scene_title = "离开湖湾镇"
	scene_text = (
		"你沿着北路离开湖湾镇。镇口的风从湖面吹来，带着潮湿的粮粉味。"
		+ "\n\n身后的铺门、告示和陈米的旧布袋，都留在这一天的记忆里。"
	)
	visible_people = []
	visible_traces = ["北路", "湖面潮风"]
	scene_hint = "离开"
	available_action_ids = ["return_lake_town"]


func _apply_give_food_to_chen_mi() -> void:
	scene_title = "给她食物"
	scene_text = (
		"你把一点干粮递过去。陈米先看你的手，再看铺门，最后小声说了句谢谢。"
		+ "\n\n她没有立刻吃完，只把一半重新塞回布袋里。"
	)
	visible_people = ["陈米"]
	visible_traces = ["少了一点的干粮", "被重新扎紧的布袋"]
	scene_hint = "人物行动"
	_adjust_stat("hunger", 4)
	_adjust_stat("sanity", 2)
	_update_region_status(
		"morale",
		"压抑",
		"市场里仍少有人大声说话，但有人看见你把食物递给了陈米。"
	)
	available_action_ids = _strings(source_data.get("initial_action_ids", []) as Array)


func _apply_ask_chen_mi_about_grain() -> void:
	scene_title = "问粮从哪来的"
	scene_text = (
		"陈米沉默了很久，才说那不是偷来的新粮。她说废弃粮仓里还有一点别人不要的东西。"
		+ "\n\n她不确定那些粮还能不能吃。"
	)
	visible_people = ["陈米"]
	visible_traces = ["旧布袋", "被她避开的目光"]
	scene_hint = "对话结果"
	_discover_clue("granary_gray_powder")
	available_action_ids = [
		"go_abandoned_granary",
		"give_food_to_chen_mi",
		"ignore_chen_mi",
	]


func _apply_ignore_chen_mi() -> void:
	scene_title = "装作没看见"
	scene_text = (
		"你没有继续问。陈米抱着布袋坐回门边，像是希望自己也能变成铺门上的影子。"
		+ "\n\n街上的人经过这里时，都走得比平时更快。"
	)
	visible_people = ["陈米"]
	visible_traces = ["旧布袋", "沉默的街口"]
	scene_hint = "回避"
	_adjust_stat("sanity", -3)
	available_action_ids = _strings(source_data.get("initial_action_ids", []) as Array)


func _apply_return_lake_town() -> void:
	set_current_location("lake_town")


func _apply_shelve_clue() -> void:
	scene_title = "暂时搁置"
	scene_text = "你把这条线索暂时压在心里，回到眼前的湖湾镇局面。"
	visible_people = []
	visible_traces = ["暂时搁置的线索"]
	scene_hint = "线索搁置"


func _apply_contextual_action(action_id: String) -> void:
	var text_data := CONTEXT_ACTION_TEXT.get(action_id, {}) as Dictionary
	scene_title = str(
		text_data.get(
			"title",
			(actions.get(action_id, {}) as Dictionary).get("label", action_id)
		)
	)
	scene_text = str(text_data.get("text", "这个入口目前只记录为地点行动占位。"))
	visible_people = _strings(text_data.get("people", []) as Array)
	visible_traces = _strings(text_data.get("traces", []) as Array)
	scene_hint = "地点行动"
	var clue_id := str(text_data.get("clue_id", ""))
	if clue_id != "":
		_discover_clue(clue_id)


func _record_action(action_id: String, from_location_id: String) -> void:
	action_history.append({
		"index": action_history.size() + 1,
		"action_id": action_id,
		"action_label": str((actions.get(action_id, {}) as Dictionary).get("label", action_id)),
		"from_location_id": from_location_id,
		"to_location_id": current_location_id,
		"scene_title": scene_title,
	})


func _set_scene_from_location(location_id: String) -> void:
	var location := locations.get(location_id, {}) as Dictionary
	scene_title = str(location.get("name", location_id))
	scene_text = str(location.get("description", ""))
	visible_people = _strings(location.get("visible_people", []) as Array)
	visible_traces = _strings(location.get("visible_traces", []) as Array)
	scene_hint = "地点局面"


func _set_available_actions_for_location(location_id: String) -> void:
	var ids := LOCATION_ACTION_IDS.get(location_id, []) as Array
	if ids.is_empty():
		ids = source_data.get("initial_action_ids", []) as Array
	available_action_ids = _strings(ids)


func _set_character_location(location_id: String) -> void:
	var location := locations.get(location_id, {}) as Dictionary
	character["current_location_id"] = location_id
	character["current_location_name"] = str(location.get("name", location_id))


func _update_region_status(status_id: String, state: String, detail: String) -> void:
	var status := (region_statuses.get(status_id, {}) as Dictionary).duplicate(true)
	if status.is_empty():
		return
	status["state"] = state
	status["detail"] = detail
	region_statuses[status_id] = status


func _discover_clue(clue_id: String) -> void:
	if clues.has(clue_id) and clue_id not in discovered_clue_ids:
		discovered_clue_ids.append(clue_id)


func _ensure_action(action_id: String) -> void:
	if actions.has(action_id) and action_id not in available_action_ids:
		available_action_ids.append(action_id)


func _add_extra_actions() -> void:
	for action_value: Variant in EXTRA_ACTIONS:
		var action := action_value as Dictionary
		var action_id := str(action.get("id", ""))
		if action_id != "" and not actions.has(action_id):
			actions[action_id] = action.duplicate(true)


func _adjust_stat(stat_id: String, delta: int) -> void:
	var stats := character.get("stats", {}) as Dictionary
	var stat := (stats.get(stat_id, {}) as Dictionary).duplicate(true)
	if stat.is_empty():
		return
	var current := int(stat.get("current", 0)) + delta
	var max_value := int(stat.get("max", current))
	stat["current"] = clampi(current, 0, max_value)
	stats[stat_id] = stat
	character["stats"] = stats


func _index_by_id(rows: Array) -> Dictionary:
	var output: Dictionary = {}
	for row_value: Variant in rows:
		var row := row_value as Dictionary
		var row_id := str(row.get("id", ""))
		if row_id != "":
			output[row_id] = row.duplicate(true)
	return output


func _strings(values: Array) -> Array[String]:
	var output: Array[String] = []
	for value: Variant in values:
		output.append(str(value))
	return output
