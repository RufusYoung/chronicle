extends RefCounted
class_name V5LiveLocationViewModel

const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")

const FIXTURE_PATH := "res://data/sim/fixtures/lake_town_food_crisis_fixture.json"
const RULE_PATHS := [
	"res://data/sim/raw/action_rules/basic_action_rules.json",
	"res://data/sim/raw/action_rules/domain_action_rules.json",
]

var session: Variant = null
var start_result: Dictionary = {}
var latest_result: Dictionary = {}
var action_history: Array[Dictionary] = []
var latest_event_type: String = ""


func _init(source_session: Variant = null) -> void:
	session = source_session


func start() -> Dictionary:
	if session == null:
		session = SimSessionModel.new()
	action_history.clear()
	latest_result = {}
	latest_event_type = ""
	start_result = session.start_from_fixture_path(FIXTURE_PATH, RULE_PATHS)
	return start_result.duplicate(true)


func is_ready() -> bool:
	return session != null and session.is_ready()


func perform_action(action_id: String) -> Dictionary:
	latest_event_type = "player_action"
	if not is_ready():
		latest_result = {
			"success": false,
			"error": "session_not_initialized",
			"action_id": action_id,
		}
		return latest_result.duplicate(true)

	var option := _find_action_option(action_id)
	latest_result = session.execute_action(action_id, {
		"source": "v5_live_location_surface",
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"action_id": action_id,
			"label": str(option.get("label", "采取行动")),
			"contract_status": str(latest_result.get("contract_status", "")),
			"narrative": _result_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func advance_time(hours: int = 1) -> Dictionary:
	latest_event_type = "world_tick"
	if not is_ready():
		latest_result = {
			"success": false,
			"error_reason": "session_not_initialized",
		}
		return latest_result.duplicate(true)

	latest_result = session.advance_time(hours, "after_short_wait", {
		"label": "在老陈铺子等待一小时",
		"source": "v5_live_location_surface",
	})
	if bool(latest_result.get("success", false)):
		action_history.append({
			"index": action_history.size() + 1,
			"event_type": "world_tick",
			"label": "等待一小时",
			"triggered_count": int(latest_result.get("triggered_count", 0)),
			"narrative": _tick_narrative(latest_result),
		})
	return latest_result.duplicate(true)


func build_view_data() -> Dictionary:
	if not is_ready():
		return {
			"ready": false,
			"error_text": "局面暂时无法载入。",
			"actions": [],
		}

	var snapshot: Variant = session.get_snapshot()
	var location: Dictionary = snapshot.location
	var visible_people: Array[Dictionary] = []
	var visible_observations: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_visible_entities():
		var row := _entity_row(entity)
		if str(entity.get("type", "")) == "person":
			visible_people.append(row)
		else:
			visible_observations.append(row)

	return {
		"ready": true,
		"location": {
			"id": str(location.get("id", "")),
			"title": str(location.get("display_name", "未知地点")),
			"description": str(
				location.get("description", "你停下来观察眼前的地方。")
			),
			"context": _location_context(location, snapshot),
		},
		"player": _player_view(snapshot),
		"time": _time_view(),
		"region_status": _region_status_rows(snapshot),
		"visible_people": visible_people,
		"visible_observations": visible_observations,
		"actions": _action_rows(),
		"knowledge": _knowledge_rows(snapshot),
		"feedback": _feedback_view(),
		"history": action_history.duplicate(true),
		"world_log_count": session.get_world_log_entries().size(),
	}


func _action_rows() -> Array:
	var rows: Array[Dictionary] = []
	for option: Dictionary in session.get_action_options():
		var action_type := str(option.get("action_type", "normal"))
		rows.append({
			"action_id": str(option.get("action_id", "")),
			"label": str(option.get("label", "采取行动")),
			"action_type": action_type,
			"kind": _action_kind(action_type),
			"hint": _action_hint(option),
		})
	return rows


func _entity_row(entity: Dictionary) -> Dictionary:
	var states: Dictionary = entity.get("states", {})
	var entity_type := str(entity.get("type", ""))
	return {
		"id": str(entity.get("id", "")),
		"name": str(entity.get("display_name", "未命名")),
		"description": str(entity.get("description", "")),
		"state_text": (
			_person_state_text(states)
			if entity_type == "person"
			else _object_state_text(entity_type, states)
		),
	}


func _player_view(snapshot: Variant) -> Dictionary:
	var role := str(snapshot.get_player_value("role", "traveler"))
	return {
		"title": "无名旅人",
		"role": _role_label(role),
		"food_count": int(snapshot.get_player_value("food_count", 0)),
		"perception": int(snapshot.get_player_value("perception", 0)),
		"summary": "身份　%s\n食物　%d 份\n感知　%d" % [
			_role_label(role),
			int(snapshot.get_player_value("food_count", 0)),
			int(snapshot.get_player_value("perception", 0)),
		],
	}


func _region_status_rows(snapshot: Variant) -> Array:
	var rows: Array[Dictionary] = []
	var sources := [
		["food_pressure", snapshot.region_state],
		["public_order", snapshot.region_state],
		["market_order", snapshot.institution],
		["local_guard_attention", snapshot.institution],
	]
	for source: Array in sources:
		var key := str(source[0])
		var values := source[1] as Dictionary
		if not values.has(key):
			continue
		rows.append({
			"key": key,
			"label": _status_label(key),
			"value": _state_value_label(str(values.get(key, ""))),
			"detail": _status_detail(key, str(values.get(key, ""))),
		})
	var shortage_pressure := 0
	var location_id := str(snapshot.location.get("id", ""))
	for pressure: Dictionary in snapshot.get_pressures():
		if (
			str(pressure.get("scope_id", "")) == location_id
			and str(pressure.get("pressure_type", "")) == "market_shortage"
		):
			shortage_pressure += int(pressure.get("value", 0))
	if shortage_pressure > 0:
		rows.append({
			"key": "market_shortage",
			"label": "收铺迹象",
			"value": "加剧",
			"detail": "商铺开始提前关门，能买到粮食的时间正在缩短。",
		})
	return rows


func _knowledge_rows(snapshot: Variant) -> Array:
	var rows: Array[String] = []
	for fact: Dictionary in snapshot.get_facts():
		var fact_type := str(fact.get("fact_type", ""))
		var target_name := str(fact.get("target_display_name", ""))
		if target_name == "":
			target_name = _entity_name(str(fact.get("target_id", "")))
		rows.append(_fact_text(fact_type, target_name))
	if rows.is_empty():
		rows.append("你还没有确认任何值得记下的事实。")
	return rows


func _feedback_view() -> Dictionary:
	if latest_result.is_empty():
		return {
			"status": "idle",
			"title": "局面刚刚展开",
			"body": "先看清这里的人和痕迹，再决定把手伸向哪里。",
			"details": [],
		}

	if latest_event_type == "world_tick":
		return _tick_feedback_view()

	if not bool(latest_result.get("success", false)):
		var error := str(latest_result.get("error", ""))
		return {
			"status": "error",
			"title": "行动没有发生",
			"body": (
				"局面已经变化，这个行动不再可用。"
				if error == "candidate_not_found"
				else "当前局面无法执行这个行动。"
			),
			"details": [],
		}

	var transaction: Dictionary = latest_result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	var candidate: Dictionary = latest_result.get("candidate", {})
	var contract_status := str(latest_result.get("contract_status", ""))
	var title := str(narrative.get("title", ""))
	var body := _result_narrative(latest_result)
	if title == "":
		title = str(candidate.get("label", "行动已记录"))
	if body == "":
		body = (
			"你做出了这个选择。它已被记录，但还没有产生可结算的世界变化。"
			if contract_status == "candidate_only"
			else "行动已经发生。"
		)
	return {
		"status": contract_status,
		"title": title,
		"body": body,
		"details": _result_detail_lines(transaction),
	}


func _tick_feedback_view() -> Dictionary:
	if not bool(latest_result.get("success", false)):
		return {
			"status": "error",
			"title": "时间没有推进",
			"body": "这个时间变化无法作用于当前世界。",
			"details": [],
		}

	var triggered_count := int(latest_result.get("triggered_count", 0))
	if triggered_count == 0:
		return {
			"status": "world_tick",
			"title": "一小时过去",
			"body": "这里没有立刻显现出新的变化，但世界时钟仍在向前。",
			"details": [],
		}

	var results: Array = latest_result.get("results", [])
	var result_data: Dictionary = results[0] if not results.is_empty() else {}
	var narrative: Dictionary = result_data.get("narrative_result", {})
	return {
		"status": "world_tick",
		"title": str(narrative.get("title", "时间带来了变化")),
		"body": _tick_narrative(latest_result),
		"details": _tick_detail_lines(result_data),
	}


func _tick_narrative(result: Dictionary) -> String:
	var entries: Array = result.get("world_log_entries", [])
	if not entries.is_empty():
		var entry := entries[0] as Dictionary
		var summary := str(entry.get("narrative_summary", ""))
		if summary != "":
			return summary
	var results: Array = result.get("results", [])
	if not results.is_empty():
		var result_data := results[0] as Dictionary
		var narrative: Dictionary = result_data.get("narrative_result", {})
		return str(narrative.get("summary", ""))
	return ""


func _tick_detail_lines(result_data: Dictionary) -> Array:
	var rows: Array[String] = []
	for change: Dictionary in result_data.get("state_changes", []):
		rows.append(_state_change_text(change))
	for pressure: Dictionary in result_data.get("pressure_changes", []):
		if str(pressure.get("pressure_type", "")) == "market_shortage":
			rows.append("老陈铺子周围的粮食压力继续上升")
	if not (result_data.get("facts_added", []) as Array).is_empty():
		rows.append("这次变化已经成为可追溯的世界事实")
	return rows


func _result_narrative(result: Dictionary) -> String:
	var world_log_entry: Dictionary = result.get("world_log_entry", {})
	var summary := str(world_log_entry.get("narrative_summary", ""))
	if summary != "":
		return summary
	var transaction: Dictionary = result.get("transaction_result", {})
	var narrative: Dictionary = transaction.get("narrative_result", {})
	return str(narrative.get("summary", narrative.get("body", "")))


func _result_detail_lines(transaction: Dictionary) -> Array:
	var rows: Array[String] = []
	for change: Dictionary in transaction.get("state_changes", []):
		rows.append(_state_change_text(change))
	for change: Dictionary in transaction.get("relationship_changes", []):
		rows.append(_relationship_change_text(change))
	var facts: Array = transaction.get("facts_added", [])
	if not facts.is_empty():
		rows.append("形成了 %d 条可追溯事实" % facts.size())
	return rows


func _state_change_text(change: Dictionary) -> String:
	var entity_id := str(change.get("entity_id", ""))
	var key := str(change.get("key", ""))
	if key == "visible" and bool(change.get("to", false)):
		return "%s出现在现场" % _entity_name(entity_id)
	if key == "price_level" and str(change.get("to", "")) == "raised_again":
		return "%s上的价格又被改高" % _entity_name(entity_id)
	if entity_id == "player" and key == "food_count":
		return "随身食物 %s" % _signed_number(int(change.get("delta", 0)))
	if key == "hunger" and str(change.get("operation", "")) == "decrease_tier":
		return "%s的饥饿有所缓和" % _entity_name(entity_id)
	return "%s的%s发生变化" % [_entity_name(entity_id), _state_key_label(key)]


func _relationship_change_text(change: Dictionary) -> String:
	return "%s对你的%s %s" % [
		_entity_name(str(change.get("source_id", ""))),
		_relationship_axis_label(str(change.get("axis", ""))),
		_signed_number(int(change.get("delta", 0))),
	]


func _find_action_option(action_id: String) -> Dictionary:
	for option: Dictionary in session.get_action_options():
		if str(option.get("action_id", "")) == action_id:
			return option.duplicate(true)
	return {}


func _entity_name(entity_id: String) -> String:
	if entity_id == "player":
		return "你"
	if not is_ready():
		return "某个对象"
	var entity: Dictionary = session.get_snapshot().get_entity(entity_id)
	return str(entity.get("display_name", "某个对象"))


func _location_context(location: Dictionary, snapshot: Variant) -> String:
	var labels: Array[String] = []
	for tag: Variant in location.get("tags", []):
		var label := _location_tag_label(str(tag))
		if label != "" and label not in labels:
			labels.append(label)
	var pressure := str(snapshot.get_region_state_value("food_pressure", ""))
	if pressure == "high":
		labels.append("粮食紧缺")
	return " · ".join(labels)


func _person_state_text(states: Dictionary) -> String:
	var rows: Array[String] = []
	if states.has("hunger"):
		rows.append("饥饿：%s" % _hunger_label(str(states.get("hunger", ""))))
	if states.has("fear"):
		rows.append("戒备：%s" % _fear_label(str(states.get("fear", ""))))
	return "　".join(rows)


func _object_state_text(entity_type: String, states: Dictionary) -> String:
	if str(states.get("price_level", "")) == "raised_again":
		return "刚被再次改高　可以阅读"
	if entity_type == "readable_notice" and bool(states.get("readable", false)):
		return "可以阅读"
	if entity_type == "trace" and bool(states.get("inspectable", false)):
		return "可以检查"
	return "就在眼前"


func _time_view() -> Dictionary:
	var summary: Dictionary = session.get_time_summary()
	var day := int(summary.get("day", 1))
	var hour := int(summary.get("hour", 0))
	return {
		"day": day,
		"hour": hour,
		"label": "第 %d 天　%02d:00" % [day, hour],
		"period": _time_period(hour),
	}


func _time_period(hour: int) -> String:
	if hour < 6:
		return "深夜"
	if hour < 12:
		return "上午"
	if hour < 18:
		return "下午"
	return "夜晚"


func _action_kind(action_type: String) -> String:
	return {
		"dialogue": "对话",
		"clue": "调查",
		"normal": "行动",
		"relationship": "关系",
		"military": "职责",
		"rumor": "传闻",
	}.get(action_type, "行动")


func _action_hint(option: Dictionary) -> String:
	var mode := str(option.get("transaction_mode", ""))
	if mode == "candidate_only":
		return "记录选择，等待后续对话系统承接"
	return "由当前世界状态即时结算"


func _role_label(role: String) -> String:
	return {
		"traveler": "途经湖湾镇的旅人",
		"squadmate": "同队士兵",
	}.get(role, role)


func _status_label(key: String) -> String:
	return {
		"food_pressure": "粮食压力",
		"public_order": "街面秩序",
		"market_order": "市场状况",
		"local_guard_attention": "守卫关注",
	}.get(key, key)


func _status_detail(key: String, value: String) -> String:
	var details := {
		"food_pressure:high": "存粮正在收紧，价格和人心都受到了挤压。",
		"public_order:tense": "表面仍有秩序，但争执随时可能冒出来。",
		"market_order:tense": "商贩惜售，买粮的人不愿空手离开。",
		"local_guard_attention:medium": "守卫已经留意到异样，还没有正式介入。",
	}
	return str(details.get("%s:%s" % [key, value], "局势仍在变化。"))


func _state_value_label(value: String) -> String:
	return {
		"high": "高",
		"medium": "中等",
		"low": "低",
		"tense": "紧张",
		"stable": "稳定",
	}.get(value, value)


func _hunger_label(value: String) -> String:
	return {
		"extreme": "濒临极限",
		"high": "严重",
		"medium": "缓和",
		"low": "轻微",
	}.get(value, value)


func _fear_label(value: String) -> String:
	return {
		"high": "惊惧",
		"medium": "不安",
		"low": "放松",
	}.get(value, value)


func _location_tag_label(tag: String) -> String:
	return {
		"town": "湖湾镇",
		"shop": "旧粮铺",
		"food_related": "粮食相关",
		"local_family_business": "本地人经营",
	}.get(tag, "")


func _fact_text(fact_type: String, target_name: String) -> String:
	return {
		"actor_gave_food_to_target": "你给%s递过食物。" % target_name,
		"actor_asked_about_concealed_item": "你问过%s藏起来的东西。" % target_name,
		"actor_read_object": "你读过%s。" % target_name,
		"actor_inspected_trace": "你检查过%s。" % target_name,
		"actor_asked_about_market_pressure": "你确认湖湾镇正承受粮食压力。",
		"old_chen_shop_closed_early": "你亲眼看到老陈铺子提前收门，涨价告示也被再次改高。",
	}.get(fact_type, "你确认了一条与此地有关的事实。")


func _state_key_label(key: String) -> String:
	return {
		"hunger": "饥饿状态",
		"food_count": "食物数量",
	}.get(key, key)


func _relationship_axis_label(axis: String) -> String:
	return {
		"gratitude": "感激",
		"trust": "信任",
		"fear": "畏惧",
		"debt": "亏欠",
	}.get(axis, axis)


func _signed_number(value: int) -> String:
	return "+%d" % value if value > 0 else str(value)
