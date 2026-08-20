extends RefCounted
class_name V5RoutePressureQuery


func active_pressure(
		snapshot: Variant, link_id: String, day: int
) -> Dictionary:
	var latest: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", ""))
			!= "regional_route_pressure_started"
			or str(fact.get("link_id", "")) != link_id
			or int(fact.get("start_day", 0)) > day
			or int(fact.get("until_day", 0)) < day
		):
			continue
		if latest.is_empty() or int(fact.get("start_day", 0)) > int(
			latest.get("start_day", 0)
		):
			latest = fact
	if latest.is_empty():
		return {
			"risk_increase": 0,
			"capacity_penalty": 0.0,
			"source_fact_ids": [],
		}
	return {
		"risk_increase": maxi(int(latest.get("risk_increase", 0)), 0),
		"capacity_penalty": maxf(float(latest.get(
			"capacity_penalty", 0.0
		)), 0.0),
		"source_fact_ids": [str(latest.get("fact_id", ""))],
		"fact_id": str(latest.get("fact_id", "")),
		"cause_id": str(latest.get("cause_id", "")),
		"summary": str(latest.get("summary", "")),
		"start_day": int(latest.get("start_day", 0)),
		"until_day": int(latest.get("until_day", 0)),
	}


func latest_start_day(snapshot: Variant, link_id: String, before_day: int) -> int:
	var latest_day := 0
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", ""))
			== "regional_route_pressure_started"
			and str(fact.get("link_id", "")) == link_id
			and int(fact.get("start_day", 0)) < before_day
		):
			latest_day = maxi(latest_day, int(fact.get("start_day", 0)))
	return latest_day
