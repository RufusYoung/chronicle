extends RefCounted
class_name WorldSimLeadAdapter

const TYPE_MAP: Dictionary = {
	"smoke": "烟柱",
	"tracks": "足迹",
	"rumor": "传闻",
	"river": "河流",
	"apparition": "传闻",
	"checkpoint": "足迹",
	"caravan": "烟柱",
}

const V03_TYPE_MAP: Dictionary = {
	"smoke": "smoke",
	"tracks": "footprint",
	"rumor": "rumor",
	"river": "river",
	"apparition": "rumor",
	"checkpoint": "footprint",
	"caravan": "smoke",
}

const DIRECTION_BY_REGION: Dictionary = {
	"mirror_lake_forest": "西北",
	"border_town": "东南",
	"old_ruins": "北方",
}

const REGION_NAME_BY_ID: Dictionary = {
	"mirror_lake_forest": "镜湖森林",
	"border_town": "边境镇",
	"old_ruins": "旧日遗迹",
}

const FACTION_NAME_BY_ID: Dictionary = {
	"wardens": "镜湖守望者",
	"smugglers": "雾路走私团",
	"echo_cult": "回声教团",
}

const ACTION_NAME_BY_ID: Dictionary = {
	"investigate": "调查",
	"protect": "护送",
	"rob": "劫掠",
	"ignore": "放任",
	"observe": "观察",
	"interrupt": "打断",
	"follow": "跟随",
	"report": "报告",
	"hunt": "狩猎",
	"set_trap": "设陷",
	"warn_travelers": "警告旅人",
	"sample_water": "取水检验",
	"trace_upstream": "溯流追查",
	"warn_villagers": "提醒居民",
	"approach": "靠近",
	"scout": "侦察",
	"avoid": "绕行",
	"inform_wardens": "通知守望者",
	"cooperate": "配合盘查",
	"question": "询问",
	"bypass": "绕过关卡",
	"report_smuggling": "举报走私",
	"verify": "核实",
	"buy_information": "购买情报",
	"spread": "散播消息",
}


func adapt_lead_candidate(candidate: Dictionary) -> Dictionary:
	var world_cause := String(candidate.get("world_cause", ""))
	var related_fact_id := String(candidate.get("related_fact_id", ""))
	if world_cause == "" or related_fact_id == "":
		push_error("[WorldSimLeadAdapter] Lead is missing world_cause or related_fact_id")
		return {}

	var candidate_id := String(candidate.get("id", ""))
	var type_id := String(candidate.get("type", ""))
	var direction := map_direction(candidate)
	var freshness := map_freshness(candidate)
	var risk := map_risk(candidate)
	var title := map_title(candidate)
	var actions := map_action_hints(candidate)
	var target := _map_target(candidate)

	return {
		"id": candidate_id,
		"lead_id": candidate_id,
		"type": map_lead_type(type_id),
		"lead_type": String(V03_TYPE_MAP.get(type_id, "rumor")),
		"target": target,
		"target_dir_or_place": direction,
		"direction": direction,
		"stage": map_stage(candidate),
		"freshness": freshness,
		"freshness_percent": int(round(freshness * 100.0)),
		"risk": risk,
		"risk_hint": _map_risk_hint(risk),
		"source": map_source(candidate),
		"title": title,
		"description": _map_description(candidate),
		"possible_actions": actions,
		"action_ids": (candidate.get("possible_actions", []) as Array).duplicate(),
		"world_cause": world_cause,
		"related_fact_id": related_fact_id,
		"source_region_id": String(candidate.get("region_id", "")),
		"source_faction_id": String(candidate.get("source_faction_id", "")),
		"origin": "world_sim",
	}


func adapt_lead_candidates(candidates: Array) -> Array:
	var adapted: Array[Dictionary] = []
	for candidate_value: Variant in candidates:
		if not candidate_value is Dictionary:
			push_warning("[WorldSimLeadAdapter] Ignored non-Dictionary candidate")
			continue
		var result := adapt_lead_candidate(candidate_value as Dictionary)
		if not result.is_empty():
			adapted.append(result)
	return adapted


func map_lead_type(type_id: String) -> String:
	if not TYPE_MAP.has(type_id):
		push_warning("[WorldSimLeadAdapter] Unknown lead type: %s" % type_id)
	return String(TYPE_MAP.get(type_id, "传闻"))


func map_direction(candidate: Dictionary) -> String:
	var explicit_direction := String(candidate.get("direction", ""))
	if explicit_direction != "":
		return explicit_direction
	var region_id := String(candidate.get("region_id", ""))
	return String(DIRECTION_BY_REGION.get(region_id, "附近"))


func map_stage(candidate: Dictionary) -> int:
	if candidate.has("urgency"):
		var urgency := _normalize_ratio(candidate.get("urgency", 0.0), 0.0)
		if urgency < 0.35:
			return 1
		if urgency < 0.7:
			return 2
		return 3

	var freshness := map_freshness(candidate)
	var risk := map_risk(candidate)
	if risk >= 0.7 and freshness >= 0.7:
		return 3
	if risk >= 0.5 or freshness >= 0.6:
		return 2
	return 1


func map_freshness(candidate: Dictionary) -> float:
	return _normalize_ratio(candidate.get("freshness", 0.8), 0.8)


func map_risk(candidate: Dictionary) -> float:
	return _normalize_ratio(candidate.get("risk", 0.5), 0.5)


func map_title(candidate: Dictionary) -> String:
	var cause := String(candidate.get("world_cause", ""))
	match cause:
		"scarcity_high_and_smuggler_raid":
			return "远处商队烟迹"
		"cult_ritual_and_mystic_pressure":
			return "关于旧遗迹异象的传闻"
		"order_collapse_and_forest_conflict":
			return "林间冲突升起的烟柱"
		"beast_migration":
			return "林中迁徙足迹"
		"resource_pressure_along_lake_routes":
			return "河岸资源异动"
		"warden_security_response":
			return "道旁新设的盘查痕迹"
		"smuggler_information_market":
			return "镇上的低声传闻"

	var mapped_type := map_lead_type(String(candidate.get("type", "")))
	return "%s线索" % mapped_type


func map_source(candidate: Dictionary) -> String:
	var faction_id := String(candidate.get("source_faction_id", ""))
	if faction_id != "":
		return String(FACTION_NAME_BY_ID.get(faction_id, faction_id))
	var region_id := String(candidate.get("region_id", ""))
	return String(REGION_NAME_BY_ID.get(region_id, "世界状态"))


func map_action_hints(candidate: Dictionary) -> Array:
	var mapped: Array[String] = []
	for action_value: Variant in candidate.get("possible_actions", []):
		var action_id := String(action_value)
		if ACTION_NAME_BY_ID.has(action_id):
			mapped.append(String(ACTION_NAME_BY_ID[action_id]))
		else:
			push_warning("[WorldSimLeadAdapter] Unknown action: %s" % action_id)
			mapped.append("谨慎查看")
	if mapped.is_empty():
		mapped.append("谨慎查看")
	return mapped


func _normalize_ratio(value: Variant, default_value: float) -> float:
	if not value is float and not value is int:
		return default_value
	var normalized := float(value)
	if normalized > 1.0:
		normalized /= 100.0
	return clampf(normalized, 0.0, 1.0)


func _map_risk_hint(risk: float) -> String:
	if risk < 0.35:
		return "低风险"
	if risk < 0.7:
		return "中风险"
	return "高风险"


func _map_target(candidate: Dictionary) -> String:
	var cause := String(candidate.get("world_cause", ""))
	match cause:
		"scarcity_high_and_smuggler_raid":
			return "商队烟迹"
		"cult_ritual_and_mystic_pressure":
			return "旧遗迹异象"
		"order_collapse_and_forest_conflict":
			return "森林冲突地点"
		"beast_migration":
			return "迁徙兽群"
		"resource_pressure_along_lake_routes":
			return "河岸资源痕迹"
		"warden_security_response":
			return "新设关卡"
		"smuggler_information_market":
			return "情报来源"
	return map_title(candidate)


func _map_description(candidate: Dictionary) -> String:
	var cause := String(candidate.get("world_cause", ""))
	match cause:
		"scarcity_high_and_smuggler_raid":
			return "匮乏加剧后，商队补给遭到走私者袭击。"
		"cult_ritual_and_mystic_pressure":
			return "教团仪式推高神秘压力，遗迹附近出现异象。"
		"order_collapse_and_forest_conflict":
			return "森林秩序下降，冲突留下了可见烟迹。"
		"beast_migration":
			return "兽群密度上升，迁徙足迹穿过林地。"
		"resource_pressure_along_lake_routes":
			return "草药消耗与神秘压力在河岸留下异常。"
		"warden_security_response":
			return "守望者加强安保，道路出现新的盘查痕迹。"
		"smuggler_information_market":
			return "走私情报交易活跃，镇上流言开始聚集。"
	return "世界状态变化留下了一条可追查线索。"
