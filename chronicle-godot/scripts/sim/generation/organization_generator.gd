extends RefCounted
class_name V5OrganizationGenerator


func generate_fixture(
		source_fixture: Dictionary,
		config: Dictionary,
		definition: Dictionary
) -> Dictionary:
	if source_fixture.is_empty() or config.is_empty() or definition.is_empty():
		return _failure("generation_input_missing")
	if source_fixture.has("organization_generation_result"):
		var existing_fixture := source_fixture.duplicate(true)
		var existing_report: Dictionary = (
			existing_fixture.get(
				"organization_generation_result", {}
			) as Dictionary
		).duplicate(true)
		var existing_integrity := _validate_generated_fixture(
			existing_fixture, existing_report
		)
		if not bool(existing_integrity.get("ok", false)):
			return _failure("existing_organization_generation_invalid:%s" % (
				",".join(existing_integrity.get("errors", []))
			))
		existing_report["integrity"] = existing_integrity
		existing_fixture["organization_generation_result"] = existing_report
		return {
			"ok": true,
			"fixture": existing_fixture,
			"report": existing_report,
		}

	var runtime: Dictionary = source_fixture.get(
		"settlement_network_runtime", {}
	)
	var sites := _dictionary_rows(runtime.get("sites", []))
	var prototypes := _dictionary_rows(definition.get("prototypes", []))
	if sites.is_empty() or prototypes.is_empty():
		return _failure("organization_sites_or_prototypes_missing")

	var fixture := source_fixture.duplicate(true)
	var seed := int(config.get(
		"seed", fixture.get("challenge_seed", 1)
	))
	var entities: Array = (fixture.get("entities", []) as Array).duplicate(true)
	var facts: Array = (fixture.get("known_facts", []) as Array).duplicate(true)
	var relationships: Dictionary = (
		fixture.get("initial_relationships", {}) as Dictionary
	).duplicate(true)
	var chronicles: Array = (
		fixture.get("initial_chronicle_entries", []) as Array
	).duplicate(true)
	var stocks: Array = (
		fixture.get("initial_resource_stocks", []) as Array
	).duplicate(true)
	var site_inputs := _site_inputs(fixture)
	var organization_ids: Array[String] = []
	var organization_rows: Array[Dictionary] = []
	var assigned_member_ids: Dictionary = {}

	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("site_id", "")) < str(b.get("site_id", ""))
	)
	for site: Dictionary in sites:
		var settlement_id := str(site.get("settlement_id", ""))
		var site_id := str(site.get("site_id", ""))
		var site_input: Dictionary = site_inputs.get(site_id, {})
		var industry_ids := _industry_ids(facts, settlement_id)
		var needs := _need_signals(site, site_input, runtime, industry_ids)
		var prototype := _select_prototype(
			prototypes, industry_ids, site_input, needs, seed, site_id
		)
		if prototype.is_empty():
			continue
		var organization_id := "generated_organization.%s.%s" % [
			_safe_id(site_id),
			_safe_id(str(prototype.get("prototype_id", "organization"))),
		]
		var positions := _assign_positions(
			entities,
			settlement_id,
			organization_id,
			prototype.get("positions", []),
			assigned_member_ids,
			seed
		)
		if positions.is_empty():
			return _failure("organization_positions_unfilled:%s" % organization_id)
		var founding_member_ids: Array[String] = []
		for position: Dictionary in positions:
			founding_member_ids.append(str(position.get("founding_holder_id", "")))
		var resource_stock_ids := _resource_stock_ids(
			stocks,
			settlement_id,
			prototype.get("resource_tags_any", []),
			int(config.get("maximum_resource_links", 3))
		)
		var source_fact_ids := _source_fact_ids(
			facts, settlement_id, industry_ids, resource_stock_ids
		)
		var settlement_name := _entity_name(entities, settlement_id)
		var organization_name := "%s%s" % [
			settlement_name,
			str(prototype.get("name_suffix", "议事会")),
		]
		var organization_fact_id := "fact.generated_organization.%s" % (
			_safe_id(organization_id)
		)
		entities.append({
			"id": organization_id,
			"type": "institution",
			"display_name": organization_name,
			"description": str(prototype.get(
				"description", "由聚落条件生成的地方组织。"
			)),
			"location_id": str(site.get("hub_location_id", "")),
			"tags": [
				"institution", "organization", "generated_organization",
				str(prototype.get("organization_kind", "local_association")),
			],
			"settlement_id": settlement_id,
			"organization_kind": str(prototype.get(
				"organization_kind", "local_association"
			)),
			"prototype_id": str(prototype.get("prototype_id", "")),
			"goal": str(prototype.get("goal", "")),
			"need_signals": needs.duplicate(true),
			"positions": positions.duplicate(true),
			"founding_member_ids": founding_member_ids.duplicate(),
			"resource_stock_ids": resource_stock_ids.duplicate(),
			"generation_seed": seed,
			"source_fact_ids": source_fact_ids.duplicate(),
			"states": {"visible": false},
		})
		facts.append({
			"fact_id": organization_fact_id,
			"fact_type": "organization_generated",
			"actor_id": settlement_id,
			"target_id": organization_id,
			"settlement_id": settlement_id,
			"organization_kind": str(prototype.get(
				"organization_kind", "local_association"
			)),
			"prototype_id": str(prototype.get("prototype_id", "")),
			"goal": str(prototype.get("goal", "")),
			"need_signals": needs.duplicate(true),
			"founding_member_ids": founding_member_ids.duplicate(),
			"resource_stock_ids": resource_stock_ids.duplicate(),
			"source_fact_ids": source_fact_ids.duplicate(),
			"generation_seed": seed,
			"summary": "%s因当地产业、人口与道路压力形成，%d 个职位由真实居民担任。" % [
				organization_name, positions.size()
			],
		})
		for position: Dictionary in positions:
			var member_id := str(position.get("founding_holder_id", ""))
			_set_member_role(
				entities,
				member_id,
				"%s::%s" % [
					organization_id, str(position.get("position_id", ""))
				]
			)
			_set_relation_axes(relationships, organization_id, member_id, {
				"familiarity": 45, "trust": 18,
			})
			_set_relation_axes(relationships, member_id, organization_id, {
				"familiarity": 45, "discipline_respect": 12,
			})
			facts.append({
				"fact_id": "fact.organization_position.%s.%s" % [
					_safe_id(organization_id), _safe_id(member_id)
				],
				"fact_type": "organization_position_assigned",
				"actor_id": organization_id,
				"target_id": member_id,
				"settlement_id": settlement_id,
				"position_id": str(position.get("position_id", "")),
				"position_label": str(position.get("label", "成员")),
				"selection_score": int(position.get("selection_score", 0)),
				"source_fact_ids": [organization_fact_id],
				"generation_seed": seed,
			})
		chronicles.append({
			"entry_id": "chronicle.generated_organization.%s" % (
				_safe_id(organization_id)
			),
			"subject_id": organization_id,
			"title": "%s形成" % organization_name,
			"body": "%s，首批职位由%s担任。" % [
				str(prototype.get("goal", "协调聚落事务")),
				_member_names(entities, founding_member_ids),
			],
			"source_fact_ids": [organization_fact_id],
			"generation_seed": seed,
		})
		organization_ids.append(organization_id)
		organization_rows.append({
			"organization_id": organization_id,
			"settlement_id": settlement_id,
			"prototype_id": str(prototype.get("prototype_id", "")),
			"organization_kind": str(prototype.get("organization_kind", "")),
			"founding_member_ids": founding_member_ids.duplicate(),
			"resource_stock_ids": resource_stock_ids.duplicate(),
			"need_signals": needs.duplicate(true),
		})

	fixture["entities"] = entities
	fixture["known_facts"] = facts
	fixture["initial_relationships"] = relationships
	fixture["initial_chronicle_entries"] = chronicles
	var report := {
		"ok": true,
		"generation_seed": seed,
		"definition_version": int(definition.get("definition_version", 1)),
		"organization_count": organization_ids.size(),
		"organization_ids": organization_ids,
		"organizations": organization_rows,
		"signature": JSON.stringify(organization_rows),
	}
	var integrity := _validate_generated_fixture(fixture, report)
	report["integrity"] = integrity
	if not bool(integrity.get("ok", false)):
		return _failure("organization_integrity_invalid:%s" % ",".join(
			integrity.get("errors", [])
		))
	fixture["organization_generation_result"] = report.duplicate(true)
	return {"ok": true, "fixture": fixture, "report": report}


func _select_prototype(
		prototypes: Array[Dictionary],
		industry_ids: Array[String],
		site_input: Dictionary,
		needs: Dictionary,
		seed: int,
		site_id: String
) -> Dictionary:
	var terrain: Dictionary = site_input.get("terrain", {})
	var terrain_tags: Array = terrain.get("tags", [])
	var candidates: Array[Dictionary] = []
	for prototype: Dictionary in prototypes:
		var required_industries: Array = prototype.get(
			"required_any_industry_ids", []
		)
		if (
			not required_industries.is_empty()
			and not _arrays_intersect(industry_ids, required_industries)
		):
			continue
		var required_terrain: Array = prototype.get(
			"required_all_terrain_tags", []
		)
		if not _contains_all(terrain_tags, required_terrain):
			continue
		var score := int(prototype.get("base_score", 0))
		for industry_id: String in industry_ids:
			score += int((prototype.get(
				"industry_weights", {}
			) as Dictionary).get(industry_id, 0))
		for tag_value: Variant in terrain_tags:
			score += int((prototype.get(
				"terrain_weights", {}
			) as Dictionary).get(str(tag_value), 0))
		for need_id: String in needs.keys():
			score += int(needs.get(need_id, 0)) * int((prototype.get(
				"need_weights", {}
			) as Dictionary).get(need_id, 0))
		var row := prototype.duplicate(true)
		row["selection_score"] = score
		row["tie_break"] = _stable_noise(
			seed, "%s:%s" % [site_id, str(prototype.get("prototype_id", ""))]
		)
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("selection_score", 0)) != int(b.get("selection_score", 0)):
			return int(a.get("selection_score", 0)) > int(b.get("selection_score", 0))
		if int(a.get("tie_break", 0)) != int(b.get("tie_break", 0)):
			return int(a.get("tie_break", 0)) > int(b.get("tie_break", 0))
		return str(a.get("prototype_id", "")) < str(b.get("prototype_id", ""))
	)
	return candidates[0]


func _assign_positions(
		entities: Array,
		settlement_id: String,
		organization_id: String,
		position_values: Variant,
		assigned_member_ids: Dictionary,
		seed: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not position_values is Array:
		return rows
	for position_value: Variant in position_values:
		if not position_value is Dictionary:
			continue
		var position: Dictionary = position_value
		var candidates: Array[Dictionary] = []
		for entity_value: Variant in entities:
			if not entity_value is Dictionary:
				continue
			var entity: Dictionary = entity_value
			var entity_id := str(entity.get("id", ""))
			var states: Dictionary = entity.get("states", {})
			if (
				str(entity.get("type", "")) != "person"
				or str(states.get("settlement_id", "")) != settlement_id
				or int(states.get("age_years", 0)) < 18
				or assigned_member_ids.has(entity_id)
			):
				continue
			var occupation_id := str(states.get("occupation_id", ""))
			var preferred: Array = position.get("preferred_occupation_ids", [])
			var score := 30 if occupation_id in preferred else 0
			for attribute: String in (position.get(
				"attribute_bias", {}
			) as Dictionary).keys():
				score += int(states.get(attribute, 0)) * int((position.get(
					"attribute_bias", {}
				) as Dictionary).get(attribute, 0))
			var candidate := {
				"holder_id": entity_id,
				"selection_score": score,
				"tie_break": _stable_noise(seed, "%s:%s:%s" % [
					organization_id,
					str(position.get("position_id", "")),
					entity_id,
				]),
			}
			candidates.append(candidate)
		if candidates.is_empty():
			continue
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("selection_score", 0)) != int(b.get("selection_score", 0)):
				return int(a.get("selection_score", 0)) > int(b.get("selection_score", 0))
			if int(a.get("tie_break", 0)) != int(b.get("tie_break", 0)):
				return int(a.get("tie_break", 0)) > int(b.get("tie_break", 0))
			return str(a.get("holder_id", "")) < str(b.get("holder_id", ""))
		)
		var selected: Dictionary = candidates[0]
		var holder_id := str(selected.get("holder_id", ""))
		assigned_member_ids[holder_id] = organization_id
		rows.append({
			"position_id": str(position.get("position_id", "member")),
			"label": str(position.get("label", "成员")),
			"founding_holder_id": holder_id,
			"selection_score": int(selected.get("selection_score", 0)),
			"preferred_occupation_ids": (
				position.get("preferred_occupation_ids", []) as Array
			).duplicate(),
			"attribute_bias": (
				position.get("attribute_bias", {}) as Dictionary
			).duplicate(true),
		})
	return rows


func _need_signals(
		site: Dictionary,
		site_input: Dictionary,
		runtime: Dictionary,
		industry_ids: Array[String]
) -> Dictionary:
	var settlement_id := str(site.get("settlement_id", ""))
	var link_count := 0
	var capacity_total := 0
	var risk_total := 0
	for link: Dictionary in runtime.get("links", []):
		if settlement_id not in [
			str(link.get("settlement_a_id", "")),
			str(link.get("settlement_b_id", "")),
		]:
			continue
		link_count += 1
		capacity_total += int(link.get("capacity_per_day", 0))
		risk_total += int(link.get("risk", 0))
	for traffic_value: Variant in site_input.get("traffic", []):
		if traffic_value is Dictionary:
			risk_total += int((traffic_value as Dictionary).get("risk", 0))
	var has_food_industry := (
		"fishery" in industry_ids or "terrace_farming" in industry_ids
	)
	return {
		"food_coordination": 1 if has_food_industry else 2,
		"population_coordination": maxi(
			int(site.get("population_target", 0)) / 12, 1
		),
		"trade_coordination": link_count + capacity_total / 4,
		"security_coordination": maxi(risk_total / 2, 1),
		"route_exposure": maxi(link_count + risk_total / 3, 1),
	}


func _resource_stock_ids(
		stocks: Array,
		settlement_id: String,
		tag_values: Variant,
		maximum_count: int
) -> Array[String]:
	var tags: Array = tag_values if tag_values is Array else []
	var candidates: Array[Dictionary] = []
	for stock_value: Variant in stocks:
		if not stock_value is Dictionary:
			continue
		var stock: Dictionary = stock_value
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and _arrays_intersect(stock.get("tags", []), tags)
		):
			candidates.append(stock)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.get("current", 0.0)) != float(b.get("current", 0.0)):
			return float(a.get("current", 0.0)) > float(b.get("current", 0.0))
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	var rows: Array[String] = []
	for candidate: Dictionary in candidates:
		if rows.size() >= maxi(maximum_count, 0):
			break
		rows.append(str(candidate.get("stock_id", "")))
	return rows


func _source_fact_ids(
		facts: Array,
		settlement_id: String,
		industry_ids: Array[String],
		resource_stock_ids: Array[String]
) -> Array[String]:
	var rows: Array[String] = []
	for fact_value: Variant in facts:
		if not fact_value is Dictionary:
			continue
		var fact: Dictionary = fact_value
		if str(fact.get("actor_id", "")) != settlement_id:
			continue
		var fact_type := str(fact.get("fact_type", ""))
		if (
			fact_type == "settlement_generated"
			or (
				fact_type == "settlement_industry_selected"
				and str(fact.get("industry_id", "")) in industry_ids
			)
			or str(fact.get("stock_id", "")) in resource_stock_ids
		):
			var fact_id := str(fact.get("fact_id", ""))
			if fact_id != "" and fact_id not in rows:
				rows.append(fact_id)
	rows.sort()
	return rows


func _industry_ids(facts: Array, settlement_id: String) -> Array[String]:
	var rows: Array[String] = []
	for fact_value: Variant in facts:
		if not fact_value is Dictionary:
			continue
		var fact: Dictionary = fact_value
		if (
			str(fact.get("fact_type", "")) == "settlement_industry_selected"
			and str(fact.get("actor_id", "")) == settlement_id
		):
			rows.append(str(fact.get("industry_id", "")))
	rows.sort()
	return rows


func _site_inputs(fixture: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	var network: Dictionary = fixture.get("settlement_network_generation", {})
	for site_value: Variant in network.get("sites", []):
		if site_value is Dictionary:
			var site: Dictionary = site_value
			rows[str(site.get("site_id", ""))] = site.duplicate(true)
	return rows


func _set_member_role(
		entities: Array,
		member_id: String,
		role_value: String
) -> void:
	for entity_value: Variant in entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		if str(entity.get("id", "")) != member_id:
			continue
		var states: Dictionary = (entity.get("states", {}) as Dictionary).duplicate(
			true
		)
		states["institution_role"] = role_value
		entity["states"] = states
		return


func _set_relation_axes(
		relationships: Dictionary,
		source_id: String,
		target_id: String,
		axes: Dictionary
) -> void:
	if not relationships.has(source_id):
		relationships[source_id] = {}
	var targets: Dictionary = relationships[source_id]
	var merged: Dictionary = (
		targets.get(target_id, {}) as Dictionary
	).duplicate(true)
	for axis: String in axes.keys():
		merged[axis] = int(axes.get(axis, 0))
	targets[target_id] = merged
	relationships[source_id] = targets


func _validate_generated_fixture(
		fixture: Dictionary,
		report: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	var entity_ids: Dictionary = {}
	for entity_value: Variant in fixture.get("entities", []):
		if entity_value is Dictionary:
			entity_ids[str((entity_value as Dictionary).get("id", ""))] = true
	var location_ids: Dictionary = {}
	var location_values: Variant = fixture.get("locations", {})
	if location_values is Dictionary:
		for key: Variant in (location_values as Dictionary).keys():
			location_ids[str(key)] = true
	var stock_ids: Dictionary = {}
	for stock_value: Variant in fixture.get("initial_resource_stocks", []):
		if stock_value is Dictionary:
			stock_ids[str((stock_value as Dictionary).get("stock_id", ""))] = true
	for organization_id: String in report.get("organization_ids", []):
		if not entity_ids.has(organization_id):
			errors.append("organization_entity_missing:%s" % organization_id)
			continue
		var organization := _entity_by_id(
			fixture.get("entities", []), organization_id
		)
		if not entity_ids.has(str(organization.get("settlement_id", ""))):
			errors.append("organization_settlement_unknown:%s" % organization_id)
		if not location_ids.has(str(organization.get("location_id", ""))):
			errors.append("organization_location_unknown:%s" % organization_id)
		if str(organization.get("goal", "")) == "":
			errors.append("organization_goal_missing:%s" % organization_id)
		for member_id: Variant in organization.get("founding_member_ids", []):
			if not entity_ids.has(str(member_id)):
				errors.append("organization_member_unknown:%s" % organization_id)
		for stock_id: Variant in organization.get("resource_stock_ids", []):
			if not stock_ids.has(str(stock_id)):
				errors.append("organization_resource_unknown:%s" % organization_id)
		for position_value: Variant in organization.get("positions", []):
			if (
				not position_value is Dictionary
				or str((position_value as Dictionary).get("founding_holder_id", ""))
				not in (organization.get("founding_member_ids", []) as Array)
			):
				errors.append("organization_position_unfilled:%s" % organization_id)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"organization_count": (report.get("organization_ids", []) as Array).size(),
	}


func _entity_by_id(entity_values: Variant, entity_id: String) -> Dictionary:
	if not entity_values is Array:
		return {}
	for entity_value: Variant in entity_values:
		if (
			entity_value is Dictionary
			and str((entity_value as Dictionary).get("id", "")) == entity_id
		):
			return entity_value as Dictionary
	return {}


func _entity_name(entities: Array, entity_id: String) -> String:
	var entity := _entity_by_id(entities, entity_id)
	return str(entity.get("display_name", entity_id))


func _member_names(entities: Array, member_ids: Array[String]) -> String:
	var rows: Array[String] = []
	for member_id: String in member_ids:
		rows.append(_entity_name(entities, member_id))
	return "、".join(rows)


func _dictionary_rows(value: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if not value is Array:
		return rows
	for row_value: Variant in value:
		if row_value is Dictionary:
			rows.append((row_value as Dictionary).duplicate(true))
	return rows


func _arrays_intersect(left_value: Variant, right_value: Variant) -> bool:
	if not left_value is Array or not right_value is Array:
		return false
	for value: Variant in left_value:
		if value in (right_value as Array):
			return true
	return false


func _contains_all(values: Array, required: Array) -> bool:
	for value: Variant in required:
		if value not in values:
			return false
	return true


func _stable_noise(seed: int, value: String) -> int:
	var result := posmod(seed, 104729)
	for index: int in range(value.length()):
		result = posmod(result * 33 + value.unicode_at(index), 104729)
	return result


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "fixture": {}, "report": {}}
