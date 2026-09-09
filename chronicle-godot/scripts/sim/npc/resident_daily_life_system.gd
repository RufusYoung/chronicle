extends RefCounted
class_name V5ResidentDailyLifeSystem

const Result = preload("res://scripts/sim/transaction/transaction_result.gd")
const Industry = preload("res://scripts/sim/settlement/industry_runtime_catalog.gd")
const FoodAccess = preload("res://scripts/sim/economy/resident_food_access.gd")
const FamilyFood = preload("res://scripts/sim/npc/household_provisioning.gd")
const Carting = preload("res://scripts/sim/economy/resident_food_carting.gd")
const FoodStorage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Hauling = preload("res://scripts/sim/economy/household_food_hauling.gd")
const Assistance = preload("res://scripts/sim/npc/community_assistance.gd")
const Budget = preload("res://scripts/sim/economy/household_food_budget.gd")
const Subsistence = preload("res://scripts/sim/npc/resident_subsistence.gd")
const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")
const WorkOpportunities = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const CommunityLife = preload("res://scripts/sim/npc/community_life.gd")
const CommunityKnowledge = preload("res://scripts/sim/npc/community_knowledge.gd")
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
		network: Dictionary, locations: Dictionary, base_routes: Array, profiles: Array = [], registry: Variant = null) -> Dictionary:
	if not enabled(config) or int(tick.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var routes := _routes(snapshot, network, locations, base_routes, config)
	var result = Result.new()
	var events: Array = []
	var people: Array = snapshot.get_entities_by_type("person")
	var food_config: Dictionary = config.get("food_access", {})
	var food_items: Array = snapshot.get_items() if FoodAccess.enabled(food_config) else []
	var known_supply_cache := {}
	var choice_config: Dictionary = config.get("activity_choice", {})
	var use_choice := Choice.enabled(choice_config)
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
		var decision_intent := ""
		var proposals: Array = []
		var decision_evidence: Dictionary = {}
		if use_choice:
			Choice.propose(proposals, "home", home, "home", "暂时没有更值得赶去做的事")
		if must_rest or not on_shift:
			activity = "resting"
			reason = "身体需要休息" if must_rest else "班次结束，回家休息"
		elif worker and workplace != "" and workplace != home:
			goal = workplace
			activity = "working"
			reason = "到岗谋生"
			if location == workplace:
				for profile: Dictionary in profiles:
					if profile.get("occupation_id") == states.get("occupation_id") and profile.get("workplace_id") == workplace \
							and not FoodStorage.has_capacity(snapshot, id, profile, food_config.get("worksite_storage", {})):
						reason = "库存积压，暂停采收，等待取用或买家"
		elif str(states.get("livelihood_status", "")) == "unemployed" and hour >= 9 and hour <= 16:
			goal = _hub(network, str(states.get("settlement_id", "")))
			activity = "seeking_work"
			reason = "前往集地寻找工作"
		if use_choice:
			Choice.propose(proposals, "rest" if activity == "resting" else ("work" if activity == "working" else ("seek_work" if activity == "seeking_work" else "home")), goal, activity, reason)
			proposals.back()["mandatory_rest"] = must_rest
		if FoodAccess.enabled(food_config) and not must_rest:
			var family := FamilyFood.request(snapshot, actor, tick, food_config.get("household_provisioning", {}))
			if Budget.enabled(food_config.get("household_budget", {})):
				family = Budget.request(snapshot, actor, tick, food_config.household_budget)
			var haul_config: Dictionary = food_config.get("hauling", {})
			if Hauling.enabled(haul_config) and not family.is_empty():
				var sent := Hauling.assigned_targets(snapshot, id, tick)
				if family.targets.all(func(row: Dictionary) -> bool: return str(row.target_id) in sent):
					family = {}
			var carried := FoodAccess.food_quantity(food_items, id)
			var cart_config: Dictionary = food_config.get("carting", {})
			if Carting.is_carter(actor, cart_config) and on_shift:
				goal = Carting.stall_location(actor, network)
				if carried > int(cart_config.retained_portions):
					activity = "working"
					reason = "携粮到集散点，等待真实买家"
				else:
					var supplier := _food_goal(snapshot, actor, routes, profiles, tick, food_config, network, locations, food_items, known_supply_cache, {}, true)
					if supplier != "":
						goal = supplier
						activity = "seeking_food"
						reason = "自费收粮，带回集散点出售"
						decision_intent = "food_carting"
					else:
						activity = "seeking_work"
						reason = "周转钱或已知供货不足，暂不进货"
				if use_choice:
					Choice.propose(proposals, "cart", goal, activity, reason, decision_sources, decision_intent)
			var supply := _food_goal(snapshot, actor, routes, profiles, tick, food_config, network, locations, food_items, known_supply_cache, family)
			if supply != "":
				decision_intent = ""
				goal = supply
				activity = "seeking_food"
				reason = "没有口粮，带钱寻找已知供给" if family.is_empty() else "记得%s缺粮，带自己的钱去采购" % family.names
				decision_sources = family.get("source_fact_ids", []).duplicate()
				if CommunityKnowledge.enabled(food_config.get("community_rules", {})):
					decision_sources.append_array(CommunityKnowledge.sources_at(snapshot, id, supply, CommunityKnowledge.hour(tick)))
				if use_choice:
					Choice.propose(proposals, "food", goal, activity, reason, decision_sources, decision_intent)
			var subsistence_config: Dictionary = food_config.get("subsistence", {})
			var subsistence_need := Subsistence.decision(snapshot, actor, food_items, family, subsistence_config, tick)
			if not subsistence_need.is_empty():
				for profile: Dictionary in Subsistence.candidates(actor, profiles, subsistence_config, snapshot):
					var site := str(profile.workplace_id)
					if Subsistence.recently_failed(snapshot, id, site, tick, subsistence_config):
						continue
					var hours := 0 if site == location else int(_next_edge(routes, location, site).get("total_hours", 100000))
					if hours > int(subsistence_config.maximum_travel_hours):
						continue
					if work_time("subsistence", hour, config):
						goal = site
						activity = "foraging"
						reason = str(subsistence_need.reason)
					elif int(subsistence_config.get("household_affordability_version", 0)) == 1 \
							and states.get("occupation_id") in config.get("night_occupations", []):
						goal = home
						activity = "resting"
						reason = "现有买粮钱补不上口粮缺口，今晚暂停原班次，回家休息准备白天采食"
					else:
						continue
					decision_sources = subsistence_need.source_fact_ids
					decision_intent = "subsistence"
					if use_choice:
						Choice.propose(proposals, "forage", goal, activity, reason, decision_sources, decision_intent)
					break
			var self_reserve := 1 if FoodStorage.enabled(food_config.get("worksite_storage", {})) else 0
			var useful_return := true
			if self_reserve > 0 and location == home and not family.has("pantry_id"):
				useful_return = false
				for target: Dictionary in family.get("targets", []):
					if snapshot.get_entity_state(str(target.target_id), "location_id", "") == home \
							and snapshot.get_entity_state(str(target.target_id), "daily_route_id", "") == "":
						useful_return = true
			var return_reserve := int(food_config.get("household_budget", {}).get("personal_reserve", self_reserve))
			if not family.is_empty() and carried > return_reserve and useful_return:
				decision_intent = ""
				goal = str(family.home_location_id)
				activity = "home"
				reason = "给%s带粮回家" % family.names
				decision_sources = family.source_fact_ids
				if use_choice:
					Choice.propose(proposals, "care", goal, activity, reason, decision_sources, decision_intent)
			if Hauling.is_carrier(actor, haul_config) or not Hauling.active_order(snapshot, id).is_empty():
				var order := Hauling.active_order(snapshot, id)
				if not order.is_empty():
					goal = str(order.origin_location_id if order.status == "returning" else order.destination_location_id)
					activity = "working"
					reason = "携带未交出的托运粮食和封存运费返回" if order.status == "returning" else "把受托粮食送到约定家人手中，之后才能领取运费"
					if order.get("self_delivery", false):
						reason = "把未能送出的自有口粮带回作业地" if order.status == "returning" else "亲自把答应援助的口粮送到邻聚落的粮柜，没有运费收入"
					decision_sources = order.source_fact_ids
					decision_intent = "food_hauling"
					if use_choice:
						Choice.propose(proposals, "haul", goal, activity, reason, decision_sources, decision_intent)
				elif on_shift and (use_choice or (supply == "" and activity != "foraging" and (family.is_empty() or carried <= return_reserve))):
					var sites := FoodAccess.known_supply_locations(snapshot, actor, profiles, network, food_config)
					var best := ""
					var distance := 100000
					for site: String in sites:
						if Hauling.recently_visited(snapshot, id, site, tick, haul_config):
							continue
						var hours := 0 if site == location else int(_next_edge(routes, location, site).get("total_hours", 100000))
						if hours < distance:
							best = site
							distance = hours
					goal = best if best != "" else _hub(network, str(states.get("settlement_id", "")))
					activity = "seeking_work"
					reason = "到已知作业地询问有报酬的送粮差事" if best != "" else "暂未找到可到场询问的差事，返回集地"
					if use_choice:
						Choice.propose(proposals, "seek_work", goal, activity, reason, [], "")
		if use_choice:
			if not must_rest:
				var committed := proposals.any(func(row: Dictionary) -> bool: return row.kind in ["care", "haul"])
				if not committed:
					proposals.append_array(Assistance.proposals(snapshot, actor, tick, config.get("community_rules", {}), food_config.get("household_budget", {})))
					var visits := CommunityLife.proposals(snapshot, actor, tick, config.get("community_rules", {}), network)
					for visit: Dictionary in visits:
						visit["unmet_food"] = FoodAccess.needs_food(actor, food_items) or proposals.any(func(row: Dictionary) -> bool: return row.kind in ["food", "forage"] and not row.source_fact_ids.is_empty())
					proposals.append_array(visits)
			if not must_rest and on_shift:
				var demand := WorkOpportunities.need(snapshot, actor, profiles)
				if not demand.is_empty():
					demand.source_fact_ids.append_array(WorkOpportunities.failure_sources(snapshot, id, demand, tick))
					for profile: Dictionary in WorkOpportunities.repair_profiles(snapshot, actor, config, tick):
						Choice.propose(proposals, "repair", profile.workplace_id, "working", "工具已经磨坏，先到有材料的作业地修补", demand.source_fact_ids, "repair:" + str(profile.work_recipe.recipe_id))
					if bool(choice_config.get("supply_enabled", true)):
						for site: String in WorkOpportunities.supply_sites(snapshot, actor, profiles, demand, network, registry, tick):
							if site == workplace:
								Choice.propose(proposals, "resupply", site, "seeking_work", "先回作业地检查自己存下的备用用品，不需要向自己的货柜付钱", demand.source_fact_ids, "work_supply")
							elif FoodAccess.balance(food_items, id) > 0:
								Choice.propose(proposals, "resupply", site, "seeking_work", "作业用品不足，去已知的生产地当面询价", demand.source_fact_ids, "work_supply")
			var chosen := Choice.choose(proposals, actor, routes, self, snapshot, profiles, registry, choice_config, food_config)
			if not chosen.is_empty():
				goal = str(chosen.goal)
				activity = str(chosen.activity)
				reason = str(chosen.reason)
				decision_sources = chosen.source_fact_ids
				decision_intent = str(chosen.intent_id)
				decision_evidence = {"choice_version": 1, "chosen_candidate": chosen.rule_id,
					"goal_location_id": goal, "utility_score": chosen.score, "alternatives": chosen.alternatives}
			_change(result, id, states, "daily_intent_id", decision_intent)
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
			journey.merge(decision_evidence)
			if not decision_sources.is_empty():
				journey["source_fact_ids"] = decision_sources
			if decision_intent != "":
				journey["intent_id"] = decision_intent
			var fact := _transition(result, events, actor, states, "traveling", reason, tick, journey)
			_change(result, id, states, "daily_departure_fact_id", fact)
			continue
		var evidence := {"source_fact_ids": decision_sources} if not decision_sources.is_empty() else {}
		evidence.merge(decision_evidence)
		if decision_intent != "":
			evidence["intent_id"] = decision_intent
		_transition(result, events, actor, states, activity, reason, tick, evidence)
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
		items: Array, known_supply_cache: Dictionary, family: Dictionary = {}, business: bool = false) -> String:
	var hour := int(tick.get("hour", 0))
	if (not business and not FoodAccess.needs_food(actor, items) and family.is_empty()) or FoodAccess.balance(items, str(actor.id)) <= 0:
		return ""
	if business and FoodAccess.balance(items, str(actor.id)) <= int(config.carting.cash_reserve):
		return ""
	var states: Dictionary = actor.get("states", {})
	var location := str(states.get("location_id", ""))
	if int(states.get("age_years", 0)) < int(config.get("minimum_independent_shopping_age", 18)):
		return ""
	var own_settlement := str(states.get("settlement_id", ""))
	var away := str(locations.get(location, {}).get("settlement_id", own_settlement)) != own_settlement
	if not business and not away and (hour < int(config.get("shopping_start_hour", 12)) or hour > int(config.get("shopping_end_hour", 17))):
		return ""
	# A food producer can satisfy this need by continuing real production.
	for profile: Dictionary in profiles:
		if str(profile.get("workplace_id", "")) == str(states.get("workplace_id", "")) \
				and str(profile.get("occupation_id", "")) == str(states.get("occupation_id", "")) \
				and FoodAccess.is_food_producer(profile):
			if not profile.has("work_recipe") or not WorkOpportunities.knows_work_blocked(snapshot, actor, profile, tick):
				return ""
	var individual_knowledge := CommunityKnowledge.enabled(config.get("community_rules", {}))
	var cache_key := str(actor.id) if individual_knowledge else own_settlement + (".cart" if Carting.is_carter(actor, config.get("carting", {})) else "")
	if not known_supply_cache.has(cache_key):
		known_supply_cache[cache_key] = FoodAccess.known_supply_locations(snapshot, actor, profiles, network, config, tick)
	var sites: Array = known_supply_cache[cache_key].duplicate()
	if individual_knowledge:
		var costs := {}
		for site: String in sites:
			var distance := 0 if site == location else int(_next_edge(routes, location, site).get("total_hours", 100000))
			var reports := CommunityKnowledge.supply_reports(snapshot, str(actor.id), CommunityKnowledge.hour(tick)).filter(func(m: Dictionary) -> bool: return m.location_id == site)
			# Recent positive testimony is worth checking before another merely familiar empty site.
			costs[site] = distance * 3 - (18 if not reports.is_empty() else 0)
		sites.sort_custom(func(a: String, b: String) -> bool: return costs[a] < costs[b] if costs[a] != costs[b] else a < b)
	elif Carting.enabled(config.get("carting", {})):
		var distances := {}
		for site: String in sites:
			distances[site] = 0 if site == location else int(_next_edge(routes, location, site).get("total_hours", 100000))
		sites.sort_custom(func(a: String, b: String) -> bool:
			return int(distances[a]) < int(distances[b]) if distances[a] != distances[b] else a < b)
	for site: String in sites:
		if individual_knowledge and FoodAccess.recently_failed(snapshot, str(actor.id), site, tick, config):
			continue
		if Carting.enabled(config.get("carting", {})) and FoodAccess.recently_failed(snapshot, str(actor.id), site, tick, config):
			continue
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
