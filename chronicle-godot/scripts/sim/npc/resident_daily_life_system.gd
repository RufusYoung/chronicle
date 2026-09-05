extends RefCounted
class_name V5ResidentDailyLifeSystem

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Industry = preload("res://scripts/sim/settlement/industry_runtime_catalog.gd")
const FoodAccess = preload("res://scripts/sim/economy/resident_food_access.gd")
const FamilyFood = preload("res://scripts/sim/npc/household_provisioning.gd")
const STATE_KEYS := ["daily_life_version", "daily_activity", "daily_activity_reason", "daily_goal_id",
	"daily_workplace_id", "daily_route_id", "daily_destination_id", "daily_travel_remaining",
	"daily_departure_fact_id", "daily_presence_fact_id"]

const PROFILE := {"version": 1, "work_start_hour": 6, "work_end_hour": 18,
	"minimum_work_health": 30, "rest_fatigue": 7, "resume_fatigue": 2, "home_walk_hours": 1,
	"night_occupations": ["watch_hand"]}


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func work_time(occupation: String, hour: int, config: Dictionary) -> bool:
	var daylight := hour > int(config.get("work_start_hour", 6)) and hour <= int(config.get("work_end_hour", 18))
	return not daylight if occupation in config.get("night_occupations", []) else daylight


func resolve_tick(snapshot: Variant, tick: Dictionary, config: Dictionary,
		network: Dictionary, locations: Dictionary, base_routes: Array, profiles: Array = []) -> Dictionary:
	if not enabled(config) or int(tick.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var routes := _routes(snapshot, network, locations, base_routes, config)
	var result = Result.new()
	var events: Array = []
	var people: Array = snapshot.get_entities_by_type("person")
	var food_config: Dictionary = config.get("food_access", {})
	var food_items: Array = snapshot.get_items() if FoodAccess.enabled(food_config) else []
	var known_supply_cache := {}
	people.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for actor: Dictionary in people:
		if "generated_resident" not in actor.get("tags", []):
			continue
		var id := str(actor.id)
		var states: Dictionary = actor.get("states", {})
		if not bool(states.get("alive", true)):
			continue
		_change(result, id, states, "daily_life_version", 1)
		var location := str(states.get("location_id", ""))
		var home := str(states.get("home_location_id", ""))
		var workplace := str(states.get("workplace_id", ""))
		# Partial production belongs to a workplace, not to a transferable timer.
		if str(states.get("daily_workplace_id", "")) != workplace:
			_change(result, id, states, "daily_workplace_id", workplace)
			_change(result, id, states, "livelihood_elapsed_hours", 0)
		if str(states.get("daily_route_id", "")) != "":
			_progress_journey(result, events, actor, states, routes, locations, tick)
			continue
		var fatigue := int(states.get("fatigue", 0))
		var must_rest := int(states.get("health", 100)) < int(config.get("minimum_work_health", 30)) \
			or fatigue >= int(config.get("rest_fatigue", 7)) \
			or (str(states.get("daily_activity", "")) == "resting" and fatigue > int(config.get("resume_fatigue", 2)))
		var hour := int(tick.get("hour", 0))
		var on_shift := work_time(str(states.get("occupation_id", "")), hour, config)
		var worker := str(states.get("livelihood_status", "")) in ["employed", "self_employed"]
		var goal := home
		var activity := "home"
		var reason := "日常在家"
		var decision_sources: Array = []
		if must_rest or not on_shift:
			activity = "resting"
			reason = "身体需要休息" if must_rest else "班次结束，回家休息"
		elif worker and workplace != "" and workplace != home:
			goal = workplace
			activity = "working"
			reason = "到岗谋生"
		elif str(states.get("livelihood_status", "")) == "unemployed" and hour >= 9 and hour <= 16:
			goal = _hub(network, str(states.get("settlement_id", "")))
			activity = "seeking_work"
			reason = "前往集地寻找工作"
		if FoodAccess.enabled(food_config) and not must_rest:
			var family := FamilyFood.request(snapshot, actor, tick, food_config.get("household_provisioning", {}))
			var carried := FoodAccess.food_quantity(food_items, id)
			var supply := _food_goal(snapshot, actor, routes, profiles, tick, food_config, network, locations, food_items, known_supply_cache, family)
			if supply != "":
				goal = supply
				activity = "seeking_food"
				reason = "没有口粮，带钱寻找已知供给" if family.is_empty() else "记得%s缺粮，带自己的钱去采购" % family.names
				decision_sources = family.get("source_fact_ids", [])
			if not family.is_empty() and carried > 0:
				goal = str(family.home_location_id)
				activity = "home"
				reason = "给%s带粮回家" % family.names
				decision_sources = family.source_fact_ids
		_change(result, id, states, "daily_goal_id", goal)
		if goal == "" or not locations.has(goal):
			_transition(result, events, actor, states, "blocked", "没有可到达的去处", tick)
			continue
		if goal != location:
			var route := _next_edge(routes, location, goal)
			if route.is_empty():
				_transition(result, events, actor, states, "blocked", "通往目的地的路不通", tick)
				_change(result, id, states, "visible", _public_place(locations, location))
				continue
			_change(result, id, states, "daily_route_id", str(route.route_id))
			_change(result, id, states, "daily_destination_id", str(route.to_location_id))
			_change(result, id, states, "daily_travel_remaining", int(route.hours))
			_change(result, id, states, "visible", false)
			var journey := {
				"route_id": route.route_id, "from_location_id": location,
				"to_location_id": route.to_location_id, "goal_location_id": goal,
				"travel_hours": route.hours}
			if not decision_sources.is_empty():
				journey["source_fact_ids"] = decision_sources
			var fact := _transition(result, events, actor, states, "traveling", reason, tick, journey)
			_change(result, id, states, "daily_departure_fact_id", fact)
			continue
		_transition(result, events, actor, states, activity, reason, tick,
			{"source_fact_ids": decision_sources} if not decision_sources.is_empty() else {})
		_change(result, id, states, "visible", _public_place(locations, location))
		if activity == "resting" and fatigue > 0:
			_change(result, id, states, "fatigue", fatigue - 1)
	if result.is_empty():
		return {"results": [], "events": []}
	result.mark_resolved("resident_daily_life")
	return {"results": [result], "events": events}


func _progress_journey(result: Variant, events: Array, actor: Dictionary, states: Dictionary,
		routes: Array, locations: Dictionary, tick: Dictionary) -> void:
	var id := str(actor.id)
	var route_id := str(states.get("daily_route_id", ""))
	var route: Dictionary = {}
	for candidate: Dictionary in routes:
		if str(candidate.route_id) == route_id:
			route = candidate
			break
	var location := str(states.get("location_id", ""))
	if not route.is_empty() and str(route.get("from_location_id", "")) != location:
		_change(result, id, states, "daily_route_id", "")
		_change(result, id, states, "daily_travel_remaining", 0)
		_change(result, id, states, "visible", _public_place(locations, location))
		_transition(result, events, actor, states, "blocked", "途中通路或出发位置已改变，停止行程", tick,
			{"route_id": route_id, "source_fact_ids": [str(states.get("daily_departure_fact_id", ""))]})
		return
	if route.is_empty() or int(states.get("health", 100)) <= 0:
		_change(result, id, states, "visible", false)
		_transition(result, events, actor, states, "blocked", "途中受阻，尚未抵达", tick,
			{"route_id": route_id, "source_fact_ids": [str(states.get("daily_departure_fact_id", ""))]})
		return
	var remaining := maxi(int(states.get("daily_travel_remaining", 1)) - 1, 0)
	_change(result, id, states, "daily_travel_remaining", remaining)
	if remaining > 0:
		_transition(result, events, actor, states, "traveling", "继续尚未走完的路", tick)
		return
	var destination := str(route.to_location_id)
	_change(result, id, states, "location_id", destination)
	_change(result, id, states, "daily_route_id", "")
	_change(result, id, states, "visible", _public_place(locations, destination))
	var fact := _transition(result, events, actor, states, "arrived", "刚刚抵达", tick, {
		"location_id": destination, "from_location_id": location, "to_location_id": destination,
		"route_id": route_id, "travel_hours": route.hours,
		"source_fact_ids": [str(states.get("daily_departure_fact_id", ""))]})
	_change(result, id, states, "daily_presence_fact_id", fact)


func _routes(snapshot: Variant, network: Dictionary, locations: Dictionary,
		base_routes: Array, config: Dictionary) -> Array:
	var source := base_routes.duplicate()
	source.append_array(Industry.routes(snapshot))
	var home_ids := locations.keys()
	home_ids.sort()
	for home_id: String in home_ids:
		var home: Dictionary = locations[home_id]
		if "home" not in home.get("tags", []):
			continue
		var hub := _hub(network, str(home.get("settlement_id", "")))
		if hub == "" or hub == home_id:
			continue
		for edge: Array in [[home_id, hub], [hub, home_id]]:
			source.append({"route_id": "resident_path.%s.%s" % [edge[0], edge[1]],
				"from_location_id": edge[0], "to_location_id": edge[1],
				"hours": maxi(int(config.get("home_walk_hours", 1)), 1)})
	var routes: Array = []
	for route: Dictionary in source:
		if bool(route.get("enabled", true)) and int(route.get("hours", 0)) > 0 \
				and locations.has(str(route.get("from_location_id", ""))) \
				and locations.has(str(route.get("to_location_id", ""))):
			routes.append(route)
	routes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.route_id) < str(b.route_id))
	return routes


func _next_edge(routes: Array, start: String, goal: String) -> Dictionary:
	var costs := {start: 0}
	var first_edges := {}
	var visited := {}
	while true:
		var next := ""
		for node: String in costs:
			if not visited.has(node) and (next == "" or int(costs[node]) < int(costs[next]) \
					or (int(costs[node]) == int(costs[next]) and node < next)):
				next = node
		if next == "":
			return {}
		if next == goal:
			var edge: Dictionary = first_edges.get(next, {}).duplicate()
			if not edge.is_empty():
				edge["total_hours"] = int(costs[next])
			return edge
		visited[next] = true
		for edge: Dictionary in routes:
			if str(edge.from_location_id) != next:
				continue
			var target := str(edge.to_location_id)
			var cost := int(costs[next]) + int(edge.hours)
			if not costs.has(target) or cost < int(costs[target]):
				costs[target] = cost
				first_edges[target] = edge if next == start else first_edges[next]
	return {}


func _food_goal(snapshot: Variant, actor: Dictionary, routes: Array, profiles: Array,
		tick: Dictionary, config: Dictionary, network: Dictionary, locations: Dictionary,
		items: Array, known_supply_cache: Dictionary, family: Dictionary = {}) -> String:
	var hour := int(tick.get("hour", 0))
	if (not FoodAccess.needs_food(actor, items) and family.is_empty()) or FoodAccess.balance(items, str(actor.id)) <= 0:
		return ""
	var states: Dictionary = actor.get("states", {})
	var location := str(states.get("location_id", ""))
	if int(states.get("age_years", 0)) < int(config.get("minimum_independent_shopping_age", 18)):
		return ""
	var own_settlement := str(states.get("settlement_id", ""))
	var away := str(locations.get(location, {}).get("settlement_id", own_settlement)) != own_settlement
	if not away and (hour < int(config.get("shopping_start_hour", 12)) or hour > int(config.get("shopping_end_hour", 17))):
		return ""
	# A food producer can satisfy this need by continuing real production.
	for profile: Dictionary in profiles:
		if str(profile.get("workplace_id", "")) == str(states.get("workplace_id", "")) \
				and str(profile.get("occupation_id", "")) == str(states.get("occupation_id", "")) \
				and FoodAccess.is_food_producer(profile):
			return ""
	if not known_supply_cache.has(own_settlement):
		known_supply_cache[own_settlement] = FoodAccess.known_supply_locations(snapshot, actor, profiles, network, config)
	for site: String in known_supply_cache[own_settlement]:
		if FoodAccess.known_unaffordable(snapshot, str(actor.id), site, FoodAccess.balance(items, str(actor.id)), tick, config):
			continue
		if site == location:
			return site
		if FoodAccess.recently_failed(snapshot, str(actor.id), site, tick, config):
			continue
		var edge := _next_edge(routes, location, site)
		if not edge.is_empty() and (family.is_empty() or int(edge.total_hours) <= int(family.travel_hours)):
			return site
	return ""


func _hub(network: Dictionary, settlement: String) -> String:
	for site: Dictionary in network.get("sites", []):
		if str(site.get("settlement_id", "")) == settlement:
			return str(site.get("hub_location_id", ""))
	return ""


func _public_place(locations: Dictionary, id: String) -> bool:
	return locations.has(id) and "home" not in locations[id].get("tags", [])


func _change(result: Variant, id: String, states: Dictionary, key: String, value: Variant) -> void:
	if states.get(key) != value:
		result.add_state_change({"entity_id": id, "key": key, "to": value})


func _transition(result: Variant, events: Array, actor: Dictionary, states: Dictionary,
		activity: String, reason: String, tick: Dictionary, extra: Dictionary = {}) -> String:
	if str(states.get("daily_activity", "")) == activity and str(states.get("daily_activity_reason", "")) == reason:
		return ""
	var id := str(actor.id)
	var fact_id := "fact.resident_activity.%s.%s" % [id, str(tick.get("tick_event_id", ""))]
	_change(result, id, states, "daily_activity", activity)
	_change(result, id, states, "daily_activity_reason", reason)
	var fact := {"fact_id": fact_id, "fact_type": "resident_activity_changed", "actor_id": id,
		"location_id": str(states.get("location_id", "")), "activity": activity, "reason": reason,
		"previous_activity": str(states.get("daily_activity", "home")),
		"day": int(tick.get("day", 0)), "hour": int(tick.get("hour", 0)),
		"summary": "%s：%s。" % [actor.get("display_name", id), reason]}
	fact.merge(extra, true)
	result.add_fact(fact)
	events.append(fact.duplicate(true))
	return fact_id
