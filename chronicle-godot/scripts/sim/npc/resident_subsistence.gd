extends RefCounted
class_name V5ResidentSubsistence

const Food = preload("res://scripts/sim/economy/resident_food_access.gd")
const Family = preload("res://scripts/sim/npc/household_provisioning.gd")
const PROFILE := {"version": 1, "work_hours": 4, "portions": 4, "minimum_health": 40,
	"minimum_age": 18, "retry_hours": 12, "maximum_travel_hours": 4,
	"household_affordability_version": 1, "quote_memory_hours": 24}
const STATE_KEYS := ["subsistence_elapsed_hours", "subsistence_workplace_id"]


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func validate_config(config: Dictionary) -> String:
	if int(config.get("version", 0)) not in [0, 1]:
		return "unsupported_resident_subsistence_version"
	if enabled(config):
		for key: String in PROFILE:
			if key in ["household_affordability_version", "quote_memory_hours"] and not config.has(key):
				continue
			var value: Variant = config.get(key)
			if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 1:
				return "invalid_resident_subsistence_config"
		if int(config.get("household_affordability_version", 0)) not in [0, 1]:
			return "unsupported_subsistence_affordability_version"
	return ""


static func candidates(actor: Dictionary, profiles: Array, config: Dictionary) -> Array:
	var rows: Array = []
	var state: Dictionary = actor.get("states", {})
	if not enabled(config) or "generated_resident" not in actor.get("tags", []) \
			or int(state.get("age_years", 0)) < int(config.minimum_age) or int(state.get("health", 0)) < int(config.minimum_health) \
			or not bool(state.get("alive", true)) or state.get("life_status", "alive") != "alive":
		return rows
	for profile: Dictionary in profiles:
		if profile.get("settlement_id") != state.get("settlement_id") or not Food.is_food_producer(profile):
			continue
		if profile.get("occupation_id") == state.get("occupation_id"):
			return []
		# Local residents know the commons and its usual use, not current stock or private stores.
		var row := profile.duplicate(true)
		row["actor_tags_all"] = ["generated_resident"]
		row["wage_amount"] = 0
		row["work_interval_hours"] = int(config.work_hours)
		row["work_kind"] = "subsistence"
		row["work_summary"] = "%s暂时放下原本的安排，在本地公用作业地采食，产物需自己携带。" % actor.display_name
		row["products"] = [{"item_def_id": profile.products[0].item_def_id,
			"quantity": mini(int(config.portions), int(profile.products[0].quantity))}]
		rows.append(row)
	return rows


static func wants_work(snapshot: Variant, actor: Dictionary, items: Array, family: Dictionary, config: Dictionary, tick: Dictionary) -> bool:
	return not decision(snapshot, actor, items, family, config, tick).is_empty()


static func decision(snapshot: Variant, actor: Dictionary, items: Array, family: Dictionary, config: Dictionary, tick: Dictionary) -> Dictionary:
	if not enabled(config) or (not Food.needs_food(actor, items) and family.is_empty()):
		return {}
	if Food.food_quantity(items, str(actor.id)) >= int(config.portions):
		return {}
	# A failed purchase is remembered; an empty wallet does not require omniscient price knowledge.
	var money := Food.balance(items, str(actor.id))
	var sources: Array = family.get("source_fact_ids", []).duplicate()
	if money == 0:
		return {"reason": "口粮不足且没有买粮钱，尝试在已知公用作业地采食", "source_fact_ids": sources}
	var household_budget := int(config.get("household_affordability_version", 0)) == 1
	var latest: Dictionary = {}
	var latest_hour := -1
	for fact: Dictionary in snapshot.get_facts():
		if fact.get("actor_id") != actor.id:
			continue
		var price := 0
		if fact.get("fact_type") == "resident_food_purchase_unmet" and fact.get("reason") == "unaffordable":
			price = int(fact.get("unit_price", 0))
		elif household_budget and fact.get("fact_type") == "resident_food_purchased":
			price = int(fact.get("fields", {}).get("unit_price", 0))
		var observed := Family.absolute_hour(fact)
		var memory_hours := int(config.get("quote_memory_hours", 24)) if household_budget else int(config.retry_hours)
		if price <= 0 or observed > Family.absolute_hour(tick) or Family.absolute_hour(tick) - observed >= memory_hours:
			continue
		if observed > latest_hour:
			latest = {"unit_price": price, "fact_id": fact.fact_id}
			latest_hour = observed
	if latest.is_empty():
		return {}
	var wanted := maxi(int(family.get("target_portions", 1)) - Food.food_quantity(items, str(actor.id)), 1) if household_budget else 1
	if money >= int(latest.unit_price) * wanted:
		return {}
	sources.append(str(latest.fact_id))
	return {"reason": "按自己见过的报价，买粮钱不足以补上已知口粮缺口，尝试采食", "source_fact_ids": sources}


static func recently_failed(snapshot: Variant, actor: String, site: String, tick: Dictionary, config: Dictionary) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if fact.get("fact_type") == "npc_livelihood_blocked_resource" and fact.get("actor_id") == actor \
				and fact.get("work_kind") == "subsistence" and fact.get("location_id") == site \
				and Family.absolute_hour(tick) - Family.absolute_hour(fact) < int(config.retry_hours):
			return true
	return false


static func active_profile(actor: Dictionary, profiles: Array, config: Dictionary) -> Dictionary:
	if actor.get("states", {}).get("daily_activity") != "foraging":
		return {}
	for profile: Dictionary in candidates(actor, profiles, config):
		if profile.workplace_id == actor.states.get("location_id") and actor.states.get("daily_route_id", "") == "":
			return profile
	return {}
