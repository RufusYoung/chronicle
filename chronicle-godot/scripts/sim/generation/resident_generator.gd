extends RefCounted
class_name V5ResidentGenerator


func generate_fixture(
		source_fixture: Dictionary,
		config: Dictionary,
		definition: Dictionary
) -> Dictionary:
	if source_fixture.is_empty() or config.is_empty() or definition.is_empty():
		return _failure("generation_input_missing")
	if source_fixture.has("resident_generation_result"):
		var existing_report: Dictionary = source_fixture.get(
			"resident_generation_result", {}
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
	var count := int(config.get("resident_count", 12))
	if count < 2:
		return _failure("resident_count_below_minimum")
	var seed := int(config.get("seed", fixture.get("challenge_seed", 1)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var locations := _location_dictionary(fixture.get("locations", {}))
	var settlement_id := str(config.get("settlement_id", ""))
	if settlement_id == "" or not _fixture_has_entity(fixture, settlement_id):
		return _failure("settlement_entity_missing")
	var occupations: Array = definition.get("occupations", [])
	var occupation_error := _occupation_reference_error(occupations, locations)
	if occupation_error != "":
		return _failure(occupation_error)

	var household_count := clampi(
		rng.randi_range(
			int(config.get("minimum_households", 3)),
			int(config.get("maximum_households", 4))
		),
		1,
		maxi(count / 2, 1)
	)
	var household_sizes := _household_sizes(count, household_count, rng)
	var surnames: Array = definition.get("surnames", [])
	var given_names: Array = definition.get("given_names", [])
	if surnames.is_empty() or given_names.is_empty():
		return _failure("resident_name_pool_missing")
	var culture_id := str(definition.get("culture_id", "culture.unknown"))
	var generation_id := "%s:%d" % [
		str(definition.get("generation_def_id", "generation.residents")), seed
	]
	var entities: Array = (fixture.get("entities", []) as Array).duplicate(true)
	var facts: Array = (fixture.get("known_facts", []) as Array).duplicate(true)
	var relationships: Dictionary = (
		fixture.get("initial_relationships", {}) as Dictionary
	).duplicate(true)
	var items: Array = (fixture.get("initial_items", []) as Array).duplicate(true)
	var chronicles: Array = (
		fixture.get("initial_chronicle_entries", []) as Array
	).duplicate(true)
	var resident_ids: Array[String] = []
	var household_ids: Array[String] = []
	var household_heads: Array[String] = []
	var used_names: Dictionary = {}
	var occupation_counts: Dictionary = {}
	var required_occupations := _required_occupation_queue(occupations)
	var resident_index := 0

	facts.append({
		"fact_id": "fact.generated_resident_batch.%s.%d" % [
			str(fixture.get("fixture_id", "world")), seed
		],
		"fact_type": "resident_generation_completed",
		"actor_id": settlement_id,
		"generation_id": generation_id,
		"generation_seed": seed,
		"resident_count": count,
		"household_count": household_count,
		"definition_version": int(definition.get("definition_version", 1)),
	})
	var batch_fact_id := str((facts.back() as Dictionary).get("fact_id", ""))

	for household_index: int in range(household_count):
		var household_number := household_index + 1
		var household_id := "generated_household.%s.%02d" % [
			str(fixture.get("fixture_id", "world")), household_number
		]
		var home_id := "generated_home.%s.%02d" % [
			str(fixture.get("fixture_id", "world")), household_number
		]
		var surname := str(surnames[rng.randi_range(0, surnames.size() - 1)])
		locations[home_id] = {
			"id": home_id,
			"display_name": "%s家住屋" % surname,
			"description": "芦苇岸聚落的一处普通住屋，居住者和家庭结构由世界种子生成。",
			"tags": ["home", "generated_location", "settlement_dwelling"],
		}
		entities.append({
			"id": household_id,
			"type": "household",
			"display_name": "%s家" % surname,
			"description": "由生成合同建立的同住生活单元。",
			"location_id": home_id,
			"tags": ["generated_household", culture_id],
			"states": {"visible": false},
		})
		household_ids.append(household_id)
		facts.append({
			"fact_id": "fact.generated_household.%s" % household_id,
			"fact_type": "household_generated",
			"actor_id": settlement_id,
			"target_id": household_id,
			"home_location_id": home_id,
			"generation_seed": seed,
			"source_fact_ids": [batch_fact_id],
		})
		var household_members: Array[String] = []
		var household_member_ages: Dictionary = {}
		for member_index: int in range(int(household_sizes[household_index])):
			resident_index += 1
			var resident_id := "generated_resident.%s.%03d" % [
				str(fixture.get("fixture_id", "world")), resident_index
			]
			var display_name := _unique_name(
				surname, given_names, used_names, rng, resident_index
			)
			var age := _generated_age(member_index, rng)
			var temperament := _weighted_id(
				definition.get("temperaments", []), rng, "steady"
			)
			var livelihood := _livelihood_for(
				age, occupations, occupation_counts, required_occupations, rng
			)
			var occupation: Dictionary = livelihood.get("occupation", {})
			var occupation_id := str(livelihood.get("occupation_id", "dependent"))
			var livelihood_status := str(livelihood.get(
				"livelihood_status", "dependent"
			))
			var workplace_id := str(livelihood.get("workplace_id", ""))
			if workplace_id == "":
				workplace_id = home_id
			var attributes := _attributes_for(age, occupation, rng)
			var tags: Array = [
				"generated_resident", "living_needs", culture_id,
				"occupation_%s" % occupation_id,
			]
			if livelihood_status in ["employed", "self_employed"]:
				tags.append("generated_worker")
			var states := {
				"visible": false,
				"location_id": home_id,
				"age_years": age,
				"settlement_id": settlement_id,
				"household_id": household_id,
				"home_location_id": home_id,
				"workplace_id": workplace_id,
				"occupation_id": occupation_id,
				"livelihood_status": livelihood_status,
				"temperament": temperament,
				"health": rng.randi_range(72, 100),
				"fatigue": rng.randi_range(0, 3),
				"hunger": ["low", "low", "medium"][rng.randi_range(0, 2)],
				"livelihood_elapsed_hours": 0,
				"livelihood_cycle_count": 0,
			}
			states.merge(attributes, true)
			entities.append({
				"id": resident_id,
				"type": "person",
				"role": occupation_id,
				"display_name": display_name,
				"description": "%d 岁的%s居民，性情%s，当前身份为%s。" % [
					age,
					str(definition.get("culture_label", "本地")),
					_temperament_label(definition, temperament),
					str(livelihood.get("label", occupation_id)),
				],
				"location_id": home_id,
				"tags": tags,
				"states": states,
			})
			resident_ids.append(resident_id)
			household_members.append(resident_id)
			household_member_ages[resident_id] = age
			if member_index == 0:
				household_heads.append(resident_id)
			facts.append({
				"fact_id": "fact.generated_resident.%s" % resident_id,
				"fact_type": "resident_generated",
				"actor_id": settlement_id,
				"target_id": resident_id,
				"household_id": household_id,
				"home_location_id": home_id,
				"occupation_id": occupation_id,
				"generation_seed": seed,
				"source_fact_ids": [batch_fact_id],
			})
			if livelihood_status in ["employed", "self_employed"]:
				items.append(_coin_stack(resident_id, seed, rng))
		_link_household_members(relationships, household_members, rng)
		_append_household_relationship_facts(
			facts,
			household_id,
			household_members,
			household_member_ages,
			batch_fact_id
		)

	_link_household_heads(relationships, household_heads, rng)
	chronicles.append({
		"entry_id": "chronicle.generated_residents.%s.%d" % [
			str(fixture.get("fixture_id", "world")), seed
		],
		"subject_id": settlement_id,
		"title": "%s的人口初册" % str(config.get("settlement_name", settlement_id)),
		"body": "聚落初册记录了 %d 名居民与 %d 个同住家庭。姓名、年龄、职业和关系来自可复现的生成合同。" % [count, household_count],
		"source_fact_ids": [batch_fact_id],
		"generation_seed": seed,
	})
	fixture["locations"] = locations
	fixture["entities"] = entities
	fixture["known_facts"] = facts
	fixture["initial_relationships"] = relationships
	fixture["initial_items"] = items
	fixture["initial_chronicle_entries"] = chronicles
	fixture["generated_livelihood_profiles"] = _livelihood_profiles(
		occupations
	)
	var report := {
		"ok": true,
		"generation_id": generation_id,
		"generation_seed": seed,
		"resident_count": resident_ids.size(),
		"household_count": household_ids.size(),
		"resident_ids": resident_ids,
		"household_ids": household_ids,
		"occupation_counts": occupation_counts.duplicate(true),
		"signature": _signature(entities, resident_ids, relationships),
		"structure_signature": _structure_signature(
			entities, resident_ids, household_ids, relationships
		),
	}
	var integrity := _validate_generated_fixture(fixture, report)
	report["integrity"] = integrity
	if not bool(integrity.get("ok", false)):
		return _failure("generated_fixture_integrity_invalid:%s" % ",".join(
			integrity.get("errors", [])
		))
	fixture["resident_generation_result"] = report.duplicate(true)
	return {"ok": true, "fixture": fixture, "report": report}


func _location_dictionary(value: Variant) -> Dictionary:
	var rows: Dictionary = {}
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			rows[str(key)] = ((value as Dictionary)[key] as Dictionary).duplicate(true)
	elif value is Array:
		for location: Dictionary in value:
			var location_id := str(location.get("id", ""))
			if location_id != "":
				rows[location_id] = location.duplicate(true)
	return rows


func _fixture_has_entity(fixture: Dictionary, entity_id: String) -> bool:
	for entity: Dictionary in fixture.get("entities", []):
		if str(entity.get("id", "")) == entity_id:
			return true
	return false


func _occupation_reference_error(occupations: Array, locations: Dictionary) -> String:
	if occupations.is_empty():
		return "occupation_pool_missing"
	for occupation: Dictionary in occupations:
		if str(occupation.get("occupation_id", "")) == "":
			return "occupation_id_missing"
		if not locations.has(str(occupation.get("workplace_id", ""))):
			return "occupation_workplace_missing:%s" % str(
				occupation.get("occupation_id", "")
			)
	return ""


func _household_sizes(
		resident_count: int,
		household_count: int,
		rng: RandomNumberGenerator
) -> Array[int]:
	var sizes: Array[int] = []
	for unused: int in range(household_count):
		sizes.append(2)
	var remaining := resident_count - household_count * 2
	while remaining > 0:
		var index := rng.randi_range(0, household_count - 1)
		sizes[index] += 1
		remaining -= 1
	return sizes


func _unique_name(
		surname: String,
		given_names: Array,
		used: Dictionary,
		rng: RandomNumberGenerator,
		fallback_index: int
) -> String:
	for unused: int in range(given_names.size() * 2):
		var candidate := "%s%s" % [
			surname, str(given_names[rng.randi_range(0, given_names.size() - 1)])
		]
		if not used.has(candidate):
			used[candidate] = true
			return candidate
	var fallback := "%s%d" % [surname, fallback_index]
	used[fallback] = true
	return fallback


func _generated_age(member_index: int, rng: RandomNumberGenerator) -> int:
	if member_index == 0:
		return rng.randi_range(30, 60)
	if member_index == 1 and rng.randi_range(1, 100) <= 75:
		return rng.randi_range(24, 64)
	var roll := rng.randi_range(1, 100)
	if roll <= 55:
		return rng.randi_range(6, 17)
	if roll <= 85:
		return rng.randi_range(18, 52)
	return rng.randi_range(65, 78)


func _required_occupation_queue(occupations: Array) -> Array:
	var rows: Array = []
	for occupation: Dictionary in occupations:
		for unused: int in range(maxi(int(occupation.get("minimum_slots", 0)), 0)):
			rows.append(occupation.duplicate(true))
	return rows


func _livelihood_for(
		age: int,
		occupations: Array,
		counts: Dictionary,
		required_queue: Array,
		rng: RandomNumberGenerator
) -> Dictionary:
	if age < 18:
		return {"occupation_id": "dependent", "livelihood_status": "dependent", "label": "受家庭照料", "workplace_id": ""}
	if age >= 65:
		return {"occupation_id": "retired", "livelihood_status": "retired", "label": "退出常年重活", "workplace_id": ""}
	var occupation: Dictionary = {}
	while not required_queue.is_empty() and occupation.is_empty():
		var candidate: Dictionary = required_queue.pop_front()
		if int(counts.get(str(candidate.get("occupation_id", "")), 0)) < int(
			candidate.get("maximum_slots", 999)
		):
			occupation = candidate
	if occupation.is_empty():
		var available: Array = []
		for candidate: Dictionary in occupations:
			if int(counts.get(str(candidate.get("occupation_id", "")), 0)) < int(
				candidate.get("maximum_slots", 999)
			):
				available.append(candidate)
		occupation = _weighted_row(available, rng)
	if occupation.is_empty():
		return {"occupation_id": "unemployed", "livelihood_status": "unemployed", "label": "暂时没有稳定生计", "workplace_id": ""}
	var occupation_id := str(occupation.get("occupation_id", ""))
	counts[occupation_id] = int(counts.get(occupation_id, 0)) + 1
	return {
		"occupation_id": occupation_id,
		"livelihood_status": str(occupation.get("livelihood_status", "employed")),
		"label": str(occupation.get("label", occupation_id)),
		"workplace_id": str(occupation.get("workplace_id", "")),
		"occupation": occupation,
	}


func _attributes_for(
		age: int,
		occupation: Dictionary,
		rng: RandomNumberGenerator
) -> Dictionary:
	var rows := {}
	var bias: Dictionary = occupation.get("attribute_bias", {})
	for key: String in [
		"strength", "dexterity", "wisdom", "charisma", "constitution", "perception"
	]:
		var value := rng.randi_range(5, 11) + int(bias.get(key, 0))
		if age < 14 and key in ["strength", "constitution"]:
			value -= 2
		if age >= 65 and key in ["strength", "dexterity", "constitution"]:
			value -= 2
		if age >= 50 and key == "wisdom":
			value += 1
		rows[key] = clampi(value, 2, 16)
	return rows


func _weighted_id(rows: Array, rng: RandomNumberGenerator, fallback: String) -> String:
	var row := _weighted_row(rows, rng)
	return str(row.get("id", fallback)) if not row.is_empty() else fallback


func _weighted_row(rows: Array, rng: RandomNumberGenerator) -> Dictionary:
	if rows.is_empty():
		return {}
	var total := 0
	for row: Dictionary in rows:
		total += maxi(int(row.get("weight", 1)), 1)
	var roll := rng.randi_range(1, total)
	var cursor := 0
	for row: Dictionary in rows:
		cursor += maxi(int(row.get("weight", 1)), 1)
		if roll <= cursor:
			return row.duplicate(true)
	return (rows.back() as Dictionary).duplicate(true)


func _temperament_label(definition: Dictionary, temperament_id: String) -> String:
	for row: Dictionary in definition.get("temperaments", []):
		if str(row.get("id", "")) == temperament_id:
			return str(row.get("label", temperament_id))
	return temperament_id


func _link_household_members(
		relationships: Dictionary,
		member_ids: Array[String],
		rng: RandomNumberGenerator
) -> void:
	for source_id: String in member_ids:
		for target_id: String in member_ids:
			if source_id == target_id:
				continue
			_set_relation_axes(relationships, source_id, target_id, {
				"trust": rng.randi_range(18, 55),
				"familiarity": rng.randi_range(55, 90),
			})


func _link_household_heads(
		relationships: Dictionary,
		head_ids: Array[String],
		rng: RandomNumberGenerator
) -> void:
	if head_ids.size() < 2:
		return
	for index: int in range(head_ids.size()):
		var source_id := head_ids[index]
		var target_id := head_ids[(index + 1) % head_ids.size()]
		_set_relation_axes(relationships, source_id, target_id, {
			"trust": rng.randi_range(-8, 24),
			"familiarity": rng.randi_range(15, 45),
		})
		_set_relation_axes(relationships, target_id, source_id, {
			"trust": rng.randi_range(-8, 24),
			"familiarity": rng.randi_range(15, 45),
		})


func _append_household_relationship_facts(
		facts: Array,
		household_id: String,
		member_ids: Array[String],
		member_ages: Dictionary,
		batch_fact_id: String
) -> void:
	for source_id: String in member_ids:
		for target_id: String in member_ids:
			if source_id == target_id:
				continue
			var source_age := int(member_ages.get(source_id, 18))
			var target_age := int(member_ages.get(target_id, 18))
			var relationship_kind := "co_resident"
			if source_age >= 18 and target_age < 18:
				relationship_kind = "guardian"
			elif source_age < 18 and target_age >= 18:
				relationship_kind = "dependent"
			facts.append({
				"fact_id": "fact.generated_social_relation.%s.%s.%s" % [
					_safe_id(household_id),
					_safe_id(source_id),
					_safe_id(target_id),
				],
				"fact_type": "generated_social_relation",
				"actor_id": source_id,
				"target_id": target_id,
				"household_id": household_id,
				"relationship_kind": relationship_kind,
				"source_fact_ids": [batch_fact_id],
			})


func _set_relation_axes(
		relationships: Dictionary,
		source_id: String,
		target_id: String,
		axes: Dictionary
) -> void:
	if not relationships.has(source_id):
		relationships[source_id] = {}
	var targets: Dictionary = relationships[source_id]
	targets[target_id] = axes.duplicate(true)
	relationships[source_id] = targets


func _coin_stack(
		resident_id: String,
		seed: int,
		rng: RandomNumberGenerator
) -> Dictionary:
	return {
		"item_instance_id": "item_instance.generated.%s.coins" % resident_id,
		"item_def_id": "item.copper_coin",
		"holder": {"kind": "entity", "id": resident_id},
		"quantity": rng.randi_range(1, 8),
		"condition": {},
		"custom_tags": ["generated_livelihood_savings"],
		"provenance": {"generation_seed": seed},
		"history": [],
		"created_tick": 0,
		"updated_tick": 0,
	}


func _livelihood_profiles(occupations: Array) -> Array:
	var rows: Array = []
	for occupation: Dictionary in occupations:
		var products: Variant = occupation.get("products", [])
		if not products is Array or (products as Array).is_empty():
			continue
		rows.append({
			"occupation_id": str(occupation.get("occupation_id", "")),
			"actor_tags_all": ["generated_worker"],
			"work_interval_hours": int(occupation.get(
				"work_interval_hours", 8
			)),
			"products": (products as Array).duplicate(true),
			"work_summary": str(occupation.get(
				"work_summary", "一轮普通生计结束，产物进入了居民库存。"
			)),
		})
	return rows


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")


func _signature(
		entities: Array,
		resident_ids: Array[String],
		relationships: Dictionary
) -> String:
	var rows: Array[String] = []
	for entity: Dictionary in entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id not in resident_ids:
			continue
		var states: Dictionary = entity.get("states", {})
		rows.append("%s|%s|%s|%s|%s" % [
			entity_id,
			str(entity.get("display_name", "")),
			str(states.get("age_years", 0)),
			str(states.get("household_id", "")),
			str(states.get("occupation_id", "")),
		])
	rows.sort()
	return "%s#%s" % [";".join(rows), JSON.stringify(relationships)]


func _structure_signature(
		entities: Array,
		resident_ids: Array[String],
		household_ids: Array[String],
		relationships: Dictionary
) -> String:
	var rows: Array[String] = []
	for entity: Dictionary in entities:
		var entity_id := str(entity.get("id", ""))
		if entity_id not in resident_ids:
			continue
		var states: Dictionary = entity.get("states", {})
		rows.append("%s|%s|%s|%s" % [
			entity_id,
			_age_band(int(states.get("age_years", 0))),
			str(states.get("household_id", "")),
			str(states.get("occupation_id", "")),
		])
	rows.sort()
	var family_edges: Array[String] = []
	for source_id: String in resident_ids:
		var targets: Dictionary = relationships.get(source_id, {})
		for target_id: String in targets.keys():
			if target_id not in resident_ids:
				continue
			var axes: Dictionary = targets[target_id]
			if int(axes.get("familiarity", 0)) >= 50:
				family_edges.append("%s>%s" % [source_id, target_id])
	family_edges.sort()
	return "%d#%s#%s" % [
		household_ids.size(), ";".join(rows), ";".join(family_edges)
	]


func _age_band(age: int) -> String:
	if age < 18:
		return "minor"
	if age >= 65:
		return "elder"
	return "adult"


func _validate_generated_fixture(
		fixture: Dictionary,
		report: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	var entities_by_id: Dictionary = {}
	for entity: Dictionary in fixture.get("entities", []):
		var entity_id := str(entity.get("id", ""))
		if entity_id == "" or entities_by_id.has(entity_id):
			errors.append("missing_or_duplicate_entity:%s" % entity_id)
			continue
		entities_by_id[entity_id] = entity
	var locations := _location_dictionary(fixture.get("locations", {}))
	var names: Dictionary = {}
	var relationships: Dictionary = fixture.get("initial_relationships", {})
	for resident_id: String in report.get("resident_ids", []):
		if not entities_by_id.has(resident_id):
			errors.append("resident_entity_missing:%s" % resident_id)
			continue
		var resident: Dictionary = entities_by_id[resident_id]
		var name := str(resident.get("display_name", ""))
		if name == "" or names.has(name):
			errors.append("resident_name_missing_or_duplicate:%s" % resident_id)
		names[name] = true
		var states: Dictionary = resident.get("states", {})
		var household_id := str(states.get("household_id", ""))
		var settlement_id := str(states.get("settlement_id", ""))
		var home_id := str(states.get("home_location_id", ""))
		var workplace_id := str(states.get("workplace_id", ""))
		if not entities_by_id.has(household_id):
			errors.append("resident_household_unknown:%s" % resident_id)
		if not entities_by_id.has(settlement_id):
			errors.append("resident_settlement_unknown:%s" % resident_id)
		if not locations.has(home_id):
			errors.append("resident_home_unknown:%s" % resident_id)
		if workplace_id == "" or not locations.has(workplace_id):
			errors.append("resident_workplace_unknown:%s" % resident_id)
		var age := int(states.get("age_years", -1))
		var livelihood := str(states.get("livelihood_status", ""))
		if age >= 18 and livelihood not in [
			"employed", "self_employed", "unemployed", "retired"
		]:
			errors.append("adult_livelihood_missing:%s" % resident_id)
		if age < 18 and livelihood != "dependent":
			errors.append("minor_not_dependent:%s" % resident_id)
		var social_targets: Dictionary = relationships.get(resident_id, {})
		if social_targets.is_empty():
			errors.append("resident_socially_isolated:%s" % resident_id)
	for household_id: String in report.get("household_ids", []):
		if not entities_by_id.has(household_id) or str((
			entities_by_id.get(household_id, {}) as Dictionary
		).get("type", "")) != "household":
			errors.append("household_entity_invalid:%s" % household_id)
	for source_id: String in relationships.keys():
		if not entities_by_id.has(source_id):
			errors.append("relationship_source_unknown:%s" % source_id)
		for target_id: String in (relationships[source_id] as Dictionary).keys():
			if not entities_by_id.has(target_id):
				errors.append("relationship_target_unknown:%s" % target_id)
	for item: Dictionary in fixture.get("initial_items", []):
		var holder: Dictionary = item.get("holder", {})
		if str(holder.get("kind", "")) == "entity" and not entities_by_id.has(
			str(holder.get("id", ""))
		):
			errors.append("item_holder_unknown:%s" % str(
				item.get("item_instance_id", "")
			))
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"entity_count": entities_by_id.size(),
		"location_count": locations.size(),
		"resident_count": (report.get("resident_ids", []) as Array).size(),
		"household_count": (report.get("household_ids", []) as Array).size(),
	}


func _failure(error: String) -> Dictionary:
	return {"ok": false, "error": error, "fixture": {}, "report": {}}
