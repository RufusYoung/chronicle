extends RefCounted
## Optional new-world rules. Existing saves keep their original travel and lodging contracts.

const PROFILE := {"version": 1, "rush_hours_saved": 1, "rush_fatigue_cost": 2,
	"bed_hourly_price": 1, "bed_durations": [1, 2, 4]}


static func enabled(fixture: Dictionary) -> bool:
	return fixture.get("journey_utility_rules", {}).get("version") == 1


static func validate(fixture: Dictionary) -> String:
	if not fixture.has("journey_utility_rules"):
		return ""
	var rules: Variant = fixture.journey_utility_rules
	if not rules is Dictionary or rules.size() != PROFILE.size() or fixture.get("situation_rules", {}).get("version") != 2:
		return "journey_utility_bootstrap_mismatch"
	for key: String in PROFILE:
		if key == "bed_durations":
			var durations: Variant = rules.get(key)
			if not durations is Array or durations.size() != PROFILE.bed_durations.size():
				return "journey_utility_bootstrap_mismatch"
			for index: int in range(durations.size()):
				if not _same_number(durations[index], int(PROFILE.bed_durations[index])):
					return "journey_utility_bootstrap_mismatch"
		elif not _same_number(rules.get(key), int(PROFILE[key])):
			return "journey_utility_bootstrap_mismatch"
	return ""


static func _same_number(value: Variant, expected: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == expected


static func walkable(fixture: Dictionary, route: Dictionary) -> bool:
	if int(route.get("hours", 0)) < 2:
		return false
	# Only explicit road links qualify; a ferry cannot be accelerated by walking harder.
	return fixture.get("settlement_network_generation_result", {}).get("links", []).any(func(link: Dictionary) -> bool:
		return link.get("link_id") == route.get("network_link_id", "") and link.get("mode") == "road")


static func rush_denial(session: Variant, route: Dictionary) -> String:
	if not enabled(session.fixture_source_data) or not walkable(session.fixture_source_data, route):
		return "这段路不能靠加快脚程缩短"
	var fatigue := int(session.get_snapshot().player.get("fatigue", 0))
	if fatigue + int(PROFILE.rush_fatigue_cost) + 1 > 10:
		return "体力不足以承担赶路和抵达的疲劳；仍可正常步行或先休息"
	return ""


static func options(session: Variant) -> Array:
	var rows: Array = []
	if not enabled(session.fixture_source_data):
		return rows
	for offer: Dictionary in session.get_travel_options():
		var matches: Array = session.travel_routes.filter(func(route: Dictionary) -> bool: return route.route_id == offer.route_id)
		if matches.is_empty() or not walkable(session.fixture_source_data, matches[0]):
			continue
		var denial := rush_denial(session, matches[0]) if offer.can_travel else str(offer.blocked_reason)
		var hours := int(offer.hours) - int(PROFILE.rush_hours_saved)
		rows.append({"action_id": "rush:" + str(offer.route_id), "event_type": "player_life", "action_type": "life",
			"life_group": "travel", "label": "加快脚程去%s" % offer.destination_name, "hours": hours,
			"route_id": offer.route_id, "destination_id": offer.to_location_id,
			"cost": "%d小时 / 额外%d疲劳" % [hours, PROFILE.rush_fatigue_cost],
			"known_effect": "同一条路提早1小时抵达；出发时额外消耗2体力，抵达仍增加1疲劳。",
			"hint": "不改变居民的行程，不保证赶得上某人；遇险仍会停下。",
			"tradeoff": "正常步行慢1小时但保留体力。疲劳超过7时无法再次加快脚程，可免费休息或付费住宿。",
			"can_execute": denial == "", "blocked_reason": denial})
	return rows
