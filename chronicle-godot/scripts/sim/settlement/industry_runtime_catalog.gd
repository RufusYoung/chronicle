extends RefCounted
class_name V5IndustryRuntimeCatalog


static func profiles(snapshot: Variant, initial_profiles: Array) -> Array:
	var rows: Dictionary = {}
	for profile: Dictionary in initial_profiles:
		rows[_key(profile)] = profile
	# Later facilities override retired predecessors without deleting their history.
	var facilities: Array = snapshot.get_entities().filter(
		func(entity: Dictionary) -> bool: return entity.has("industry_profile")
	)
	facilities.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("industry_founded_day", 0)) < int(b.get("industry_founded_day", 0))
	)
	for facility: Dictionary in facilities:
		var profile: Dictionary = facility.get("industry_profile", {})
		rows[_key(profile)] = profile
	var retired: Dictionary = {}
	for facility: Dictionary in snapshot.get_entities():
		if (
			str(snapshot.get_entity_state(str(facility.get("id", "")), "industry_status", ""))
			!= "retired"
		):
			continue
		var workplace := str(
			snapshot.get_entity_state(str(facility.get("id", "")), "location_id", "")
		)
		retired[workplace] = true
	var keys: Array = rows.keys()
	keys.sort()
	var result: Array = []
	for key: String in keys:
		var profile: Dictionary = rows[key]
		if not retired.has(str(profile.get("workplace_id", ""))):
			result.append(profile.duplicate(true))
	return result


static func routes(snapshot: Variant) -> Array:
	var rows: Array = []
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != "settlement_industry_founded":
			continue
		var id := str(fact.get("facility_entity_id", ""))
		var plot := str(fact.get("workplace_id", ""))
		var hub := str(fact.get("hub_location_id", ""))
		var retired := str(snapshot.get_entity_state(id, "industry_status", "active")) == "retired"
		var name := str(fact.get("facility_name", "产业设施")) + ("旧址" if retired else "")
		rows.append(
			{
				"route_id": id + ".visit",
				"from_location_id": hub,
				"to_location_id": plot,
				"label": "前往" + name,
				"hours": 1,
				"food_cost": 0
			}
		)
		rows.append(
			{
				"route_id": id + ".return",
				"from_location_id": plot,
				"to_location_id": hub,
				"label": "返回聚落集地",
				"hours": 1,
				"food_cost": 0
			}
		)
	return rows


static func location(snapshot: Variant, source: Dictionary) -> Dictionary:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) != "settlement_industry_founded"
			or str(fact.get("workplace_id", "")) != str(source.get("id", ""))
		):
			continue
		var id := str(fact.get("facility_entity_id", ""))
		var row := source.duplicate(true)
		var retired := str(snapshot.get_entity_state(id, "industry_status", "active")) == "retired"
		row["display_name"] = str(fact.get("facility_name", "产业设施")) + ("旧址" if retired else "")
		row["description"] = str(fact.get("facility_description", ""))
		if retired:
			for event: Dictionary in snapshot.get_facts():
				if (
					str(event.get("fact_type", "")) == "settlement_industry_retired"
					and str(event.get("target_id", "")) == id
				):
					row["description"] = str(event.get("summary", "这里已不再提供岗位。"))
		row["tags"] = ["generated_location", "generated_facility", "workplace"]
		return row
	return source


static func _key(profile: Dictionary) -> String:
	return "%s::%s" % [profile.get("settlement_id", ""), profile.get("occupation_id", "")]


static func validate_references(stores: Dictionary, locations: Dictionary, registry: Variant) -> String:
	for facility: Dictionary in stores["entity_store"].list_entity_rows():
		if not facility.has("industry_profile"):
			continue
		var id := str(facility.get("id", ""))
		var value: Variant = facility["industry_profile"]
		if not value is Dictionary:
			return "profile_not_dictionary:" + id
		var profile: Dictionary = value
		var settlement := str(profile.get("settlement_id", ""))
		var workplace := str(profile.get("workplace_id", ""))
		var fact: Dictionary = stores["fact_store"].get_fact(str(profile.get("industry_source_fact_id", "")))
		if (
			str(profile.get("facility_entity_id", "")) != id
			or not stores["entity_store"].has_entity(settlement)
			or not locations.has(workplace)
			or not locations.has(str(facility.get("industry_hub_id", "")))
			or workplace != str(stores["state_store"].get_state(id, "location_id", ""))
			or str(fact.get("fact_type", "")) != "settlement_industry_founded"
			or str(fact.get("facility_entity_id", "")) != id
			or str(fact.get("settlement_id", "")) != settlement
			or str(fact.get("workplace_id", "")) != workplace
			or str(fact.get("hub_location_id", "")) != str(facility.get("industry_hub_id", ""))
			or str(profile.get("occupation_id", "")) == ""
			or str(fact.get("occupation_id", "")) != str(profile.get("occupation_id", ""))
		):
			return "identity_or_founding_reference_invalid:" + id
		if not profile.get("resource_inputs") is Array or not profile.get("products") is Array:
			return "production_rows_invalid:" + id
		for input: Variant in profile["resource_inputs"]:
			if not input is Dictionary:
				return "resource_input_invalid:" + id
			var stock: Dictionary = stores["resource_stock_store"].get_stock(str(input.get("stock_id", "")))
			if stock.is_empty() or str(stock.get("settlement_id", "")) != settlement:
				return "resource_reference_invalid:" + id
			if float(input.get("amount_per_cycle", 0)) <= 0:
				return "resource_amount_invalid:" + id
		for product: Variant in profile["products"]:
			if not product is Dictionary:
				return "product_invalid:" + id
			if not registry.has_definition("item", str(product.get("item_def_id", ""))):
				return "product_definition_unknown:" + id
			if int(product.get("quantity", 0)) <= 0:
				return "product_quantity_invalid:" + id
	return ""
