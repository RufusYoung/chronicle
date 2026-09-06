extends RefCounted
class_name V5ResidentFoodCarting

const PROFILE := {"version": 1, "target_portions": 8, "cash_reserve": 0,
	"retained_portions": 1, "minimum_load": 2, "unit_margin": 1}


static func enabled(config: Dictionary) -> bool:
	return int(config.get("version", 0)) == 1


static func is_carter(actor: Dictionary, config: Dictionary) -> bool:
	return enabled(config) and "generated_resident" in actor.get("tags", []) \
		and actor.get("states", {}).get("occupation_id") == "road_carter"


static func validate(config: Dictionary) -> String:
	if int(config.get("version", 0)) not in [0, 1]:
		return "unsupported_food_carting_version"
	if not enabled(config):
		return ""
	for key: String in ["target_portions", "cash_reserve", "retained_portions", "minimum_load", "unit_margin"]:
		var value: Variant = config.get(key)
		if not (value is int or value is float) or float(value) != float(int(value)) or int(value) < 0:
			return "invalid_food_carting_config"
	if int(config.minimum_load) < 2 or int(config.target_portions) < int(config.minimum_load) \
			or int(config.retained_portions) >= int(config.minimum_load):
		return "invalid_food_carting_config"
	return ""


static func restocking(snapshot: Variant, actor: Dictionary, config: Dictionary) -> bool:
	if not is_carter(actor, config):
		return false
	var states: Dictionary = actor.get("states", {})
	var facts: Array = snapshot.get_facts()
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if states.get("daily_activity") == "arrived":
			if fact.get("fact_id") == states.get("daily_departure_fact_id"):
				return fact.get("intent_id") == "food_carting"
		elif fact.get("actor_id") == actor.id and fact.get("fact_type") == "resident_activity_changed":
			return fact.get("intent_id") == "food_carting"
	return false


static func stall_location(actor: Dictionary, network: Dictionary) -> String:
	for site: Dictionary in network.get("sites", []):
		if site.get("settlement_id") == actor.get("states", {}).get("settlement_id"):
			return str(site.get("hub_location_id", ""))
	return str(actor.get("states", {}).get("workplace_id", ""))


static func purchase_source(snapshot: Variant, item: Dictionary, seller: String) -> Dictionary:
	# A margin belongs to a paid, physically transported lot, not to an occupation label.
	var source := str(item.get("provenance", {}).get("created_by_fact_id", ""))
	for history: Dictionary in item.get("history", []):
		if history.get("event_type") in ["split_from", "transferred"]:
			source = str(history.get("fact_id", source))
	for fact: Dictionary in snapshot.get_facts():
		if fact.get("fact_id") != source:
			continue
		if fact.get("fact_type") == "resident_food_purchased" and fact.get("actor_id") == seller \
				and fact.get("purpose_id") == "food_carting" \
				and fact.get("location_id") != snapshot.get_entity_state(seller, "location_id", ""):
			return fact
	return {}
