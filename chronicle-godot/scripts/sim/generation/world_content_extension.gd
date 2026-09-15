extends RefCounted

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Incidents = preload("res://scripts/sim/player/local_incident_options.gd")
const Meal = preload("res://scripts/sim/economy/meal_satiation.gd")
const Access = preload("res://scripts/sim/resource/resource_access.gd")
const DEFAULT_PATH := "res://data/sim/raw/content/echo_port_life_v1.json"
const V2_PATH := "res://data/sim/raw/content/echo_port_life_v2.json"


static func validate(value: Variant) -> String:
	if not value is Dictionary:
		return "content_extension_not_dictionary"
	if value.is_empty():
		return ""
	if (value.get("version") != 1 and value.get("version") != 2) or not value.get("id") is String or str(value.id).is_empty():
		return "unsupported_content_extension"
	for key: String in value:
		if key not in ["version", "id", "source_note", "item_defs", "work_rules", "resident_variants", "incidents", "world_danger", "meal_rules", "visitor_commons"]:
			return "unknown_content_extension_field:" + key
	if value.get("version") == 1 and (value.has("meal_rules") or value.has("visitor_commons")):
		return "new_life_rules_require_content_v2"
	if value.get("version") == 2:
		var visitors: Variant = value.get("visitor_commons")
		if not visitors is Dictionary or visitors.size() != 1 or not Recipe._integer(visitors.get("daily_limit"), 1) or visitors.daily_limit > 4:
			return "invalid_visitor_commons_limit"
	for key: String in ["item_defs", "resident_variants", "incidents"]:
		if not value.get(key, []) is Array:
			return "invalid_content_extension_array:" + key
	var resident_ids := {}
	for row: Variant in value.get("resident_variants", []):
		if not row is Dictionary or not row.get("id") is String or str(row.id).strip_edges() == "" \
				or resident_ids.has(row.id) or not row.get("states") is Dictionary or row.states.is_empty() \
				or not _fields(row, ["id", "states"]):
			return "invalid_content_resident_variant"
		resident_ids[row.id] = true
		for key: String in row.states:
			var state: Variant = row.states[key]
			if key == "temperament" and state in ["steady", "cautious", "bold", "sociable", "reserved"]:
				continue
			if key == "hunger" and state in ["none", "low", "medium", "high", "extreme"]:
				continue
			if key == "fatigue" and Recipe._integer(state, 0) and int(state) <= 10:
				continue
			return "unsupported_content_resident_state:" + key
	for row: Variant in value.get("item_defs", []):
		if not row is Dictionary or row.get("item_kind") not in ["food", "craft_good"]:
			return "invalid_content_item_definition"
		if not _fields(row, ["item_def_id", "definition_version", "display_name", "display_name_key", "item_kind", "tags",
			"stackable", "max_stack", "base_mass", "equip_slots", "capabilities", "durability", "modifiers", "base_value"]):
			return "unsupported_content_item_field"
		if row.get("modifiers", []) != [] or row.get("equip_slots", []) != []:
			return "content_v1_requires_plain_goods"
		if not row.get("capabilities") is Array or row.capabilities.is_empty() \
				or not row.capabilities.all(func(cap: Variant) -> bool: return cap in ["consume", "trade", "split_stack"]):
			return "unsupported_content_item_capability"
		if not Recipe._integer(row.get("definition_version"), 1) or not Recipe._integer(row.get("base_value"), 0) \
				or not row.get("display_name") is String or str(row.display_name).strip_edges() == "":
			return "invalid_content_item_value"
		if not row.get("base_mass") is float and not row.get("base_mass") is int:
			return "invalid_content_item_mass"
		if not is_finite(float(row.base_mass)) or float(row.base_mass) < 0:
			return "invalid_content_item_mass"
		if not row.get("tags") is Array or not row.tags.all(func(tag: Variant) -> bool: return tag is String and tag.strip_edges() != ""):
			return "invalid_content_item_tags"
		if not row.get("durability", {}) is Dictionary or not _fields(row.get("durability", {}), ["maximum"]):
			return "unsupported_content_durability"
	if value.get("version") == 2:
		var error := Meal.validate(value.get("meal_rules"), value.get("item_defs", []))
		if error != "":
			return error
	if value.has("work_rules"):
		if not value.work_rules is Dictionary or not _fields(value.work_rules, ["version", "maintenance", "overrides"]):
			return "unsupported_content_work_rules"
		if not value.work_rules.get("overrides", []) is Array or not value.work_rules.get("maintenance", []) is Array:
			return "invalid_content_work_rules"
		for override: Variant in value.work_rules.get("overrides", []):
			if not override is Dictionary or not _fields(override, ["product_query", "products", "label", "work_recipe", "initial_tools", "work_interval_hours", "recipe_variants"]):
				return "unsupported_content_work_override"
		for row: Variant in value.work_rules.get("maintenance", []):
			if not row is Dictionary or not _fields(row, ["recipe_id", "label", "resource_tags_all", "amount_per_cycle", "work_interval_hours", "repairs"]):
				return "unsupported_content_maintenance"
	if value.has("world_danger"):
		if not value.world_danger is Dictionary or not _fields(value.world_danger, ["version", "contacts_enabled", "memory_hours", "retreat_hours", "recovery_hours", "rest_health_gain", "threat"]):
			return "unsupported_content_danger"
		if not value.world_danger.get("threat") is Dictionary or not _fields(value.world_danger.threat, ["display_name", "health", "attack", "defense", "escape_difficulty", "retreat_health", "damage", "start_hour", "end_hour"]):
			return "unsupported_content_threat"
	return Incidents.validate(value.get("incidents", []))


static func _fields(value: Dictionary, allowed: Array) -> bool:
	return value.keys().all(func(key: Variant) -> bool: return key in allowed)


static func signature(pack: Dictionary) -> Dictionary:
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(pack, "", true, true))
	return {"version": pack.version, "id": pack.id, "definition_hash": JSON.stringify(normalized, "", true, true).sha256_text()}


static func register_items(fixture: Dictionary, registry: Variant) -> String:
	for definition: Dictionary in fixture.get("content_extension", {}).get("item_defs", []):
		if not registry.register_definition("item", str(definition.get("item_def_id", "")), definition):
			return "content_item_invalid:" + str(registry.definition_errors)
	return ""


static func validate_compiled(fixture: Dictionary) -> String:
	var pack: Dictionary = fixture.get("content_extension", {})
	if pack.is_empty():
		return ""
	var profiles: Array = []
	for base: Dictionary in fixture.get("generated_livelihood_profiles", []):
		profiles.append_array(Recipe.variants(base))
	var recipes := {}
	var site_recipes := {}
	var produced := {}
	var resource_ids: Array = fixture.get("initial_resource_stocks", []).map(func(stock: Dictionary) -> String: return str(stock.stock_id))
	for profile: Dictionary in profiles:
		var recipe: Dictionary = profile.get("work_recipe", {})
		if recipe.is_empty():
			continue
		var site_recipe := "%s::%s" % [profile.workplace_id, recipe.recipe_id]
		if site_recipes.has(site_recipe):
			return "content_recipe_ambiguous_at_site"
		site_recipes[site_recipe] = true
		recipes[recipe.recipe_id] = true
		for product: Dictionary in profile.products:
			produced[product.item_def_id] = true
		for input: Dictionary in profile.get("resource_inputs", []):
			if input.stock_id not in resource_ids:
				return "content_resource_reference_missing"
	for override: Dictionary in pack.get("work_rules", {}).get("overrides", []):
		var specs: Array = override.get("recipe_variants", []).duplicate()
		if override.has("work_recipe"):
			specs.append(override)
		for spec: Dictionary in specs:
			if not recipes.has(spec.get("work_recipe", {}).get("recipe_id", "")):
				return "content_recipe_not_instantiated"
	for definition: Dictionary in pack.get("item_defs", []):
		if not produced.has(definition.item_def_id):
			return "content_item_not_producible:" + str(definition.item_def_id)
		if "food" in definition.tags and "consume" in definition.capabilities:
			continue
		var used := false
		for profile: Dictionary in profiles:
			for input: Dictionary in profile.get("work_recipe", {}).get("tools", []) + profile.get("work_recipe", {}).get("item_inputs", []):
				used = used or Recipe.matches(definition, input.query)
		if not used:
			return "content_item_has_no_consumer:" + str(definition.item_def_id)
	return ""


static func prepare(fixture: Dictionary) -> String:
	var pack: Dictionary = fixture.get("content_extension", {})
	if pack.is_empty():
		return "content_extension_missing_bootstrap" if fixture.has("content_extension_generated") else ""
	if fixture.has("content_extension_generated"):
		if fixture.content_extension_generated != signature(pack):
			return "content_extension_compiled_mismatch"
		for key: String in ["work_rules", "world_danger"]:
			if not pack.has(key):
				continue
			var expected: Dictionary = pack[key].duplicate(true)
			if key == "world_danger":
				expected["seed"] = int(fixture.get("challenge_seed", 1))
			# Native JSON restores integral numbers as floats, not different rules.
			if JSON.parse_string(JSON.stringify(fixture.get(key))) != JSON.parse_string(JSON.stringify(expected)):
				return "content_extension_rules_mismatch:" + key
		if pack.get("version") == 2 and fixture.resident_daily_life.food_access.get("meal_rules", {}) != pack.meal_rules:
			return "content_meal_rules_mismatch"
		return ""
	if fixture.get("player_life", {}).get("version") != 2 or fixture.get("work_rules", {}).is_empty():
		return "content_extension_requires_player_life_v2"
	if pack.has("work_rules"):
		if not pack.work_rules is Dictionary:
			return "invalid_content_work_rules"
		fixture.work_rules = pack.work_rules.duplicate(true)
	if pack.has("world_danger"):
		if not pack.world_danger is Dictionary:
			return "invalid_content_world_danger"
		fixture.world_danger = pack.world_danger.duplicate(true)
		fixture.world_danger["seed"] = int(fixture.get("challenge_seed", 1))
	if pack.get("version") == 2:
		fixture.resident_daily_life.food_access["meal_rules"] = pack.meal_rules.duplicate(true)
	var variants: Array = pack.get("resident_variants", [])
	var index := 0
	for person: Dictionary in fixture.get("entities", []):
		if variants.is_empty() or "generated_resident" not in person.get("tags", []) or int(person.get("states", {}).get("age_years", 0)) < 18:
			continue
		var variant: Dictionary = variants[posmod(index + int(fixture.get("challenge_seed", 0)), variants.size())]
		person.states.merge(variant.states, true)
		person["content_variant_id"] = variant.id
		index += 1
	fixture["content_extension_generated"] = signature(pack)
	return ""


static func configure_commons(fixture: Dictionary) -> String:
	var pack: Dictionary = fixture.get("content_extension", {})
	if pack.get("version") != 2:
		return ""
	var sites := {}
	for base: Dictionary in fixture.get("generated_livelihood_profiles", []):
		for profile: Dictionary in Recipe.variants(base):
			for input: Dictionary in profile.get("resource_inputs", []):
				if not sites.has(input.stock_id):
					sites[input.stock_id] = []
				if profile.workplace_id not in sites[input.stock_id]:
					sites[input.stock_id].append(profile.workplace_id)
	for stock: Dictionary in fixture.get("initial_resource_stocks", []):
		if stock.get("source_kind") != "natural_resource" or not sites.has(stock.stock_id):
			continue
		if not stock.has("access"):
			return "visitor_commons_requires_managed_stock"
		var fact_id := str(stock.access.source_fact_id) + ".visitors." + str(stock.stock_id)
		var policy := {"daily_limit": pack.visitor_commons.daily_limit, "workplace_ids": sites[stock.stock_id], "source_fact_id": fact_id}
		if fixture.has("content_commons_generated"):
			if stock.access.get("version") != 2 or stock.access.get("visitors", {}) != policy:
				return "visitor_commons_compiled_mismatch"
			continue
		stock.access["version"] = 2
		stock.access["visitors"] = policy
		stock.access["visitor_usage"] = {}
		fixture.known_facts.append({"fact_id": fact_id, "fact_type": "resource_visitor_access_established",
			"actor_id": stock.access.manager_id, "stock_ids": [stock.stock_id], "visitor_policy": policy.duplicate(true),
			"source_fact_ids": [stock.access.source_fact_id], "summary": "地方公地允许到场访客在每日定额内采收；仍需投入劳动并消耗现有资源。"})
	fixture["content_commons_generated"] = {"version": 1}
	return ""
