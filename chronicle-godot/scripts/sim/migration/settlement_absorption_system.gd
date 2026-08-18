extends RefCounted
class_name V5SettlementAbsorptionSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary,
		profiles: Array,
		locations: Array
) -> Dictionary:
	if config.is_empty() or int(tick_event.get("elapsed_hours", 0)) <= 0:
		return {"results": [], "events": []}
	var day := int(tick_event.get("day", 0))
	var migrations := _pending_migrations(snapshot)
	if migrations.is_empty():
		return {"results": [], "events": []}

	var location_by_id := _locations_by_id(locations)
	var home_data := _home_data(snapshot, location_by_id)
	var occupancy: Dictionary = home_data.get("occupancy", {})
	var occupants: Dictionary = home_data.get("occupants", {})
	var homes_by_settlement: Dictionary = home_data.get(
		"homes_by_settlement", {}
	)
	var profile_data := _profile_data(snapshot, profiles)
	var profiles_by_scope: Dictionary = profile_data.get("profiles", {})
	var open_slots: Dictionary = profile_data.get("open_slots", {})
	var result = TransactionResultModel.new()
	var events: Array = []
	var completed_count := 0
	var delayed_count := 0
	var household_ids: Array[String] = []
	for household_value: Variant in migrations.keys():
		household_ids.append(str(household_value))
	household_ids.sort()

	for household_id: String in household_ids:
		var migration: Dictionary = migrations[household_id]
		var migration_fact_id := str(migration.get("fact_id", ""))
		var absorption_delay_days := maxi(int(config.get(
			"absorption_delay_days", 1
		)), 1)
		if day < int(migration.get("day", day)) + absorption_delay_days:
			continue
		if (
			_absorption_completed(snapshot, migration_fact_id)
			or _fact_exists(
				snapshot,
				"fact.migrant_absorption_evaluated.%s.day%d" % [
					_safe_id(household_id), day
				]
			)
		):
			continue
		var destination_id := str(migration.get(
			"destination_settlement_id", ""
		))
		var destination_hub_id := str(migration.get(
			"destination_location_id", ""
		))
		var member_ids := _current_member_ids(
			snapshot, migration.get("member_ids", []), destination_id
		)
		if destination_id == "" or member_ids.is_empty():
			continue

		var housing := _current_household_home(
			snapshot, member_ids, destination_hub_id, location_by_id
		)
		var home_id := str(housing.get("home_id", ""))
		var host_id := ""
		if home_id == "":
			var dwelling_capacity := _dwelling_capacity(config, destination_id)
			home_id = _select_home(
				homes_by_settlement.get(destination_id, []),
				occupancy,
				dwelling_capacity,
				member_ids.size()
			)
			if home_id != "":
				var previous_occupants: Array = occupants.get(home_id, [])
				host_id = _host_resident(snapshot, previous_occupants, household_id)
				if host_id == "":
					host_id = _settlement_contact(
						snapshot, destination_id, household_id
					)
				_append_housing_changes(
					result,
					snapshot,
					household_id,
					member_ids,
					home_id,
					host_id,
					destination_id,
					migration_fact_id,
					day
				)
				occupancy[home_id] = int(occupancy.get(home_id, 0)) + member_ids.size()
				var updated_occupants: Array = previous_occupants.duplicate()
				updated_occupants.append_array(member_ids)
				occupants[home_id] = updated_occupants

		var job_seekers := _job_seekers(snapshot, member_ids)
		var hired_ids: Array[String] = []
		for member_id: String in job_seekers:
			var profile := _select_profile(
				snapshot,
				member_id,
				destination_id,
				profiles_by_scope,
				open_slots
			)
			if profile.is_empty():
				continue
			_append_reemployment_changes(
				result,
				snapshot,
				member_id,
				household_id,
				destination_id,
				profile,
				migration_fact_id,
				day
			)
			var profile_key := _profile_key(
				destination_id, str(profile.get("occupation_id", ""))
			)
			open_slots[profile_key] = maxi(
				int(open_slots.get(profile_key, 0)) - 1, 0
			)
			hired_ids.append(member_id)

		var unresolved_jobs := job_seekers.size() - hired_ids.size()
		var housed := home_id != ""
		var evaluation_fact_id := (
			"fact.migrant_absorption_evaluated.%s.day%d" % [
				_safe_id(household_id), day
			]
		)
		result.add_fact({
			"fact_id": evaluation_fact_id,
			"fact_type": "migrant_absorption_evaluated",
			"actor_id": destination_id,
			"target_id": household_id,
			"household_id": household_id,
			"destination_settlement_id": destination_id,
			"source_migration_fact_id": migration_fact_id,
			"housing_status": "housed" if housed else "temporary_shelter",
			"home_location_id": home_id if housed else destination_hub_id,
			"member_count": member_ids.size(),
			"reemployed_count": hired_ids.size(),
			"unresolved_job_count": unresolved_jobs,
			"day": day,
			"summary": _evaluation_summary(
				snapshot,
				household_id,
				destination_id,
				housed,
				hired_ids.size(),
				unresolved_jobs
			),
		})

		if housed and unresolved_jobs == 0:
			_append_completion(
				result,
				snapshot,
				household_id,
				destination_id,
				home_id,
				member_ids,
				hired_ids,
				migration_fact_id,
				day
			)
			completed_count += 1
			events.append({
				"event_type": "migrant_household_absorbed",
				"household_id": household_id,
				"destination_settlement_id": destination_id,
				"home_location_id": home_id,
				"reemployed_count": hired_ids.size(),
			})
		else:
			_append_unmet_pressures(
				result,
				household_id,
				destination_id,
				member_ids.size(),
				housed,
				unresolved_jobs,
				evaluation_fact_id,
				day
			)
			delayed_count += 1
			events.append({
				"event_type": "migrant_absorption_delayed",
				"household_id": household_id,
				"destination_settlement_id": destination_id,
				"housing_status": "housed" if housed else "temporary_shelter",
				"unresolved_job_count": unresolved_jobs,
			})

	if result.is_empty():
		return {"results": [], "events": events}
	result.set_narrative_result({
		"title": "迁入家庭开始在新聚落落脚",
		"summary": "%d 户完成安顿，%d 户仍受住房或生计限制。" % [
			completed_count, delayed_count
		],
		"tone": "settlement_absorption",
	})
	result.mark_resolved("settlement_migrant_absorption")
	return {"results": [result], "events": events}


func _append_housing_changes(
		result: Variant,
		snapshot: Variant,
		household_id: String,
		member_ids: Array[String],
		home_id: String,
		host_id: String,
		destination_id: String,
		migration_fact_id: String,
		day: int
) -> void:
	result.add_state_change({
		"entity_id": household_id,
		"key": "location_id",
		"to": home_id,
	})
	for member_id: String in member_ids:
		result.add_state_change({
			"entity_id": member_id, "key": "location_id", "to": home_id
		})
		result.add_state_change({
			"entity_id": member_id, "key": "home_location_id", "to": home_id
		})
		if str(snapshot.get_entity_state(
			member_id, "livelihood_status", ""
		)) in ["dependent", "retired"]:
			result.add_state_change({
				"entity_id": member_id, "key": "workplace_id", "to": home_id
			})
	var fact_id := "fact.migrant_household_housed.%s.%s" % [
		_safe_id(household_id), _safe_id(migration_fact_id)
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "migrant_household_housed",
		"actor_id": destination_id,
		"target_id": household_id,
		"household_id": household_id,
		"destination_settlement_id": destination_id,
		"home_location_id": home_id,
		"host_resident_id": host_id,
		"member_ids": member_ids.duplicate(),
		"source_migration_fact_id": migration_fact_id,
		"source_fact_ids": [migration_fact_id],
		"day": day,
		"summary": "%s被安置进%s的一处已有住屋。" % [
			_entity_name(snapshot, household_id),
			_entity_name(snapshot, destination_id),
		],
	})
	if host_id != "":
		var migrant_head := member_ids[0]
		var relationship_kind := "temporary_housemate"
		if str(snapshot.get_entity_state(
			host_id, "home_location_id", ""
		)) != home_id:
			relationship_kind = "settlement_sponsor"
		for change: Dictionary in [
			{"source_id": migrant_head, "target_id": host_id, "axis": "familiarity", "delta": 14},
			{"source_id": migrant_head, "target_id": host_id, "axis": "gratitude", "delta": 8},
			{"source_id": host_id, "target_id": migrant_head, "axis": "familiarity", "delta": 14},
			{"source_id": host_id, "target_id": migrant_head, "axis": "trust", "delta": 4},
		]:
			result.add_relationship_change(change)
		result.add_fact({
			"fact_id": "fact.migrant_host_relation.%s.%s" % [
				_safe_id(migrant_head), _safe_id(host_id)
			],
			"fact_type": "migrant_host_relation_formed",
			"actor_id": migrant_head,
			"target_id": host_id,
			"household_id": household_id,
			"home_location_id": home_id,
			"destination_settlement_id": destination_id,
			"relationship_kind": relationship_kind,
			"source_fact_ids": [fact_id, migration_fact_id],
			"day": day,
		})


func _append_reemployment_changes(
		result: Variant,
		snapshot: Variant,
		member_id: String,
		household_id: String,
		destination_id: String,
		profile: Dictionary,
		migration_fact_id: String,
		day: int
) -> void:
	var occupation_id := str(profile.get("occupation_id", ""))
	var workplace_id := str(profile.get("workplace_id", ""))
	var livelihood_status := str(profile.get(
		"livelihood_status", "self_employed"
	))
	for change: Dictionary in [
		{"key": "occupation_id", "to": occupation_id},
		{"key": "livelihood_status", "to": livelihood_status},
		{"key": "workplace_id", "to": workplace_id},
		{"key": "livelihood_elapsed_hours", "to": 0},
	]:
		result.add_state_change({
			"entity_id": member_id,
			"key": str(change.get("key", "")),
			"to": change.get("to"),
		})
	var fact_id := "fact.migrant_reemployed.%s.%s" % [
		_safe_id(member_id), _safe_id(migration_fact_id)
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "migrant_reemployed",
		"actor_id": destination_id,
		"target_id": member_id,
		"household_id": household_id,
		"destination_settlement_id": destination_id,
		"occupation_id": occupation_id,
		"occupation_label": str(profile.get("label", occupation_id)),
		"livelihood_status": livelihood_status,
		"workplace_id": workplace_id,
		"source_migration_fact_id": migration_fact_id,
		"source_fact_ids": [migration_fact_id],
		"day": day,
		"summary": "%s在%s找到%s的生计。" % [
			_entity_name(snapshot, member_id),
			_entity_name(snapshot, destination_id),
			str(profile.get("label", occupation_id)),
		],
	})
	var coworker_id := _coworker(snapshot, member_id, destination_id, workplace_id)
	var social_target := coworker_id if coworker_id != "" else destination_id
	for change: Dictionary in [
		{"source_id": member_id, "target_id": social_target, "axis": "familiarity", "delta": 10},
		{"source_id": social_target, "target_id": member_id, "axis": "familiarity", "delta": 8},
		{"source_id": member_id, "target_id": social_target, "axis": "trust", "delta": 3},
	]:
		result.add_relationship_change(change)
	result.add_fact({
		"fact_id": "fact.migrant_work_relation.%s.%s" % [
			_safe_id(member_id), _safe_id(social_target)
		],
		"fact_type": "migrant_work_relation_formed",
		"actor_id": member_id,
		"target_id": social_target,
		"household_id": household_id,
		"destination_settlement_id": destination_id,
		"workplace_id": workplace_id,
		"relationship_kind": "workmate" if coworker_id != "" else "settlement_employment",
		"source_fact_ids": [fact_id, migration_fact_id],
		"day": day,
	})


func _append_completion(
		result: Variant,
		snapshot: Variant,
		household_id: String,
		destination_id: String,
		home_id: String,
		member_ids: Array[String],
		hired_ids: Array[String],
		migration_fact_id: String,
		day: int
) -> void:
	var fact_id := "fact.migrant_household_absorbed.%s.%s" % [
		_safe_id(household_id), _safe_id(migration_fact_id)
	]
	var summary := "%s在%s获得住处，%d 名劳动者进入当地生计。" % [
		_entity_name(snapshot, household_id),
		_entity_name(snapshot, destination_id),
		hired_ids.size(),
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "migrant_household_absorbed",
		"actor_id": destination_id,
		"target_id": household_id,
		"household_id": household_id,
		"destination_settlement_id": destination_id,
		"home_location_id": home_id,
		"member_ids": member_ids.duplicate(),
		"reemployed_member_ids": hired_ids.duplicate(),
		"source_migration_fact_id": migration_fact_id,
		"source_fact_ids": [migration_fact_id],
		"day": day,
		"summary": summary,
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.migrant_household_absorbed.%s.%s" % [
			_safe_id(household_id), _safe_id(migration_fact_id)
		],
		"subject_id": household_id,
		"title": "迁入家庭在新聚落落脚",
		"body": summary,
		"source_fact_ids": [fact_id, migration_fact_id],
		"day": day,
	})


func _append_unmet_pressures(
		result: Variant,
		household_id: String,
		destination_id: String,
		member_count: int,
		housed: bool,
		unresolved_jobs: int,
		evaluation_fact_id: String,
		day: int
) -> void:
	if not housed:
		result.add_pressure_change({
			"pressure_id": "pressure.migrant_housing.%s.day%d" % [
				_safe_id(household_id), day
			],
			"domain": "settlement_absorption",
			"scope_id": destination_id,
			"pressure_type": "migrant_housing_need",
			"value": member_count,
			"source_fact_ids": [evaluation_fact_id],
		})
	if unresolved_jobs > 0:
		result.add_pressure_change({
			"pressure_id": "pressure.migrant_jobs.%s.day%d" % [
				_safe_id(household_id), day
			],
			"domain": "settlement_absorption",
			"scope_id": destination_id,
			"pressure_type": "migrant_unemployment",
			"value": unresolved_jobs,
			"source_fact_ids": [evaluation_fact_id],
		})


func _pending_migrations(snapshot: Variant) -> Dictionary:
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) != "household_migrated":
			continue
		var household_id := str(fact.get("household_id", ""))
		if household_id != "":
			rows[household_id] = fact.duplicate(true)
	return rows


func _absorption_completed(snapshot: Variant, migration_fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "migrant_household_absorbed"
			and str(fact.get("source_migration_fact_id", "")) == migration_fact_id
		):
			return true
	return false


func _home_data(snapshot: Variant, location_by_id: Dictionary) -> Dictionary:
	var occupancy: Dictionary = {}
	var occupants: Dictionary = {}
	var homes_by_settlement: Dictionary = {}
	for home_value: Variant in location_by_id.values():
		var home: Dictionary = home_value
		if not "settlement_dwelling" in (home.get("tags", []) as Array):
			continue
		var home_id := str(home.get("id", ""))
		var settlement_id := str(home.get("settlement_id", ""))
		if home_id == "" or settlement_id == "":
			continue
		if not homes_by_settlement.has(settlement_id):
			homes_by_settlement[settlement_id] = []
		(homes_by_settlement[settlement_id] as Array).append(home_id)
		occupancy[home_id] = 0
		occupants[home_id] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var settlement_id := str(snapshot.get_entity_state(
			person_id, "settlement_id", ""
		))
		var home_id := str(snapshot.get_entity_state(
			person_id, "home_location_id", ""
		))
		if (
			settlement_id == ""
			or not location_by_id.has(home_id)
			or not "settlement_dwelling" in (
				(location_by_id[home_id] as Dictionary).get("tags", []) as Array
			)
		):
			continue
		occupancy[home_id] = int(occupancy.get(home_id, 0)) + 1
		if not occupants.has(home_id):
			occupants[home_id] = []
		(occupants[home_id] as Array).append(person_id)
		if not homes_by_settlement.has(settlement_id):
			homes_by_settlement[settlement_id] = []
		if home_id not in (homes_by_settlement[settlement_id] as Array):
			(homes_by_settlement[settlement_id] as Array).append(home_id)
	for settlement_id: String in homes_by_settlement.keys():
		(homes_by_settlement[settlement_id] as Array).sort()
	return {
		"occupancy": occupancy,
		"occupants": occupants,
		"homes_by_settlement": homes_by_settlement,
	}


func _profile_data(snapshot: Variant, profiles: Array) -> Dictionary:
	var by_scope: Dictionary = {}
	var open_slots: Dictionary = {}
	var current_counts: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var status := str(snapshot.get_entity_state(
			person_id, "livelihood_status", ""
		))
		if status not in ["employed", "self_employed"]:
			continue
		var key := _profile_key(
			str(snapshot.get_entity_state(person_id, "settlement_id", "")),
			str(snapshot.get_entity_state(person_id, "occupation_id", ""))
		)
		current_counts[key] = int(current_counts.get(key, 0)) + 1
	for profile_value: Variant in profiles:
		if not profile_value is Dictionary:
			continue
		var profile := (profile_value as Dictionary).duplicate(true)
		var key := _profile_key(
			str(profile.get("settlement_id", "")),
			str(profile.get("occupation_id", ""))
		)
		if key == "::":
			continue
		by_scope[key] = profile
		open_slots[key] = maxi(
			int(profile.get("maximum_slots", 0))
			- int(current_counts.get(key, 0)),
			0
		)
	return {"profiles": by_scope, "open_slots": open_slots}


func _select_profile(
		snapshot: Variant,
		member_id: String,
		settlement_id: String,
		profiles: Dictionary,
		open_slots: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var prefix := "%s::" % settlement_id
	for key_value: Variant in profiles.keys():
		var key := str(key_value)
		if not key.begins_with(prefix) or int(open_slots.get(key, 0)) <= 0:
			continue
		var profile: Dictionary = profiles[key]
		if str(profile.get("workplace_id", "")) == "":
			continue
		var score := int(open_slots.get(key, 0)) * 2
		var bias: Dictionary = profile.get("attribute_bias", {})
		for attribute: String in bias.keys():
			score += int(snapshot.get_entity_state(
				member_id, attribute, 0
			)) * int(bias.get(attribute, 0))
		var row := profile.duplicate(true)
		row["match_score"] = score
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("match_score", 0)) != int(b.get("match_score", 0)):
			return int(a.get("match_score", 0)) > int(b.get("match_score", 0))
		return str(a.get("occupation_id", "")) < str(b.get("occupation_id", ""))
	)
	return candidates[0]


func _current_household_home(
		snapshot: Variant,
		member_ids: Array[String],
		destination_hub_id: String,
		location_by_id: Dictionary
) -> Dictionary:
	var home_id := ""
	for member_id: String in member_ids:
		var candidate := str(snapshot.get_entity_state(
			member_id, "home_location_id", ""
		))
		if candidate == "" or candidate == destination_hub_id:
			return {}
		if (
			not location_by_id.has(candidate)
			or not "settlement_dwelling" in (
				(location_by_id[candidate] as Dictionary).get("tags", []) as Array
			)
		):
			return {}
		if home_id != "" and home_id != candidate:
			return {}
		home_id = candidate
	return {"home_id": home_id} if home_id != "" else {}


func _current_member_ids(
		snapshot: Variant,
		member_values: Variant,
		destination_id: String
) -> Array[String]:
	var rows: Array[String] = []
	if not member_values is Array:
		return rows
	for member_value: Variant in member_values:
		var member_id := str(member_value)
		if (
			not snapshot.get_entity(member_id).is_empty()
			and str(snapshot.get_entity_state(
				member_id, "settlement_id", ""
			)) == destination_id
		):
			rows.append(member_id)
	rows.sort()
	return rows


func _job_seekers(snapshot: Variant, member_ids: Array[String]) -> Array[String]:
	var rows: Array[String] = []
	for member_id: String in member_ids:
		var entity: Dictionary = snapshot.get_entity(member_id)
		if (
			str(snapshot.get_entity_state(
				member_id, "livelihood_status", ""
			)) == "unemployed"
			and "generated_worker" in (entity.get("tags", []) as Array)
		):
			rows.append(member_id)
	rows.sort()
	return rows


func _select_home(
		home_values: Variant,
		occupancy: Dictionary,
		capacity: int,
		member_count: int
) -> String:
	if capacity <= 0 or not home_values is Array:
		return ""
	var candidates: Array[String] = []
	for home_value: Variant in home_values:
		var home_id := str(home_value)
		if capacity - int(occupancy.get(home_id, 0)) >= member_count:
			candidates.append(home_id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var a_occupancy := int(occupancy.get(a, 0))
		var b_occupancy := int(occupancy.get(b, 0))
		return a_occupancy < b_occupancy if a_occupancy != b_occupancy else a < b
	)
	return candidates[0] if not candidates.is_empty() else ""


func _dwelling_capacity(config: Dictionary, settlement_id: String) -> int:
	for site_value: Variant in config.get("sites", []):
		if not site_value is Dictionary:
			continue
		var site: Dictionary = site_value
		if str(site.get("settlement_id", "")) == settlement_id:
			return maxi(int(site.get("dwelling_capacity", 6)), 0)
	return 0


func _host_resident(
		snapshot: Variant,
		occupant_values: Array,
		migrant_household_id: String
) -> String:
	var candidates: Array[String] = []
	for occupant_value: Variant in occupant_values:
		var occupant_id := str(occupant_value)
		if str(snapshot.get_entity_state(
			occupant_id, "household_id", ""
		)) != migrant_household_id:
			candidates.append(occupant_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _settlement_contact(
		snapshot: Variant,
		settlement_id: String,
		migrant_household_id: String
) -> String:
	var candidates: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			str(snapshot.get_entity_state(person_id, "settlement_id", ""))
			== settlement_id
			and str(snapshot.get_entity_state(person_id, "household_id", ""))
			!= migrant_household_id
		):
			candidates.append(person_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _coworker(
		snapshot: Variant,
		member_id: String,
		settlement_id: String,
		workplace_id: String
) -> String:
	var candidates: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != member_id
			and str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) == settlement_id
			and str(snapshot.get_entity_state(
				person_id, "workplace_id", ""
			)) == workplace_id
			and str(snapshot.get_entity_state(
				person_id, "livelihood_status", ""
			)) in ["employed", "self_employed"]
		):
			candidates.append(person_id)
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""


func _locations_by_id(locations: Array) -> Dictionary:
	var rows: Dictionary = {}
	for location_value: Variant in locations:
		if location_value is Dictionary:
			var location: Dictionary = location_value
			rows[str(location.get("id", ""))] = location.duplicate(true)
	return rows


func _evaluation_summary(
		snapshot: Variant,
		household_id: String,
		destination_id: String,
		housed: bool,
		hired_count: int,
		unresolved_jobs: int
) -> String:
	return "%s抵达%s后，住房%s；%d 人找到生计，%d 人仍在求职。" % [
		_entity_name(snapshot, household_id),
		_entity_name(snapshot, destination_id),
		"已经落实" if housed else "仍靠公共集地临时安置",
		hired_count,
		unresolved_jobs,
	]


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _profile_key(settlement_id: String, occupation_id: String) -> String:
	return "%s::%s" % [settlement_id, occupation_id]


func _fact_exists(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
