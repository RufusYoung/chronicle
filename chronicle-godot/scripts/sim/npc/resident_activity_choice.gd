extends RefCounted
class_name V5ResidentActivityChoice

const Decision = preload("res://scripts/sim/npc/npc_decision_system.gd")
const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const WorkOpportunities = preload("res://scripts/sim/economy/resident_work_opportunities.gd")
const WorldDanger = preload("res://scripts/sim/combat/world_danger_system.gd")
const PROFILE := {"version": 1, "supply_enabled": true, "travel_cost": 3, "continuity_bonus": 8, "optional_rest_discount": 50,
	"weights": {"home": 0, "rest": 80, "work": 35, "seek_work": 18,
		"food": 48, "forage": 43, "care": 64, "cart": 36, "haul": 90,
		"resupply": 62, "repair": 60}}
const STATE_KEYS := ["daily_intent_id", "work_elapsed_recipe_id"]


static func enabled(config: Dictionary) -> bool:
	return config.get("version", 0) == 1


static func validate(config: Variant) -> String:
	if not config is Dictionary:
		return "activity_choice_not_dictionary"
	if config.is_empty():
		return ""
	if config.get("version") != 1 or not config.get("weights") is Dictionary:
		return "invalid_activity_choice_version_or_weights"
	if not config.get("supply_enabled", true) is bool:
		return "invalid_activity_supply_flag"
	for key: String in PROFILE.weights:
		if not Recipe._integer(config.weights.get(key), 0):
			return "invalid_activity_choice_weight:" + key
	for key: String in ["travel_cost", "continuity_bonus", "optional_rest_discount"]:
		if not Recipe._integer(config.get(key), 0):
			return "invalid_activity_choice_cost:" + key
	return ""


static func propose(rows: Array, kind: String, goal: String, activity: String,
		reason: String, sources: Array = [], intent: String = "") -> void:
	rows.append({"rule_id": "%s:%s" % [kind, goal], "kind": kind, "goal": goal,
		"activity": activity, "reason": reason, "source_fact_ids": sources.duplicate(), "intent_id": intent})


static func choose(rows: Array, actor: Dictionary, routes: Array, router: Variant,
		snapshot: Variant, profiles: Array, registry: Variant, config: Dictionary, food_config: Dictionary) -> Dictionary:
	var evaluations: Array = []
	var states: Dictionary = actor.states
	var location := str(states.get("location_id", ""))
	var hunger := str(states.get("hunger", "none"))
	var items: Array = snapshot.get_items_for_holder(str(actor.id))
	var need_food := Food.needs_food(actor, items)
	for source: Dictionary in rows:
		var row := source.duplicate(true)
		var hours := 0 if row.goal == location else int(router._next_edge(routes, location, row.goal).get("total_hours", 100000))
		if hours >= 100000 or row.goal == "":
			continue
		var factors := {"purpose": int(config.weights[row.kind]), "travel": -hours * int(config.travel_cost)}
		if config.has("danger_hour"):
			var danger := WorldDanger.known_danger(snapshot, str(actor.id), str(row.goal), int(config.danger_hour))
			if not danger.is_empty():
				factors["personally_seen_danger"] = -100 if states.get("temperament") == "cautious" else -75
				if hunger == "extreme" and row.kind in ["food", "forage", "work"]:
					factors["hunger_against_danger"] = 55
				row.source_fact_ids.append(str(danger.source_fact_id))
		if row.kind == "social":
			factors["company_need"] = mini(int(row.get("social_need", 0)), 30)
			factors["liaison"] = 8 if bool(row.get("representative", false)) else 0
			factors["carried_news"] = 28 if bool(row.get("dispatch", false)) else 0
			factors["unmet_food"] = -30 if bool(row.get("unmet_food", false)) else 0
		if row.kind == "aid":
			factors["trust"] = mini(int(row.get("aid_trust", 0)), 12)
			factors["temperament"] = int({"cautious": -16, "reserved": -8, "sociable": 6}.get(str(states.get("temperament", "steady")), 0))
		if row.kind == "rest" and not bool(row.get("mandatory_rest", false)):
			factors["optional_rest"] = -int(config.optional_rest_discount)
		if row.kind in ["food", "forage"] and need_food:
			factors["personal_hunger"] = 22 if hunger == "extreme" else 12
		if row.kind in ["care", "food", "forage"] and not row.source_fact_ids.is_empty():
			factors["known_need"] = 6
		if row.kind == "work":
			factors["fatigue"] = -int(states.get("fatigue", 0)) * 2
			for profile: Dictionary in profiles:
				if profile.get("occupation_id") != states.get("occupation_id") or profile.get("workplace_id") != row.goal:
					continue
				if Food.is_food_producer(profile) and need_food:
					factors["own_meal_output"] = 22
				if location == row.goal and (not Storage.has_capacity(snapshot, str(actor.id), profile, food_config.get("worksite_storage", {})) \
						or (Recipe.enabled(profile) and not Recipe.new(snapshot, registry).plan_inputs(profile, str(actor.id), "preview", 0).ok)):
					factors["known_work_blocked"] = -100
				if int(states.get("livelihood_elapsed_hours", 0)) > 0:
					factors["unfinished_work"] = mini(int(states.livelihood_elapsed_hours), int(profile.get("work_interval_hours", 1))) * 2
				if WorkOpportunities.knows_work_blocked(snapshot, actor, profile, snapshot.world_time):
					factors["known_work_blocked"] = -100
		if row.goal == states.get("daily_goal_id") and row.activity == states.get("daily_activity"):
			factors["continuity"] = int(config.continuity_bonus)
		row["score"] = 0
		for value: int in factors.values():
			row.score += value
		row["factors"] = factors
		row["travel_hours"] = hours
		evaluations.append(row)
	var chosen := Decision.choose_candidate(evaluations)
	if not chosen.is_empty():
		chosen["alternatives"] = evaluations.map(func(row: Dictionary) -> Dictionary: return {
			"rule_id": row.rule_id, "goal": row.goal, "activity": row.activity, "score": row.score, "factors": row.factors})
	return chosen
