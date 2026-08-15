extends RefCounted
class_name V5SettlementGenerator


func generate_fixture(
		source_fixture: Dictionary,
		config: Dictionary,
		definition: Dictionary
) -> Dictionary:
	if source_fixture.is_empty() or config.is_empty() or definition.is_empty():
		return _failure("generation_input_missing")
	if source_fixture.has("settlement_generation_result"):
		var existing_report: Dictionary = source_fixture.get(
			"settlement_generation_result", {}
		)
		var existing_integrity := _validate_generated_fixture(
			source_fixture, existing_report
		)
		if not bool(existing_integrity.get("ok", false)):
			return _failure(
				"existing_generated_fixture_integrity_invalid:%s" % ",".join(
					existing_integrity.get("errors", [])
				)
			)
		existing_report["integrity"] = existing_integrity
		return {
			"ok": true,
			"fixture": source_fixture.duplicate(true),
			"report": existing_report.duplicate(true),
		}

	var fixture := source_fixture.duplicate(true)
	var seed := int(config.get("seed", fixture.get("challenge_seed", 1)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var terrain: Dictionary = config.get("terrain", {})
	var terrain_id := str(terrain.get("terrain_id", ""))
	var terrain_profile := _terrain_profile(
		definition.get("terrain_profiles", []), terrain_id
	)
	if terrain_profile.is_empty():
		return _failure("terrain_profile_unknown:%s" % terrain_id)
	var resources := _dictionary_rows(config.get("resources", []))
	if resources.is_empty():
		return _failure("resource_inputs_missing")
	var traffic := _dictionary_rows(config.get("traffic", []))
	if traffic.is_empty():
		return _failure("traffic_inputs_missing")

	var capacity_data := _capacity_data(
		terrain, terrain_profile, resources, traffic, rng
	)
	var resident_capacity := int(capacity_data.get("resident_capacity", 0))
	var size_band := _size_band(
		definition.get("size_bands", []), resident_capacity
	)
	if size_band.is_empty():
		return _failure("size_band_missing")
	var industries := _industry_rows(
		definition.get("industry_archetypes", []),
		terrain,
		terrain_profile,
		resources,
		traffic,
		rng
	)
	var facility_limit := mini(
		int(size_band.get("facility_count", 3)), industries.size()
	)
	if facility_limit < 2:
		return _failure("insufficient_industry_candidates")
	industries = industries.slice(0, facility_limit)

	var fixture_token := _safe_id(str(fixture.get("fixture_id", "world")))
	var site_token := _safe_id(str(config.get("site_id", fixture_token)))
	var settlement_id := "generated_settlement.%s" % site_token
	var hub_id := "generated_location.%s.commons" % site_token
	var settlement_name := _settlement_name(definition, terrain_profile, rng)
	var generation_id := "%s:%d" % [
		str(definition.get(
			"generation_def_id", "generation.settlement"
		)),
		seed,
	]
	var batch_fact_id := "fact.generated_settlement.%s.%d" % [site_token, seed]
	var resource_stocks := _resource_stock_rows(
		resources,
		traffic,
		site_token,
		settlement_id,
		hub_id,
		seed,
		batch_fact_id
	)
	var locations := _location_dictionary(fixture.get("locations", {}))
	var entities: Array = (fixture.get("entities", []) as Array).duplicate(true)
	var facts: Array = (fixture.get("known_facts", []) as Array).duplicate(true)
	var chronicles: Array = (
		fixture.get("initial_chronicle_entries", []) as Array
	).duplicate(true)
	var routes: Array = (
		fixture.get("travel_routes", []) as Array
	).duplicate(true)
	var generated_location_ids: Array[String] = [hub_id]
	var generated_route_ids: Array[String] = []
	var generated_entity_ids: Array[String] = [settlement_id]
	var workplace_bindings := {}
	var livelihood_resource_bindings := {}
	var active_occupation_ids: Array[String] = []

	locations[hub_id] = {
		"id": hub_id,
		"display_name": "%s集地" % settlement_name,
		"description": _hub_description(
			settlement_name,
			terrain_profile,
			resident_capacity,
			industries
		),
		"tags": [
			"settlement", "generated_location", "public_space",
			str(size_band.get("id", "hamlet")), terrain_id,
		],
		"generation_source": {
			"generation_seed": seed,
			"settlement_id": settlement_id,
			"terrain_id": terrain_id,
			"resident_capacity": resident_capacity,
		},
	}
	entities.append({
		"id": settlement_id,
		"type": "institution",
		"display_name": settlement_name,
		"description": "由场址承载力、资源和交通条件生成的%s。" % str(
			size_band.get("label", "聚落")
		),
		"location_id": hub_id,
		"tags": [
			"settlement", "generated_settlement",
			str(size_band.get("id", "hamlet")),
		],
		"states": {
			"visible": false,
			"resident_capacity": resident_capacity,
			"population_target": int(capacity_data.get(
				"population_target", resident_capacity
			)),
			"terrain_id": terrain_id,
			"size_band": str(size_band.get("id", "hamlet")),
		},
	})
	var layout_feature_id := "generated_feature.%s.layout" % site_token
	entities.append({
		"id": layout_feature_id,
		"type": "trace",
		"display_name": "%s的道路与设施布局" % settlement_name,
		"description": "道路从公共集地伸向实际生产设施，远近和数量反映了场址资源与交通条件。",
		"location_id": hub_id,
		"tags": [
			"trace", "generated_settlement_layout", "inspectable_site",
		],
		"states": {"visible": true, "inspectable": true},
	})
	generated_entity_ids.append(layout_feature_id)

	for industry: Dictionary in industries:
		var industry_id := str(industry.get("industry_id", "industry"))
		var facility: Dictionary = industry.get("facility", {})
		var facility_id := "generated_location.%s.%s" % [
			site_token, _safe_id(str(facility.get("id", industry_id)))
		]
		var facility_name := "%s%s" % [
			settlement_name,
			str(facility.get("name_suffix", industry.get("label", "作业地"))),
		]
		var feature_id := "generated_feature.%s.%s" % [site_token, industry_id]
		var resource_binding := _bind_industry_resource(
			industry,
			resource_stocks,
			facility_id,
			feature_id
		)
		var bound_stock_ids: Array = []
		if not resource_binding.is_empty():
			bound_stock_ids.append(str(resource_binding.get("stock_id", "")))
		var tags: Array = [
			"workplace", "generated_location", "generated_facility",
			"industry_%s" % industry_id,
		]
		tags.append_array((facility.get("tags", []) as Array).duplicate(true))
		locations[facility_id] = {
			"id": facility_id,
			"display_name": facility_name,
			"description": str(facility.get(
				"description", "这处设施由场址条件生成。"
			)),
			"tags": tags,
			"generation_source": {
				"generation_seed": seed,
				"industry_id": industry_id,
				"industry_score": int(industry.get("score", 0)),
				"source_ids": industry.get("source_ids", []).duplicate(true),
				"resource_stock_ids": bound_stock_ids.duplicate(true),
			},
		}
		generated_location_ids.append(facility_id)
		entities.append({
			"id": feature_id,
			"type": "trace",
			"display_name": facility_name,
			"description": str(facility.get(
				"observation", facility.get("description", "")
			)),
			"location_id": facility_id,
			"tags": tags.duplicate(true),
			"states": {
				"visible": true,
				"inspectable": true,
				"resource_status": "abundant",
				"facility_operational": true,
				"resource_stock_ids": bound_stock_ids.duplicate(true),
			},
		})
		generated_entity_ids.append(feature_id)
		for occupation_value: Variant in industry.get("occupation_ids", []):
			var occupation_id := str(occupation_value)
			workplace_bindings[occupation_id] = facility_id
			if not resource_binding.is_empty():
				livelihood_resource_bindings[occupation_id] = [
					resource_binding.duplicate(true)
				]
			if occupation_id not in active_occupation_ids:
				active_occupation_ids.append(occupation_id)
		var route_pair := _facility_routes(
			site_token, hub_id, facility_id, facility_name, industry
		)
		for route: Dictionary in route_pair:
			routes.append(route)
			generated_route_ids.append(str(route.get("route_id", "")))

	facts.append({
		"fact_id": batch_fact_id,
		"fact_type": "settlement_generated",
		"actor_id": settlement_id,
		"target_id": settlement_id,
		"generation_id": generation_id,
		"generation_seed": seed,
		"settlement_name": settlement_name,
		"terrain_id": terrain_id,
		"size_band": str(size_band.get("id", "hamlet")),
		"resident_capacity": resident_capacity,
		"population_target": int(capacity_data.get("population_target", 0)),
		"source_ids": capacity_data.get("source_ids", []).duplicate(true),
	})
	for industry: Dictionary in industries:
		var industry_stock_ids := _industry_stock_ids(
			str(industry.get("industry_id", "")), resource_stocks
		)
		facts.append({
			"fact_id": "fact.generated_industry.%s.%s" % [
				site_token, str(industry.get("industry_id", ""))
			],
			"fact_type": "settlement_industry_selected",
			"actor_id": settlement_id,
			"target_id": settlement_id,
			"industry_id": str(industry.get("industry_id", "")),
			"industry_score": int(industry.get("score", 0)),
			"settlement_name": settlement_name,
			"source_ids": industry.get("source_ids", []).duplicate(true),
			"resource_stock_ids": industry_stock_ids,
			"source_fact_ids": [batch_fact_id],
		})
	for stock: Dictionary in resource_stocks:
		facts.append({
			"fact_id": str(stock.get("established_fact_id", "")),
			"fact_type": "settlement_resource_stock_established",
			"actor_id": settlement_id,
			"target_id": settlement_id,
			"stock_id": str(stock.get("stock_id", "")),
			"source_id": str(stock.get("source_id", "")),
			"resource_label": str(stock.get("label", "资源")),
			"capacity": float(stock.get("capacity", 0.0)),
			"recovery_per_hour": float(stock.get("recovery_per_hour", 0.0)),
			"source_fact_ids": [batch_fact_id],
			"generation_seed": seed,
		})

	var pressures := _derived_pressures(
		capacity_data, terrain, traffic, resident_capacity
	)
	var region_state: Dictionary = (
		fixture.get("region_state", {}) as Dictionary
	).duplicate(true)
	region_state.merge(pressures, true)
	var institution: Dictionary = (
		fixture.get("institution", {}) as Dictionary
	).duplicate(true)
	institution.merge({
		"market_order": (
			"stable" if int(capacity_data.get("traffic_capacity", 0)) >= 5
			else "informal"
		),
		"local_guard_attention": (
			"medium" if str(size_band.get("id", "hamlet")) != "hamlet"
			else "low"
		),
	}, true)
	chronicles.append({
		"entry_id": "chronicle.generated_settlement.%s.%d" % [site_token, seed],
		"subject_id": settlement_id,
		"title": "%s的立地记录" % settlement_name,
		"body": "%s依%s、%d 点资源支撑和 %d 点交通容量形成，可容纳约 %d 人，并首先形成%s。" % [
			settlement_name,
			str(terrain_profile.get("label", terrain_id)),
			int(capacity_data.get("resource_support", 0)),
			int(capacity_data.get("traffic_capacity", 0)),
			resident_capacity,
			_industry_labels(industries),
		],
		"source_fact_ids": [batch_fact_id],
		"generation_seed": seed,
	})

	var resident_config: Dictionary = (
		fixture.get("resident_generation", {}) as Dictionary
	).duplicate(true)
	if not resident_config.is_empty():
		resident_config["resident_count"] = int(capacity_data.get(
			"population_target", resident_capacity
		))
		resident_config["minimum_households"] = maxi(
			2, int(resident_config["resident_count"]) / 4
		)
		resident_config["maximum_households"] = maxi(
			int(resident_config["minimum_households"]),
			int(resident_config["resident_count"]) / 3
		)
		resident_config["settlement_id"] = settlement_id
		resident_config["settlement_name"] = settlement_name
		resident_config["workplace_bindings"] = workplace_bindings.duplicate(true)
		resident_config["livelihood_resource_bindings"] = (
			livelihood_resource_bindings.duplicate(true)
		)
		resident_config["active_occupation_ids"] = active_occupation_ids.duplicate(true)
		resident_config["require_active_occupations"] = true

	fixture["location_id"] = hub_id
	fixture["locations"] = locations
	fixture["entities"] = entities
	fixture["known_facts"] = facts
	fixture["initial_chronicle_entries"] = chronicles
	var accumulated_resource_stocks: Array = (
		fixture.get("initial_resource_stocks", []) as Array
	).duplicate(true)
	accumulated_resource_stocks.append_array(resource_stocks)
	fixture["initial_resource_stocks"] = accumulated_resource_stocks
	fixture["travel_routes"] = routes
	fixture["region_state"] = region_state
	fixture["institution"] = institution
	fixture["resident_generation"] = resident_config
	var report := {
		"ok": true,
		"generation_id": generation_id,
		"generation_seed": seed,
		"settlement_id": settlement_id,
		"settlement_name": settlement_name,
		"hub_location_id": hub_id,
		"terrain_id": terrain_id,
		"size_band": str(size_band.get("id", "hamlet")),
		"resident_capacity": resident_capacity,
		"population_target": int(capacity_data.get("population_target", 0)),
		"resource_support": int(capacity_data.get("resource_support", 0)),
		"food_support": int(capacity_data.get("food_support", 0)),
		"traffic_capacity": int(capacity_data.get("traffic_capacity", 0)),
		"industry_ids": _industry_ids(industries),
		"industry_scores": _industry_scores(industries),
		"generated_location_ids": generated_location_ids,
		"generated_route_ids": generated_route_ids,
		"generated_entity_ids": generated_entity_ids,
		"workplace_bindings": workplace_bindings.duplicate(true),
		"active_occupation_ids": active_occupation_ids.duplicate(true),
		"resource_stock_ids": _resource_stock_ids(resource_stocks),
		"resource_stock_summary": _resource_stock_summary(resource_stocks),
		"livelihood_resource_bindings": (
			livelihood_resource_bindings.duplicate(true)
		),
		"derived_pressures": pressures.duplicate(true),
		"signature": _signature(
			resident_capacity,
			industries,
			generated_location_ids,
			pressures,
			resource_stocks
		),
	}
	var integrity := _validate_generated_fixture(fixture, report)
	report["integrity"] = integrity
	if not bool(integrity.get("ok", false)):
		return _failure("generated_fixture_integrity_invalid:%s" % ",".join(
			integrity.get("errors", [])
		))
	fixture["settlement_generation_result"] = report.duplicate(true)
	return {"ok": true, "fixture": fixture, "report": report}


func _resource_stock_rows(
		resources: Array[Dictionary],
		traffic: Array[Dictionary],
		site_token: String,
		settlement_id: String,
		hub_id: String,
		seed: int,
		batch_fact_id: String
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for resource: Dictionary in resources:
		var abundance := clampi(int(resource.get("abundance", 0)), 0, 5)
		var reliability := clampi(int(resource.get("reliability", 0)), 0, 5)
		var source_id := str(resource.get("resource_id", "resource"))
		var stock_id := "resource_stock.%s.%s" % [
			site_token, _safe_id(source_id)
		]
		var capacity := float(maxi(abundance * 8 + reliability * 2, 4))
		rows.append({
			"stock_id": stock_id,
			"source_id": source_id,
			"source_kind": "natural_resource",
			"settlement_id": settlement_id,
			"location_id": hub_id,
			"label": str(resource.get(
				"label", _resource_label(resource.get("tags", []), source_id)
			)),
			"tags": (resource.get("tags", []) as Array).duplicate(true),
			"capacity": capacity,
			"current": capacity,
			"recovery_per_hour": _rounded(maxf(
				float(abundance * reliability) / 24.0, 0.04
			)),
			"operating_floor": 1.0,
			"status": "abundant",
			"abundance": abundance,
			"reliability": reliability,
			"industry_ids": [],
			"facility_entity_ids": [],
			"source_fact_ids": [batch_fact_id],
			"established_fact_id": "fact.resource_stock.%s.%s" % [
				site_token, _safe_id(source_id)
			],
			"generation_seed": seed,
			"change_count": 0,
			"last_tick": 0,
		})
	for route: Dictionary in traffic:
		var route_capacity := clampi(int(route.get("capacity", 0)), 0, 5)
		var reliability := clampi(int(route.get("reliability", 0)), 0, 5)
		var source_id := str(route.get("traffic_id", "traffic"))
		var mode := str(route.get("mode", "road"))
		var stock_id := "resource_stock.%s.%s" % [
			site_token, _safe_id(source_id)
		]
		var capacity := float(maxi(route_capacity * 8 + reliability * 2, 4))
		rows.append({
			"stock_id": stock_id,
			"source_id": source_id,
			"source_kind": "traffic_capacity",
			"settlement_id": settlement_id,
			"location_id": hub_id,
			"label": str(route.get("label", "%s运力" % _traffic_label(mode))),
			"tags": ["traffic", "transport", mode],
			"capacity": capacity,
			"current": capacity,
			"recovery_per_hour": _rounded(maxf(
				float(route_capacity * reliability) / 24.0, 0.04
			)),
			"operating_floor": 1.0,
			"status": "abundant",
			"abundance": route_capacity,
			"reliability": reliability,
			"industry_ids": [],
			"facility_entity_ids": [],
			"source_fact_ids": [batch_fact_id],
			"established_fact_id": "fact.resource_stock.%s.%s" % [
				site_token, _safe_id(source_id)
			],
			"generation_seed": seed,
			"change_count": 0,
			"last_tick": 0,
		})
	return rows


func _bind_industry_resource(
		industry: Dictionary,
		stocks: Array[Dictionary],
		facility_id: String,
		feature_id: String
) -> Dictionary:
	var input: Dictionary = industry.get("stock_input", {})
	if input.is_empty():
		return {}
	var source_kind := str(input.get("source_kind", "natural_resource"))
	var tags_any: Array = input.get("tags_any", [])
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in stocks:
		if str(stock.get("source_kind", "")) != source_kind:
			continue
		if not tags_any.is_empty() and not _has_any_tag(
			stock.get("tags", []), tags_any
		):
			continue
		candidates.append(stock)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := int(a.get("reliability", 0)) * 10 + int(a.get("abundance", 0))
		var right := int(b.get("reliability", 0)) * 10 + int(b.get("abundance", 0))
		if left != right:
			return left > right
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	var selected_id := str(candidates[0].get("stock_id", ""))
	var amount := maxf(float(input.get("amount_per_cycle", 1.0)), 0.1)
	var selected_label := str(candidates[0].get("label", "生产资源"))
	for index: int in range(stocks.size()):
		if str(stocks[index].get("stock_id", "")) != selected_id:
			continue
		var updated := stocks[index].duplicate(true)
		updated["location_id"] = facility_id
		updated["operating_floor"] = maxf(
			float(updated.get("operating_floor", 1.0)), amount
		)
		var industry_ids: Array = updated.get("industry_ids", [])
		var industry_id := str(industry.get("industry_id", ""))
		if industry_id not in industry_ids:
			industry_ids.append(industry_id)
		updated["industry_ids"] = industry_ids
		var facility_ids: Array = updated.get("facility_entity_ids", [])
		if feature_id not in facility_ids:
			facility_ids.append(feature_id)
		updated["facility_entity_ids"] = facility_ids
		stocks[index] = updated
		break
	return {
		"stock_id": selected_id,
		"label": selected_label,
		"amount_per_cycle": amount,
	}


func _has_any_tag(source: Variant, expected: Array) -> bool:
	if not source is Array:
		return false
	for value: Variant in source:
		if str(value) in expected:
			return true
	return false


func _industry_stock_ids(
		industry_id: String, stocks: Array[Dictionary]
) -> Array[String]:
	var ids: Array[String] = []
	for stock: Dictionary in stocks:
		if industry_id in (stock.get("industry_ids", []) as Array):
			ids.append(str(stock.get("stock_id", "")))
	return ids


func _resource_stock_ids(stocks: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for stock: Dictionary in stocks:
		ids.append(str(stock.get("stock_id", "")))
	return ids


func _resource_stock_summary(stocks: Array[Dictionary]) -> Array:
	var rows: Array = []
	for stock: Dictionary in stocks:
		rows.append({
			"stock_id": str(stock.get("stock_id", "")),
			"label": str(stock.get("label", "资源")),
			"source_kind": str(stock.get("source_kind", "")),
			"capacity": float(stock.get("capacity", 0.0)),
			"recovery_per_hour": float(stock.get("recovery_per_hour", 0.0)),
			"industry_ids": (
				stock.get("industry_ids", []) as Array
			).duplicate(true),
		})
	return rows


func _resource_label(tags_value: Variant, source_id: String) -> String:
	var tags: Array = tags_value if tags_value is Array else []
	for tag: String in ["fish", "soil", "reeds", "brine", "salt"]:
		if tag in tags:
			return {
				"fish": "近岸鱼群",
				"soil": "坡田地力",
				"reeds": "泽岸苇草",
				"brine": "浅层卤水",
				"salt": "浅层卤水",
			}.get(tag, source_id)
	return source_id


func _traffic_label(mode: String) -> String:
	return {"road": "道路", "waterway": "水路"}.get(mode, mode)


func _rounded(value: float) -> float:
	return round(value * 1000.0) / 1000.0


func _capacity_data(
		terrain: Dictionary,
		terrain_profile: Dictionary,
		resources: Array[Dictionary],
		traffic: Array[Dictionary],
		rng: RandomNumberGenerator
) -> Dictionary:
	var resource_support := 0
	var food_support := 0
	var source_ids: Array[String] = []
	for resource: Dictionary in resources:
		var abundance := clampi(int(resource.get("abundance", 0)), 0, 5)
		var reliability := clampi(int(resource.get("reliability", 0)), 0, 5)
		var support := int(round(float(abundance * reliability) / 3.0))
		resource_support += support
		if "food" in (resource.get("tags", []) as Array):
			food_support += support
		source_ids.append(str(resource.get("resource_id", "resource")))
	var traffic_capacity := 0
	for route: Dictionary in traffic:
		traffic_capacity += clampi(int(route.get("capacity", 0)), 0, 5)
		source_ids.append(str(route.get("traffic_id", "traffic")))
	var habitable_area := clampi(int(terrain.get("habitable_area", 1)), 1, 6)
	var resident_capacity := (
		int(terrain_profile.get("base_capacity", 4))
		+ habitable_area * 2
		+ resource_support
		+ traffic_capacity
		+ rng.randi_range(-2, 2)
	)
	resident_capacity = clampi(resident_capacity, 6, 36)
	var population_target := clampi(
		int(round(float(resident_capacity) * 0.72)) + rng.randi_range(-1, 1),
		6,
		resident_capacity
	)
	return {
		"resident_capacity": resident_capacity,
		"population_target": population_target,
		"resource_support": resource_support,
		"food_support": food_support,
		"traffic_capacity": traffic_capacity,
		"source_ids": source_ids,
	}


func _industry_rows(
		archetypes: Array,
		terrain: Dictionary,
		terrain_profile: Dictionary,
		resources: Array[Dictionary],
		traffic: Array[Dictionary],
		rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var terrain_tags: Array = (terrain.get("tags", []) as Array).duplicate(true)
	terrain_tags.append_array((terrain_profile.get("tags", []) as Array).duplicate(true))
	for archetype_value: Variant in archetypes:
		if not archetype_value is Dictionary:
			continue
		var archetype := (archetype_value as Dictionary).duplicate(true)
		if not _industry_inputs_available(archetype, resources, traffic):
			continue
		var score := int(archetype.get("base_score", 0))
		var source_ids: Array[String] = []
		var terrain_weights: Dictionary = archetype.get("terrain_tag_weights", {})
		for tag_value: Variant in terrain_tags:
			var tag := str(tag_value)
			if terrain_weights.has(tag):
				score += int(terrain_weights[tag])
				source_ids.append("terrain:%s" % tag)
		var resource_weights: Dictionary = archetype.get("resource_tag_weights", {})
		for resource: Dictionary in resources:
			var contribution := 0
			for tag_value: Variant in resource.get("tags", []):
				var tag := str(tag_value)
				if resource_weights.has(tag):
					contribution += int(resource_weights[tag])
			if contribution > 0:
				score += contribution * clampi(
					int(resource.get("abundance", 0)), 0, 5
				)
				source_ids.append(str(resource.get("resource_id", "resource")))
		var traffic_weights: Dictionary = archetype.get("traffic_mode_weights", {})
		for route: Dictionary in traffic:
			var mode := str(route.get("mode", ""))
			if traffic_weights.has(mode):
				score += int(traffic_weights[mode]) * clampi(
					int(route.get("capacity", 0)), 0, 5
				)
				source_ids.append(str(route.get("traffic_id", "traffic")))
		score += rng.randi_range(0, 2)
		archetype["score"] = score
		archetype["source_ids"] = source_ids
		rows.append(archetype)
	rows.sort_custom(_industry_precedes)
	return rows


func _industry_inputs_available(
		archetype: Dictionary,
		resources: Array[Dictionary],
		traffic: Array[Dictionary]
) -> bool:
	var required_resource_tags: Array = archetype.get(
		"required_any_resource_tags", []
	)
	if not required_resource_tags.is_empty():
		var resource_found := false
		for resource: Dictionary in resources:
			if int(resource.get("abundance", 0)) <= 0:
				continue
			for tag_value: Variant in resource.get("tags", []):
				if str(tag_value) in required_resource_tags:
					resource_found = true
					break
			if resource_found:
				break
		if not resource_found:
			return false
	var required_traffic_modes: Array = archetype.get(
		"required_any_traffic_modes", []
	)
	if not required_traffic_modes.is_empty():
		var traffic_found := false
		for route: Dictionary in traffic:
			if (
				int(route.get("capacity", 0)) > 0
				and str(route.get("mode", "")) in required_traffic_modes
			):
				traffic_found = true
				break
		if not traffic_found:
			return false
	return true


func _industry_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_score := int(left.get("score", 0))
	var right_score := int(right.get("score", 0))
	if left_score != right_score:
		return left_score > right_score
	return str(left.get("industry_id", "")) < str(right.get("industry_id", ""))


func _derived_pressures(
		capacity_data: Dictionary,
		terrain: Dictionary,
		traffic: Array[Dictionary],
		resident_capacity: int
) -> Dictionary:
	var population_target := int(capacity_data.get("population_target", 0))
	var food_support := int(capacity_data.get("food_support", 0))
	var traffic_capacity := int(capacity_data.get("traffic_capacity", 0))
	var food_pressure := "high"
	if food_support * 2 >= population_target:
		food_pressure = "low"
	elif food_support * 3 >= population_target:
		food_pressure = "medium"
	var isolation := "high"
	if traffic_capacity >= 6:
		isolation = "low"
	elif traffic_capacity >= 3:
		isolation = "medium"
	var route_risk := 0
	for route: Dictionary in traffic:
		route_risk += clampi(int(route.get("risk", 0)), 0, 5)
	return {
		"food_pressure": food_pressure,
		"public_order": "stable" if route_risk <= 4 else "strained",
		"settlement_isolation": isolation,
		"resource_strain": (
			"low"
			if int(capacity_data.get("resource_support", 0)) * 2 >= resident_capacity
			else "medium"
		),
		"flood_risk": (
			"high"
			if int(terrain.get("flood_exposure", 0)) >= 4
			else "medium" if int(terrain.get("flood_exposure", 0)) >= 2
			else "low"
		),
	}


func _facility_routes(
		site_token: String,
		hub_id: String,
		facility_id: String,
		facility_name: String,
		industry: Dictionary
) -> Array[Dictionary]:
	var industry_id := str(industry.get("industry_id", "industry"))
	var hours := maxi(int(industry.get("travel_hours", 1)), 1)
	return [
		{
			"route_id": "generated_route.%s.commons_to_%s" % [
				site_token, industry_id
			],
			"from_location_id": hub_id,
			"to_location_id": facility_id,
			"label": "前往%s" % facility_name,
			"hours": hours,
			"food_cost": 0,
			"narrative_title": "聚落里的短路",
			"narrative": "你沿着居民反复走出的路来到%s。" % facility_name,
		},
		{
			"route_id": "generated_route.%s.%s_to_commons" % [
				site_token, industry_id
			],
			"from_location_id": facility_id,
			"to_location_id": hub_id,
			"label": "返回聚落集地",
			"hours": hours,
			"food_cost": 0,
			"narrative_title": "回到人声汇集处",
			"narrative": "你循着屋顶和炊烟的方向回到%s。" % facility_name.trim_suffix(
				str((industry.get("facility", {}) as Dictionary).get("name_suffix", ""))
			),
		},
	]


func _terrain_profile(archetypes: Array, terrain_id: String) -> Dictionary:
	for value: Variant in archetypes:
		if value is Dictionary and str((value as Dictionary).get(
			"terrain_id", ""
		)) == terrain_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _size_band(bands: Array, capacity: int) -> Dictionary:
	var fallback := {}
	for value: Variant in bands:
		if not value is Dictionary:
			continue
		var band := value as Dictionary
		fallback = band
		if capacity <= int(band.get("maximum_capacity", capacity)):
			return band.duplicate(true)
	return fallback.duplicate(true)


func _settlement_name(
		definition: Dictionary,
		terrain_profile: Dictionary,
		rng: RandomNumberGenerator
) -> String:
	var stems: Array = terrain_profile.get(
		"name_stems", definition.get("name_stems", ["新"])
	)
	var suffixes: Array = definition.get("name_suffixes", ["村"])
	return "%s%s" % [
		str(stems[rng.randi_range(0, stems.size() - 1)]),
		str(suffixes[rng.randi_range(0, suffixes.size() - 1)]),
	]


func _hub_description(
		settlement_name: String,
		terrain_profile: Dictionary,
		resident_capacity: int,
		industries: Array[Dictionary]
) -> String:
	return "%s落在%s。这里能长期支撑约 %d 人，最先稳定下来的生计是%s；设施和人口均来自同一场址生成结果。" % [
		settlement_name,
		str(terrain_profile.get("description", "一块可居住的土地上")),
		resident_capacity,
		_industry_labels(industries),
	]


func _industry_labels(industries: Array[Dictionary]) -> String:
	var labels: Array[String] = []
	for industry: Dictionary in industries:
		labels.append(str(industry.get("label", industry.get("industry_id", "产业"))))
	return "、".join(labels)


func _industry_ids(industries: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for industry: Dictionary in industries:
		ids.append(str(industry.get("industry_id", "")))
	return ids


func _industry_scores(industries: Array[Dictionary]) -> Dictionary:
	var scores := {}
	for industry: Dictionary in industries:
		scores[str(industry.get("industry_id", ""))] = int(
			industry.get("score", 0)
		)
	return scores


func _dictionary_rows(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if value is Array:
		for row: Variant in value:
			if row is Dictionary:
				rows.append((row as Dictionary).duplicate(true))
	return rows


func _location_dictionary(value: Variant) -> Dictionary:
	var rows := {}
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			if (value as Dictionary)[key] is Dictionary:
				rows[str(key)] = ((value as Dictionary)[key] as Dictionary).duplicate(true)
	elif value is Array:
		for row: Variant in value:
			if row is Dictionary:
				var location_id := str((row as Dictionary).get("id", ""))
				if location_id != "":
					rows[location_id] = (row as Dictionary).duplicate(true)
	return rows


func _signature(
		capacity: int,
		industries: Array[Dictionary],
		location_ids: Array[String],
		pressures: Dictionary,
		resource_stocks: Array[Dictionary]
) -> String:
	return "%d|%s|%s|%s" % [
		capacity,
		",".join(_industry_ids(industries)),
		",".join(location_ids),
		"%s|%s" % [
			JSON.stringify(pressures, "", true),
			JSON.stringify(_resource_stock_summary(resource_stocks), "", true),
		],
	]


func _validate_generated_fixture(
		fixture: Dictionary, report: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	var locations := _location_dictionary(fixture.get("locations", {}))
	var entity_ids := {}
	for entity_value: Variant in fixture.get("entities", []):
		if not entity_value is Dictionary:
			continue
		var entity := entity_value as Dictionary
		var entity_id := str(entity.get("id", ""))
		if entity_id == "":
			errors.append("entity_id_missing")
			continue
		entity_ids[entity_id] = true
		if not locations.has(str(entity.get("location_id", ""))):
			errors.append("entity_location_missing:%s" % entity_id)
	for location_value: Variant in report.get("generated_location_ids", []):
		if not locations.has(str(location_value)):
			errors.append("generated_location_missing:%s" % str(location_value))
	for route_value: Variant in fixture.get("travel_routes", []):
		if not route_value is Dictionary:
			continue
		var route := route_value as Dictionary
		if not locations.has(str(route.get("from_location_id", ""))):
			errors.append("route_from_missing:%s" % str(route.get("route_id", "")))
		if not locations.has(str(route.get("to_location_id", ""))):
			errors.append("route_to_missing:%s" % str(route.get("route_id", "")))
	var settlement_id := str(report.get("settlement_id", ""))
	if settlement_id == "" or not entity_ids.has(settlement_id):
		errors.append("settlement_entity_missing")
	var resource_stock_ids := {}
	var reported_resource_stock_ids := {}
	for reported_stock_id: Variant in report.get("resource_stock_ids", []):
		reported_resource_stock_ids[str(reported_stock_id)] = true
	for stock_value: Variant in fixture.get("initial_resource_stocks", []):
		if not stock_value is Dictionary:
			errors.append("resource_stock_not_dictionary")
			continue
		var stock := stock_value as Dictionary
		var stock_id := str(stock.get("stock_id", ""))
		if stock_id == "" or resource_stock_ids.has(stock_id):
			errors.append("resource_stock_identity_invalid:%s" % stock_id)
			continue
		resource_stock_ids[stock_id] = true
		var stock_settlement_id := str(stock.get("settlement_id", ""))
		if not entity_ids.has(stock_settlement_id):
			errors.append("resource_stock_settlement_missing:%s" % stock_id)
		elif (
			reported_resource_stock_ids.has(stock_id)
			and stock_settlement_id != settlement_id
		):
			errors.append("resource_stock_settlement_invalid:%s" % stock_id)
		if not locations.has(str(stock.get("location_id", ""))):
			errors.append("resource_stock_location_missing:%s" % stock_id)
		for feature_id: Variant in stock.get("facility_entity_ids", []):
			if not entity_ids.has(str(feature_id)):
				errors.append("resource_stock_facility_missing:%s" % feature_id)
	for stock_id: Variant in report.get("resource_stock_ids", []):
		if not resource_stock_ids.has(str(stock_id)):
			errors.append("reported_resource_stock_missing:%s" % stock_id)
	var resident_config: Dictionary = fixture.get("resident_generation", {})
	var resource_bindings: Dictionary = resident_config.get(
		"livelihood_resource_bindings", {}
	)
	for occupation_id: String in resource_bindings.keys():
		for binding: Dictionary in resource_bindings[occupation_id]:
			if not resource_stock_ids.has(str(binding.get("stock_id", ""))):
				errors.append(
					"livelihood_resource_stock_missing:%s" % occupation_id
				)
	if not locations.has(str(fixture.get("location_id", ""))):
		errors.append("starting_location_missing")
	if int(report.get("population_target", 0)) > int(
		report.get("resident_capacity", 0)
	):
		errors.append("population_exceeds_capacity")
	return {"ok": errors.is_empty(), "errors": errors}


func _safe_id(value: String) -> String:
	var safe := value.to_lower()
	for character: String in [" ", ".", ":", "/", "\\"]:
		safe = safe.replace(character, "_")
	return safe


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "fixture": {}, "report": {}}
