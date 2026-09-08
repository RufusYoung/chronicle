extends RefCounted
class_name V5WorkRulesSetup

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const Storage = preload("res://scripts/sim/economy/worksite_food_storage.gd")
const Choice = preload("res://scripts/sim/npc/resident_activity_choice.gd")
const DEFAULT_PATH := "res://data/sim/raw/work_rules/echo_port_work_rules_v1.json"


static func configure(fixture: Dictionary, registry: Variant) -> String:
	var config: Variant = fixture.get("work_rules", {})
	if not config is Dictionary:
		return "work_rules_not_dictionary"
	if config.is_empty():
		return _validate_profiles(fixture, registry)
	if config.get("version") != 1:
		return "unsupported_work_rules_version"
	if not fixture.get("resident_daily_life", {}).has("food_access"):
		return "work_rules_require_physical_daily_life"
	var choice_error := Choice.validate(fixture.resident_daily_life.get("activity_choice", {}))
	if choice_error != "":
		return choice_error
	if not config.get("overrides", []) is Array:
		return "invalid_work_rules_overrides"
	if not config.get("maintenance", []) is Array:
		return "invalid_work_maintenance"
	for override: Variant in config.get("overrides", []):
		if not override is Dictionary or not override.get("product_query") is Dictionary or override.product_query.is_empty():
			return "invalid_work_rule_override"
		for key: String in override.product_query:
			if key not in Recipe.QUERY_KEYS:
				return "unknown_work_rule_product_query"
			if key == "item_def_id":
				if not override.product_query[key] is String or not registry.has_definition("item", override.product_query[key]):
					return "unknown_work_rule_product"
			elif not override.product_query[key] is Array or override.product_query[key].is_empty():
				return "invalid_work_rule_product_query"
			else:
				for tag: Variant in override.product_query[key]:
					if not tag is String or tag.strip_edges() == "":
						return "invalid_work_rule_product_tag"
		if not override.get("products", []) is Array or not override.get("initial_tools", []) is Array \
				or not override.get("work_recipe", {}) is Dictionary:
			return "invalid_work_rule_override_value"
		for product: Variant in override.get("products", []):
			if not product is Dictionary or not Recipe._integer(product.get("quantity"), 1) \
					or not registry.has_definition("item", str(product.get("item_def_id", ""))):
				return "invalid_work_rule_product"
	if fixture.has("work_rules_generated"):
		return _validate_profiles(fixture, registry)
	var tools_by_profile := {}
	for profile: Dictionary in fixture.get("generated_livelihood_profiles", []):
		if profile.get("products", []).is_empty() or profile.get("resource_inputs", []).is_empty():
			continue
		tools_by_profile[_key(profile)] = _apply_rules(profile, config, registry)
	for profile: Dictionary in fixture.get("settlement_network_runtime", {}).get("industry_occupation_templates", []):
		if not profile.get("products", []).is_empty() and profile.products.all(func(p: Dictionary) -> bool: return registry.get_definition("item", str(p.item_def_id)).get("item_kind") != "currency"):
			_apply_rules(profile, config, registry)
	var error := _validate_profiles(fixture, registry)
	if error != "":
		return error
	for actor: Dictionary in fixture.get("entities", []):
		if actor.get("type") != "person" or "generated_resident" not in actor.get("tags", []):
			continue
		var entries: Variant = tools_by_profile.get(_key(actor.get("states", {})), [])
		if not entries is Array:
			return "invalid_work_initial_tools"
		for index: int in range(entries.size()):
			var entry: Variant = entries[index]
			if not entry is Dictionary or not Recipe._integer(entry.get("quantity"), 1):
				return "invalid_work_initial_tool"
			var definition: Dictionary = registry.get_definition("item", str(entry.get("item_def_id", "")))
			if definition.is_empty() or int(definition.get("durability", {}).get("maximum", 0)) < 1:
				return "unknown_or_unusable_initial_tool"
			var fact_id := "fact.initial_work_tool.%s.%d" % [actor.id, index]
			fixture.known_facts.append({"fact_id": fact_id, "fact_type": "initial_work_tool_owned", "actor_id": actor.id,
				"day": 1, "item_def_id": entry.item_def_id, "quantity": entry.quantity,
				"summary": "%s在世界开始时拥有作业工具，使用后不会自动补发。" % actor.display_name})
			fixture.initial_items.append({"item_instance_id": "item." + fact_id, "item_def_id": entry.item_def_id,
				"holder": {"kind": "entity", "id": actor.id}, "quantity": entry.quantity,
				"provenance": {"source_kind": "initial_world_equipment", "created_by_fact_id": fact_id}})
	var storage: Dictionary = Storage.PROFILE.duplicate(true)
	storage.version = 2
	fixture.resident_daily_life.food_access["worksite_storage"] = storage
	fixture.resident_daily_life["activity_choice"] = Choice.PROFILE.duplicate(true)
	var maintenance: Array = []
	for spec: Variant in config.get("maintenance", []):
		if not spec is Dictionary or not spec.get("resource_tags_all") is Array or spec.resource_tags_all.is_empty():
			return "invalid_maintenance_resource_query"
		for tag: Variant in spec.resource_tags_all:
			if not tag is String or tag.strip_edges() == "":
				return "invalid_maintenance_resource_tag"
		for profile: Dictionary in fixture.get("generated_livelihood_profiles", []):
			for input: Dictionary in profile.get("resource_inputs", []):
				for stock: Dictionary in fixture.get("initial_resource_stocks", []):
					if stock.stock_id != input.stock_id or not spec.resource_tags_all.all(func(tag: String) -> bool: return tag in stock.get("tags", [])):
						continue
					var row := {"settlement_id": profile.settlement_id, "workplace_id": profile.workplace_id,
						"occupation_id": "maintenance", "actor_tags_all": ["generated_resident"], "label": spec.get("label", "修补工具"),
						"work_interval_hours": spec.get("work_interval_hours"), "wage_amount": 0, "products": [],
						"resource_inputs": [{"stock_id": input.stock_id, "label": input.get("label", "修补材料"), "amount_per_cycle": spec.get("amount_per_cycle")}],
						"work_recipe": {"version": 1, "recipe_id": str(spec.get("recipe_id", "")) + "." + str(profile.settlement_id),
							"item_inputs": [], "tools": [], "repairs": spec.get("repairs", [])}}
					var invalid := Recipe.validate_profile(row, registry)
					if invalid != "":
						return invalid
					maintenance.append(row)
	fixture.resident_daily_life["maintenance_profiles"] = maintenance
	fixture["work_rules_generated"] = {"version": 1}
	return ""


static func _validate_profiles(fixture: Dictionary, registry: Variant) -> String:
	var profiles: Array = fixture.get("generated_livelihood_profiles", []).duplicate()
	profiles.append_array(fixture.get("resident_daily_life", {}).get("maintenance_profiles", []))
	for profile: Dictionary in profiles:
		var error := Recipe.validate_profile(profile, registry)
		if error != "":
			return error + ":" + str(profile.get("occupation_id", ""))
		if Recipe.enabled(profile):
			_compile_product_traits(profile, registry)
	return ""


static func _apply_rules(profile: Dictionary, config: Dictionary, registry: Variant) -> Array:
	profile["work_recipe"] = {"version": 1, "recipe_id": "recipe." + str(profile.occupation_id), "item_inputs": [], "tools": []}
	var tools: Array = []
	for override: Dictionary in config.get("overrides", []):
		var applies: bool = profile.products.any(func(p: Dictionary) -> bool: return Recipe.matches(registry.get_definition("item", str(p.item_def_id)), override.product_query))
		if not applies:
			continue
		if override.has("products"):
			profile["products"] = override.products.duplicate(true)
		profile["work_recipe"] = override.get("work_recipe", profile.work_recipe).duplicate(true)
		if override.has("label"):
			profile["label"] = str(override.label)
		tools = override.get("initial_tools", []).duplicate(true)
	_compile_product_traits(profile, registry)
	return tools


static func _compile_product_traits(profile: Dictionary, registry: Variant) -> void:
	profile["work_output_food"] = profile.products.any(func(p: Dictionary) -> bool:
		var definition: Dictionary = registry.get_definition("item", str(p.item_def_id))
		return "food" in definition.get("tags", []) and "consume" in definition.get("capabilities", []))


static func _key(row: Dictionary) -> String:
	return "%s::%s" % [row.get("settlement_id", ""), row.get("occupation_id", "")]
