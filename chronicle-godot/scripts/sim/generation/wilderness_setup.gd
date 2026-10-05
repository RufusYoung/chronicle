extends RefCounted

const Rules = preload("res://scripts/sim/generation/journey_content_setup.gd")
const PATH := "res://data/sim/raw/content/echo_port_wilderness_v1.json"


static func load_rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))


static func enabled(fixture: Dictionary) -> bool:
	return fixture.get("wilderness_rules", {}).get("version") == 1


static func configure(fixture: Dictionary, registry: Variant) -> String:
	if not fixture.has("wilderness_rules"):
		return "wilderness_missing_rules" if fixture.has("wilderness_generated") else ""
	var pack: Variant = fixture.wilderness_rules
	if not pack is Dictionary or not Rules._integer(pack.get("version"), 1, 1) or not Rules._keys_valid(pack, ["version", "source_note", "sites"]) \
			or not pack.get("sites") is Array or pack.sites.is_empty():
		return "wilderness_rules_invalid"
	if fixture.get("journey_utility_rules", {}).get("version") != 1:
		return "wilderness_requires_utility_world"
	var ids := []
	for site: Variant in pack.sites:
		if not site is Dictionary or not Rules._keys_valid(site, ["id", "parent", "other_exit", "name", "description", "purpose", "hours", "other_hours", "period_hours", "features"]):
			return "wilderness_site_invalid"
		for key: String in ["id", "parent", "other_exit", "name", "description", "purpose"]:
			if not site.get(key) is String or str(site[key]).is_empty():
				return "wilderness_site_text_invalid"
		if not str(site.id).is_valid_identifier() or site.id in ids or not fixture.locations.has(site.parent) or not fixture.locations.has(site.other_exit) or site.parent == site.other_exit:
			return "wilderness_site_anchor_invalid"
		ids.append(site.id)
		if not Rules._integer(site.get("hours"), 1, 6) or not Rules._integer(site.get("other_hours"), 1, 6) or not Rules._integer(site.get("period_hours"), 3, 24):
			return "wilderness_site_timing_invalid"
		if not site.get("features") is Array or site.features.is_empty():
			return "wilderness_features_missing"
		var features := []
		for feature: Variant in site.features:
			if not feature is Dictionary or not Rules._keys_valid(feature, ["id", "name", "description", "exposure", "items"]):
				return "wilderness_feature_invalid"
			for key: String in ["id", "name", "description"]:
				if not feature.get(key) is String or str(feature[key]).is_empty():
					return "wilderness_feature_text_invalid"
			if not str(feature.id).is_valid_identifier() or feature.id in features or not Rules._integer(feature.get("exposure"), 0, 2) or not feature.get("items") is Array:
				return "wilderness_feature_shape_invalid"
			features.append(feature.id)
			var definitions := []
			for item: Variant in feature.items:
				if not item is Dictionary or not Rules._keys_valid(item, ["item_def_id", "maximum_quantity"]) \
						or not registry.has_definition("item", str(item.get("item_def_id", ""))) \
						or not Rules._integer(item.get("maximum_quantity"), 1, 8) or item.item_def_id in definitions:
					return "wilderness_stock_invalid"
				var definition: Dictionary = registry.get_definition("item", item.item_def_id)
				if item.maximum_quantity > 1 and not definition.get("stackable", false):
					return "wilderness_nonstack_quantity_invalid"
				definitions.append(item.item_def_id)
	if fixture.has("wilderness_generated"):
		var compiled: Variant = fixture.wilderness_generated
		if not compiled is Dictionary or not compiled.get("sites") is Dictionary:
			return "wilderness_compiled_invalid"
		for key: String in ["entity_ids", "item_ids", "route_ids"]:
			if not Rules._marks_valid(compiled.get(key)):
				return "wilderness_compiled_ids_invalid"
		return "" if compiled.get("signature") == signature(fixture) else "wilderness_signature_mismatch"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(fixture.get("challenge_seed", 1)) + 19471
	var compiled := {"sites": {}, "entity_ids": [], "item_ids": [], "route_ids": []}
	for site: Dictionary in pack.sites:
		var location := "wilderness_location." + str(site.id)
		if fixture.locations.has(location):
			return "wilderness_location_collision"
		fixture.locations[location] = {"id": location, "display_name": site.name, "description": site.description,
			"tags": ["wilderness_site", "generated_local_detail"], "journey_purpose": site.purpose,
			"canon_origin": fixture.locations[site.parent].get("canon_origin", {}).duplicate(true)}
		compiled.sites[site.id] = {"location_id": location, "phase_offset": rng.randi_range(0, int(site.period_hours) - 1), "features": {}}
		for exit: Array in [[site.parent, site.hours], [site.other_exit, site.other_hours]]:
			for pair: Array in [[exit[0], location], [location, exit[0]]]:
				var route := "wilderness_route." + str(pair[0]) + "." + str(pair[1])
				compiled.route_ids.append(route)
				fixture.travel_routes.append({"route_id": route, "from_location_id": pair[0], "to_location_id": pair[1],
					"hours": int(exit[1]), "food_cost": 0, "label": "前往" + str(fixture.locations[pair[1]].display_name),
					"narrative_title": "抵达", "narrative": fixture.locations[pair[1]].description})
		for feature: Dictionary in site.features:
			var owner := "wilderness_deposit." + str(site.id) + "." + str(feature.id)
			compiled.sites[site.id].features[feature.id] = owner
			compiled.entity_ids.append(owner)
			fixture.entities.append({"id": owner, "type": "environment_detail", "display_name": feature.name,
				"description": feature.description, "tags": ["wilderness_deposit"], "states": {"location_id": location, "visible": false}})
			for index: int in range(feature.items.size()):
				var entry: Dictionary = feature.items[index]
				var quantity := rng.randi_range(0, int(entry.maximum_quantity))
				if quantity == 0:
					continue
				var id := owner + ".item." + str(index)
				var definition: Dictionary = registry.get_definition("item", entry.item_def_id)
				var item := {"item_instance_id": id, "item_def_id": entry.item_def_id, "quantity": quantity,
					"holder": {"kind": "entity", "id": owner}, "provenance": {"source": "wilderness_initial_deposit_v1"}}
				var maximum := int(definition.get("durability", {}).get("maximum", 0))
				if maximum > 0:
					item["condition"] = {"maximum_durability": maximum, "durability": rng.randi_range(maxi(1, maximum / 3), maximum)}
				fixture.initial_items.append(item)
				compiled.item_ids.append(id)
	fixture["wilderness_generated"] = compiled
	compiled["signature"] = signature(fixture)
	return ""


static func signature(fixture: Dictionary) -> String:
	var compiled: Dictionary = fixture.wilderness_generated.duplicate(true)
	compiled.erase("signature")
	var places := {}
	for site: Dictionary in compiled.sites.values():
		places[site.location_id] = fixture.locations.get(site.location_id, {})
	var data := {"rules": fixture.wilderness_rules, "generated": compiled, "places": places,
		"entities": fixture.entities.filter(func(e: Dictionary) -> bool: return e.id in compiled.entity_ids),
		"items": fixture.initial_items.filter(func(i: Dictionary) -> bool: return i.item_instance_id in compiled.item_ids),
		"routes": fixture.travel_routes.filter(func(r: Dictionary) -> bool: return r.route_id in compiled.route_ids)}
	return JSON.stringify(JSON.parse_string(JSON.stringify(data)), "", true).sha256_text()
