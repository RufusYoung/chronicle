extends RefCounted

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")


static func validate(config: Variant, definitions: Array) -> String:
	if not config is Dictionary or config.get("version") != 1 or not config.get("foods") is Dictionary \
			or config.keys().any(func(key: Variant) -> bool: return key not in ["version", "foods"]):
		return "invalid_meal_rules"
	for id: String in config.foods:
		var rule: Variant = config.foods[id]
		if not rule is Dictionary or rule.size() != 1 or not Recipe._integer(rule.get("satiation_hours"), 1) or rule.satiation_hours > 12:
			return "invalid_meal_satiation"
		if not definitions.any(func(row: Dictionary) -> bool: return row.get("item_def_id") == id and "food" in row.get("tags", []) and "consume" in row.get("capabilities", [])):
			return "meal_definition_not_edible"
	return ""


static func hours(config: Dictionary, food: Dictionary) -> int:
	if config.get("version") != 1:
		return 0
	return int(config.get("foods", {}).get(str(food.get("item_def_id", "")), {}).get("satiation_hours", 0))


static func now(tick: Dictionary) -> int:
	return maxi(int(tick.get("day", 1)) - 1, 0) * 24 + int(tick.get("hour", 0))


static func append(result: Variant, actor: String, food: Dictionary, config: Dictionary, tick: Dictionary) -> void:
	var duration := hours(config, food)
	if duration == 0:
		return
	# A meal replaces its own timer; repeated eating never stacks future meals.
	result.add_state_change({"entity_id": actor, "key": "hunger_sated_until", "to": now(tick) + duration})
	if not result.facts_added.is_empty():
		result.facts_added.back()["satiation_hours"] = duration


static func describe(config: Dictionary, food: Dictionary) -> String:
	var duration := hours(config, food)
	return "吃下后%d小时内饥饿不增长；不能叠加，也不延长保存期。" % duration if duration > 0 else ""


static func configure_needs(profiles: Array, fixture: Dictionary) -> void:
	if fixture.get("content_extension", {}).get("meal_rules", {}).get("version") != 1:
		return
	for profile: Dictionary in profiles:
		for need: Dictionary in profile.get("needs", []):
			if need.get("key") == "hunger":
				need["pause_until_state_key"] = "hunger_sated_until"
