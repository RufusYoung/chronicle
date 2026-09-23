extends RefCounted

const Recipe = preload("res://scripts/sim/economy/work_recipe_service.gd")
const WorkRules = preload("res://scripts/sim/economy/work_rules_setup.gd")
const DEFAULT_PATH := "res://data/sim/raw/content/echo_port_integration_v1.json"
const ADVENTURE_PATH := "res://data/sim/raw/content/echo_port_adventure_v1.json"


static func load_pack(version: int) -> Dictionary:
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	if version == 2:
		var adventure: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ADVENTURE_PATH))
		pack.version = 2
		pack.item_defs.append_array(adventure.item_defs)
		pack.recipes.append_array(adventure.recipes)
		pack["feature_defs"] = adventure.feature_defs
		pack["combat_wear_version"] = adventure.combat_wear_version
	return pack


static func validate(pack: Variant) -> String:
	if not pack is Dictionary or not Recipe._integer(pack.get("version"), 1) or int(pack.version) not in [1, 2]:
		return "unsupported_world_integration"
	for key: String in ["equipment_enabled", "negotiation_enabled", "livelihood_enabled"]:
		if not pack.get(key) is bool:
			return "invalid_integration_flag:" + key
	if not pack.get("item_defs") is Array or not pack.get("recipes") is Array or not pack.get("maintenance") is Dictionary:
		return "invalid_integration_definitions"
	if pack.has("combat_wear_version") and (pack.version != 2 or not Recipe._integer(pack.combat_wear_version, 1) or int(pack.combat_wear_version) != 1):
		return "invalid_combat_wear_version"
	var forage: Variant = pack.get("threat_foraging")
	if not forage is Dictionary or not forage.get("resource_tags_all") is Array or forage.resource_tags_all.is_empty() \
			or not forage.resource_tags_all.all(func(tag: Variant) -> bool: return tag is String and not tag.is_empty()) \
			or not (forage.get("amount") is int or forage.get("amount") is float) or not is_finite(float(forage.amount)) or float(forage.amount) <= 0 \
			or not Recipe._integer(forage.get("work_hours"), 1) or not Recipe._integer(forage.get("sated_hours"), 1):
		return "invalid_threat_foraging"
	return ""


static func register_items(fixture: Dictionary, registry: Variant) -> String:
	if not fixture.has("integration_rules"):
		return ""
	var error := validate(fixture.integration_rules)
	if error != "":
		return error
	if fixture.integration_rules.version == 2:
		if not fixture.integration_rules.get("feature_defs") is Dictionary:
			return "missing_adventure_features"
		for kind: String in fixture.integration_rules.feature_defs:
			if kind not in ["skill", "trait"] or not fixture.integration_rules.feature_defs[kind] is Array:
				return "invalid_adventure_feature_kind"
			for definition: Dictionary in fixture.integration_rules.feature_defs[kind]:
				var id := str(definition.get(kind + "_def_id", ""))
				if registry.has_definition(kind, id) or not registry.register_definition(kind, id, definition):
					return "invalid_adventure_feature:" + id
	for definition: Variant in fixture.integration_rules.item_defs:
		if not definition is Dictionary or registry.has_definition("item", str(definition.get("item_def_id", ""))) \
				or not registry.register_definition("item", str(definition.get("item_def_id", "")), definition):
			return "invalid_integration_item"
		if definition.get("equip_slots", []).is_empty() or not definition.get("modifiers", []).any(func(m: Dictionary) -> bool:
			return m.get("target") in ["combat.attack", "combat.guard", "combat.escape"] and m.get("operation") == "add" and float(m.get("value", 0)) > 0):
			return "integration_gear_without_consumer"
	return ""


static func configure(fixture: Dictionary, registry: Variant) -> String:
	var pack: Dictionary = fixture.get("integration_rules", {})
	if pack.is_empty():
		return "integration_missing_bootstrap" if fixture.has("integration_generated") else ""
	var signature := {"version": pack.version, "definition_hash": JSON.stringify(JSON.parse_string(JSON.stringify(pack)), "", true).sha256_text()}
	if fixture.has("integration_generated"):
		signature["compiled_hash"] = _compiled_hash(fixture)
		if fixture.integration_generated != signature:
			return "integration_signature_mismatch:" + str([fixture.integration_generated, signature])
		if fixture.resident_daily_life.get("integration_rules", {}) != pack:
			return "integration_compiled_rules_mismatch"
		return ""
	if not fixture.has("body_rules") or not fixture.has("community_generated") or not fixture.has("world_danger_generated"):
		return "integration_requires_body_community_danger"
	var produced := {}
	for profile: Dictionary in fixture.generated_livelihood_profiles:
		if not profile.products.any(func(p: Dictionary) -> bool: return "rope" in registry.get_definition("item", p.item_def_id).get("tags", [])):
			continue
		if not profile.has("recipe_variants"):
			profile["recipe_variants"] = []
		for recipe: Dictionary in pack.recipes:
			profile.recipe_variants.append(recipe.duplicate(true))
			for product: Dictionary in recipe.get("products", []):
				produced[product.item_def_id] = true
		var error := Recipe.validate_profile(profile, registry)
		if error != "":
			return error
		var repair: Dictionary = profile.duplicate(true)
		repair.erase("recipe_variants")
		repair.merge(pack.maintenance, true)
		repair["products"] = []
		repair["occupation_id"] = "maintenance"
		repair.work_recipe = repair.work_recipe.duplicate(true)
		repair.work_recipe.recipe_id += "." + str(profile.settlement_id)
		error = Recipe.validate_profile(repair, registry)
		if error != "":
			return error
		fixture.resident_daily_life.maintenance_profiles.append(repair)
	for definition: Dictionary in pack.item_defs:
		if not produced.has(definition.item_def_id):
			return "integration_gear_not_producible"
	fixture.resident_daily_life["integration_rules"] = pack.duplicate(true)
	fixture.resident_daily_life.activity_choice["integration_version"] = 1
	fixture.resident_daily_life.activity_choice["equipment_integration"] = pack.equipment_enabled
	fixture.resident_daily_life.activity_choice["livelihood_integration"] = pack.livelihood_enabled
	fixture.resident_daily_life.food_access.subsistence["integration_version"] = 1 if pack.livelihood_enabled else 0
	if pack.livelihood_enabled:
		fixture.resident_daily_life.food_access.subsistence["unavailable_quote_version"] = 1
	fixture.resident_daily_life.world_danger["integration_version"] = 1
	fixture.world_danger["integration_version"] = 1
	if pack.get("combat_wear_version") == 1:
		fixture.world_danger["combat_wear_version"] = 1
		fixture.resident_daily_life.world_danger["combat_wear_version"] = 1
	if pack.livelihood_enabled:
		fixture.world_danger["foraging"] = pack.threat_foraging.duplicate(true)
		fixture.resident_daily_life.world_danger["foraging"] = pack.threat_foraging.duplicate(true)
	fixture.community_rules["negotiation_version"] = 1 if pack.negotiation_enabled else 0
	fixture.resident_daily_life.community_rules = fixture.community_rules.duplicate(true)
	fixture.resident_daily_life.food_access.community_rules = fixture.community_rules.duplicate(true)
	for actor: Dictionary in fixture.entities:
		if "generated_resident" in actor.get("tags", []):
			actor.states["equipment_autonomy_version"] = 1 if pack.equipment_enabled else 0
		if "world_threat" in actor.get("tags", []) and pack.livelihood_enabled:
			actor["foraging_rules"] = pack.threat_foraging.duplicate(true)
	var compiled_error := WorkRules._validate_profiles(fixture, registry)
	if compiled_error != "":
		return compiled_error
	signature["compiled_hash"] = _compiled_hash(fixture)
	fixture["integration_generated"] = signature
	return ""


static func _compiled_hash(fixture: Dictionary) -> String:
	var daily: Dictionary = fixture.get("resident_daily_life", {})
	var compiled := {"profiles": fixture.get("generated_livelihood_profiles", []),
		"maintenance": daily.get("maintenance_profiles", []), "choice": daily.get("activity_choice", {}),
		"subsistence": daily.get("food_access", {}).get("subsistence", {}),
		"danger": fixture.get("world_danger", {}), "daily_danger": daily.get("world_danger", {}),
		"community": fixture.get("community_rules", {}), "daily_community": daily.get("community_rules", {}),
		"food_community": daily.get("food_access", {}).get("community_rules", {})}
	return JSON.stringify(JSON.parse_string(JSON.stringify(compiled)), "", true).sha256_text()


static func validate_save(fixture: Dictionary, stores: Dictionary) -> String:
	var actors := {}
	var pack: Dictionary = fixture.get("integration_rules", {})
	for entity: Dictionary in stores.entity_store.list_entity_rows():
		if entity.has("foraging_rules") and (not pack.get("livelihood_enabled", false) \
				or entity.id not in fixture.get("world_danger_generated", {}).get("threat_ids", [])):
			return "save_threat_foraging_without_bootstrap"
	if not pack.is_empty():
		for actor: Dictionary in fixture.entities:
			if "generated_resident" in actor.get("tags", []):
				actors[actor.id] = 1 if pack.equipment_enabled else 0
			if "world_threat" in actor.get("tags", []) and pack.livelihood_enabled:
				if stores.entity_store.get_entity(str(actor.id)).get("foraging_rules") != pack.threat_foraging:
					return "save_threat_foraging_rules_mismatch"
	for id: String in stores.state_store.states:
		var state: Dictionary = stores.state_store.states[id]
		if actors.has(id) and state.get("equipment_autonomy_version") != actors[id]:
			return "save_equipment_autonomy_mismatch"
		if not actors.has(id) and state.has("equipment_autonomy_version"):
			return "save_equipment_autonomy_without_bootstrap"
		if state.has("threat_foraging_hours"):
			if not pack.get("livelihood_enabled", false) or id not in fixture.get("world_danger_generated", {}).get("threat_ids", []) \
					or not Recipe._integer(state.threat_foraging_hours, 0) or int(state.threat_foraging_hours) > int(pack.threat_foraging.work_hours):
				return "save_threat_foraging_invalid"
	return ""
