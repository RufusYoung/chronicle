extends RefCounted

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")


static func resolve(snapshot: Variant, tick: Dictionary, config: Dictionary) -> Variant:
	var result := Result.new()
	var rule: Dictionary = config.get("foraging", {})
	if rule.is_empty():
		return result
	var now := int(tick.day) * 24 + int(tick.hour)
	var used := {}
	for threat: Dictionary in snapshot.get_entities_by_type("creature"):
		if "world_threat" not in threat.get("tags", []) or not threat.states.get("alive", false) \
				or int(threat.states.get("health", 0)) <= int(config.threat.retreat_health) \
				or int(threat.states.get("danger_retreat_until", 0)) > now \
				or int(tick.hour) < int(config.threat.start_hour) or int(tick.hour) >= int(config.threat.end_hour):
			continue
		var elapsed := mini(int(threat.states.get("threat_foraging_hours", 0)) + 1, int(rule.work_hours))
		var stock: Dictionary = {}
		for candidate: Dictionary in snapshot.get_resource_stocks():
			if candidate.get("location_id") == threat.states.get("location_id") and candidate.get("source_kind") == "natural_resource" \
					and rule.resource_tags_all.all(func(tag: String) -> bool: return tag in candidate.get("tags", [])) \
					and float(candidate.current) - float(used.get(candidate.stock_id, 0)) >= float(rule.amount):
				stock = candidate
				break
		if elapsed >= int(rule.work_hours) and not stock.is_empty():
			var fact_id := "fact.threat_fed.%s.%d" % [threat.id, now]
			var sources: Array = stock.get("last_source_fact_ids", []).duplicate()
			if stock.get("established_fact_id", "") != "":
				sources.append(str(stock.established_fact_id))
			result.add_fact({"fact_id": fact_id, "fact_type": "world_threat_fed", "actor_id": threat.id,
				"day": tick.day, "hour": tick.hour, "location_id": threat.states.location_id, "stock_id": stock.stock_id,
				"amount": rule.amount, "sated_until": now + int(rule.sated_hours), "source_fact_ids": sources,
				"summary": "%s在田边觅食，消耗了%.2f份当地可采资源，随后退入灌丛休息；余下资源暂时可以采收。" % [threat.display_name, float(rule.amount)]})
			result.add_resource_change({"operation": "consume", "stock_id": stock.stock_id, "amount": rule.amount,
				"actor_id": threat.id, "tick": now, "day": tick.day, "reason": "wildlife_foraging", "source_fact_ids": [fact_id]})
			used[stock.stock_id] = float(used.get(stock.stock_id, 0)) + float(rule.amount)
			result.add_state_change({"entity_id": threat.id, "key": "danger_retreat_until", "to": now + int(rule.sated_hours)})
			elapsed = 0
		result.add_state_change({"entity_id": threat.id, "key": "threat_foraging_hours", "to": elapsed})
	result.mark_resolved("threat_subsistence")
	return result
