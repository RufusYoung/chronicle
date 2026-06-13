extends RefCounted
class_name WorldNewsDigest

const DEFAULT_COOLDOWN_DAYS := 3

const WORLD_CAUSE_BY_ACTION: Dictionary = {
	"patrol": "warden_security_response",
	"suppress_smugglers": "warden_security_response",
	"seal_ruins": "cult_ritual_and_mystic_pressure",
	"escort_supplies": "scarcity_high_and_smuggler_raid",
	"raid_supplies": "scarcity_high_and_smuggler_raid",
	"bribe_guards": "smuggler_information_market",
	"spread_rumor": "smuggler_information_market",
	"move_contraband": "smuggler_information_market",
	"gather_relics": "cult_ritual_and_mystic_pressure",
	"harvest_herbs": "resource_pressure_along_lake_routes",
	"perform_ritual": "cult_ritual_and_mystic_pressure",
	"spread_visions": "cult_ritual_and_mystic_pressure",
}


func record_action(
		state: WorldSimState,
		fact: WorldSimState.WorldFact,
		source: String,
		base_summary: String
	) -> WorldSimState.WorldNews:
	var action_type := fact.type
	var world_cause := String(
		WORLD_CAUSE_BY_ACTION.get(action_type, action_type)
	)
	var news_key := build_news_key(
		fact.region_id,
		fact.faction_id,
		action_type,
		world_cause
	)
	var history := _history_for(
		state,
		news_key,
		fact,
		source,
		action_type,
		world_cause
	)
	var previous_stage := int(history.get("stage", 0))
	var previous_severity := String(history.get("severity", "normal"))
	var count := int(history.get("count", 0)) + 1
	var stage := _count_stage(count)
	var severity := _severity_for(state, action_type, fact.region_id)

	history["last_day"] = state.day
	history["count"] = count
	history["last_fact_id"] = fact.id
	history["stage"] = stage
	history["severity"] = severity
	var related_fact_ids := history.get("related_fact_ids", []) as Array
	related_fact_ids.append(fact.id)
	history["related_fact_ids"] = related_fact_ids
	state.news_history[news_key] = history

	var last_published_day := int(history.get("last_published_day", -999))
	var cooldown_elapsed := state.day - last_published_day >= DEFAULT_COOLDOWN_DAYS
	var stage_changed := stage > previous_stage
	var severity_changed := (
		_severity_rank(severity) > _severity_rank(previous_severity)
	)
	var should_publish := (
		count == 1
		or stage_changed
		or severity_changed
	)
	if not should_publish:
		return null
	if not cooldown_elapsed and not stage_changed and not severity_changed:
		return null

	var summary := _stage_text(
		action_type,
		count,
		stage,
		severity,
		base_summary
	)
	history["last_published_day"] = state.day
	history["last_text"] = summary
	state.news_history[news_key] = history
	return state.add_news(
		fact.region_id,
		source,
		summary,
		0.9,
		fact.id,
		{
			"news_key": news_key,
			"stage": stage,
			"occurrence_count": count,
			"world_cause": world_cause,
			"related_fact_ids": related_fact_ids.duplicate(),
			"kind": "stage_news",
		}
	)


func record_immediate(
		state: WorldSimState,
		fact: WorldSimState.WorldFact,
		source: String,
		summary: String,
		world_cause: String,
		key_suffix: String = ""
	) -> WorldSimState.WorldNews:
	var suffix := key_suffix if key_suffix != "" else fact.id
	var news_key := build_news_key(
		fact.region_id,
		fact.faction_id,
		fact.type,
		"%s|%s" % [world_cause, suffix]
	)
	var history := state.news_history.get(news_key, {}) as Dictionary
	var count := int(history.get("count", 0)) + 1
	var related_fact_ids := history.get("related_fact_ids", []) as Array
	related_fact_ids.append(fact.id)
	var published_summary := summary
	if count > 1:
		published_summary = "%s（第 %d 次进入该状态）" % [summary, count]
	history = {
		"news_key": news_key,
		"region_id": fact.region_id,
		"actor_faction_id": fact.faction_id,
		"source": source,
		"action_type": fact.type,
		"world_cause": world_cause,
		"first_day": int(history.get("first_day", state.day)),
		"last_day": state.day,
		"last_published_day": state.day,
		"count": count,
		"last_fact_id": fact.id,
		"related_fact_ids": related_fact_ids,
		"stage": _count_stage(count),
		"severity": "immediate",
		"last_text": published_summary,
	}
	state.news_history[news_key] = history
	return state.add_news(
		fact.region_id,
		source,
		published_summary,
		1.0,
		fact.id,
		{
			"news_key": news_key,
			"stage": int(history.get("stage", 1)),
			"occurrence_count": count,
			"world_cause": world_cause,
			"related_fact_ids": related_fact_ids.duplicate(),
			"kind": "immediate_news",
		}
	)


func build_news_key(
		region_id: String,
		actor_faction_id: String,
		action_type: String,
		world_cause: String
	) -> String:
	return "%s|%s|%s|%s" % [
		region_id,
		actor_faction_id,
		action_type,
		world_cause,
	]


func build_continuous_summaries(
		state: WorldSimState,
		limit: int = 3
	) -> Array:
	var candidates: Array[Dictionary] = []
	for news_key_value: Variant in state.news_history:
		var news_key := String(news_key_value)
		var history := state.news_history.get(news_key, {}) as Dictionary
		var count := int(history.get("count", 0))
		if count < 2:
			continue
		if state.day - int(history.get("last_day", 0)) > DEFAULT_COOLDOWN_DAYS:
			continue
		var action_type := String(history.get("action_type", ""))
		candidates.append({
			"news_key": news_key,
			"region_id": String(history.get("region_id", "")),
			"source": String(history.get("source", "")),
			"action_type": action_type,
			"world_cause": String(history.get("world_cause", "")),
			"count": count,
			"stage": int(history.get("stage", 0)),
			"last_day": int(history.get("last_day", 0)),
			"summary": _continuous_text(action_type, count),
			"priority": (
				int(history.get("stage", 0)) * 100
				+ count
				+ int(history.get("last_day", 0))
			),
		})
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("priority", 0)) > int(b.get("priority", 0))
	)
	var output: Array[Dictionary] = []
	for index: int in range(mini(limit, candidates.size())):
		var summary := candidates[index].duplicate(true)
		summary.erase("priority")
		output.append(summary)
	return output


func _history_for(
		state: WorldSimState,
		news_key: String,
		fact: WorldSimState.WorldFact,
		source: String,
		action_type: String,
		world_cause: String
	) -> Dictionary:
	if state.news_history.has(news_key):
		return state.news_history[news_key] as Dictionary
	return {
		"news_key": news_key,
		"region_id": fact.region_id,
		"actor_faction_id": fact.faction_id,
		"source": source,
		"action_type": action_type,
		"world_cause": world_cause,
		"first_day": state.day,
		"last_day": state.day,
		"last_published_day": -999,
		"count": 0,
		"last_fact_id": "",
		"related_fact_ids": [],
		"stage": 0,
		"severity": "normal",
		"last_text": "",
	}


func _count_stage(count: int) -> int:
	if count >= 20:
		return 5
	if count >= 10:
		return 4
	if count >= 5:
		return 3
	if count >= 3:
		return 2
	return 1


func _severity_for(
		state: WorldSimState,
		action_type: String,
		region_id: String
	) -> String:
	var region := state.get_region(region_id)
	if region == null:
		return "normal"
	match action_type:
		"raid_supplies":
			if region.food <= 15.0 or region.scarcity >= 95.0:
				return "critical"
			if region.food <= 35.0 or region.scarcity >= 80.0:
				return "high"
		"suppress_smugglers":
			if region.order <= 20.0:
				return "critical"
			if region.information >= 85.0:
				return "high"
		"escort_supplies":
			if region.food <= 15.0 or region.scarcity >= 95.0:
				return "critical"
			if region.scarcity >= 80.0:
				return "high"
		"gather_relics", "perform_ritual", "spread_visions":
			if region.mystic >= 95.0:
				return "critical"
			if region.mystic >= 80.0:
				return "high"
		"harvest_herbs":
			if region.herbs <= 45.0:
				return "critical"
			if region.herbs <= 65.0:
				return "high"
	return "normal"


func _severity_rank(severity: String) -> int:
	match severity:
		"critical":
			return 3
		"high":
			return 2
		"immediate":
			return 1
	return 0


func _stage_text(
		action_type: String,
		count: int,
		stage: int,
		severity: String,
		base_summary: String
	) -> String:
	match action_type:
		"raid_supplies":
			if severity == "critical":
				return "补给线已遇袭 %d 次，边境镇粮食接近见底。" % count
			if severity == "high":
				return "补给线已遇袭 %d 次，边境镇的空货架越来越多。" % count
			if stage >= 4:
				return "补给线已遭袭 %d 次，粮车只能改走更危险的路线。" % count
			if stage >= 3:
				return "走私者控制了部分暗线，镇上粮价继续上涨。"
			if stage >= 2:
				return "边境镇外的补给线多次遇袭，粮车开始绕路。"
		"suppress_smugglers":
			if severity == "critical":
				return "第 %d 次清剿后，边境镇秩序仍跌入危险线。" % count
			if severity == "high":
				return "清剿累计 %d 次，走私者转入暗线，镇上传闻更多了。" % count
			if stage >= 4:
				return "守望者已发动 %d 次清剿，路口盘查成为常态。" % count
			if stage >= 3:
				return "走私者转入暗线，镇上公开冲突减少但传闻增多。"
			if stage >= 2:
				return "守望者连续清剿走私据点，路口盘查变多。"
		"escort_supplies":
			if severity == "critical":
				return "已护送 %d 批粮车，但补给速度仍追不上消耗。" % count
			if severity == "high":
				return "已护送 %d 批粮车，边境镇的粮食压力仍未解除。" % count
			if stage >= 3:
				return "护粮行动已成常态，守望者的仓储与财力开始吃紧。"
			if stage >= 2:
				return "多批粮车在守望者护送下进入边境镇。"
		"gather_relics":
			if severity == "critical":
				return "教团第 %d 次带出遗物，遗迹神秘压力接近失控。" % count
			if severity == "high":
				return "教团已 %d 次带出遗物，遗迹附近的回声越发密集。" % count
			if stage >= 3:
				return "回声教团持续搬运遗物，遗迹深处开始出现空洞回响。"
			if stage >= 2:
				return "旧日遗迹附近的夜间回声越来越频繁。"
		"perform_ritual":
			if severity == "critical":
				return "教团已举行 %d 次仪式，遗迹神秘压力接近失控。" % count
			if severity == "high":
				return "教团已举行 %d 次仪式，遗迹上空的回声持续整夜。" % count
			if stage >= 3:
				return "回声教团的仪式形成固定节律，异象开始向外扩散。"
			if stage >= 2:
				return "旧日遗迹附近的夜间回声越来越频繁。"
		"spread_visions":
			if severity == "critical":
				return "异梦已传播 %d 次，旧日遗迹的压力接近失控。" % count
			if stage >= 3:
				return "越来越多镇民梦见倒悬湖面，白日里也有人听见回声。"
			if stage >= 2:
				return "镇民反复梦见同一片倒悬的湖面。"
		"harvest_herbs":
			if severity == "critical":
				return "草药已被集中采集 %d 次，短缺开始影响伤病治疗。" % count
			if severity == "high":
				return "草药已被集中采集 %d 次，采药人开始深入危险地带。" % count
			if stage >= 3:
				return "草药短缺开始影响镇上的伤病治疗。"
			if stage >= 2:
				return "湖岸药草变少，采药人开始深入危险地带。"
		"move_contraband":
			if stage >= 3:
				return "隐蔽商路已形成固定网络，走私货物持续穿过地区。"
			if stage >= 2:
				return "走私货物多次沿隐蔽路线穿过地区。"
		"spread_rumor", "bribe_guards":
			if stage >= 3:
				return "边境镇的情报交易已成暗市，真假消息混在一起。"
			if stage >= 2:
				return "关于粮价与守望者的传闻持续累积。"
	return base_summary


func _continuous_text(action_type: String, count: int) -> String:
	match action_type:
		"raid_supplies":
			return "走私者袭击补给线已持续 %d 次，边境镇粮食压力仍在升高。" % count
		"suppress_smugglers":
			return "守望者清剿走私据点已持续 %d 次，盘查与暗线活动同时增加。" % count
		"escort_supplies":
			return "守望者已护送 %d 批补给，粮食危机仍未完全缓解。" % count
		"gather_relics", "perform_ritual", "spread_visions":
			return "回声教团的相关活动已持续 %d 次，旧日遗迹神秘压力维持高位。" % count
		"harvest_herbs":
			return "森林草药采集已持续 %d 次，湖岸资源压力继续累积。" % count
		"move_contraband", "spread_rumor", "bribe_guards":
			return "走私网络活动已持续 %d 次，边境镇情报与秩序持续波动。" % count
	return "%s 已连续发生 %d 次。" % [action_type, count]
