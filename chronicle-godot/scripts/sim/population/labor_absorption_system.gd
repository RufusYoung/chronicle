extends RefCounted
class_name V5LaborAbsorptionSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_daily_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		network_config: Dictionary,
		profiles: Array,
		locations: Array
) -> Dictionary:
	var config: Dictionary = network_config.get("labor_absorption", {})
	var day := int(tick_event.get("day", 0))
	var interval := maxi(int(config.get("evaluation_interval_days", 1)), 1)
	if (
		not bool(config.get("enabled", false))
		or day <= 0
		or day % interval != 0
		or profiles.is_empty()
	):
		return {"results": [], "events": []}

	var location_by_id := _locations_by_id(locations)
	var profile_data := _profile_data(snapshot, profiles, location_by_id)
	var profiles_by_scope: Dictionary = profile_data.get("profiles", {})
	var open_slots: Dictionary = profile_data.get("open_slots", {})
	if profiles_by_scope.is_empty():
		return {"results": [], "events": []}
	var seekers_by_settlement := _seekers_by_settlement(
		snapshot, day, config
	)
	if seekers_by_settlement.is_empty():
		return {"results": [], "events": []}

	var result = TransactionResultModel.new()
	var events: Array = []
	var hired_count := 0
	var unmet_count := 0
	var maximum_hires := maxi(int(config.get(
		"maximum_hires_per_settlement_per_day", 2
	)), 0)
	var settlement_ids: Array[String] = []
	for value: Variant in seekers_by_settlement.keys():
		settlement_ids.append(str(value))
	settlement_ids.sort()
	for settlement_id: String in settlement_ids:
		var seekers: Array = seekers_by_settlement[settlement_id]
		seekers.sort_custom(func(a: String, b: String) -> bool:
			var priority_a := _seeker_priority(snapshot, a)
			var priority_b := _seeker_priority(snapshot, b)
			return priority_a > priority_b if priority_a != priority_b else a < b
		)
		var settlement_hires := 0
		for seeker_id: String in seekers:
			var source_fact_ids := _employment_source_facts(
				snapshot, seeker_id, settlement_id, "", location_by_id
			)
			if source_fact_ids.is_empty():
				continue
			if settlement_hires >= maximum_hires:
				if _append_unmet_search(
					result, snapshot, seeker_id, settlement_id,
					"daily_hire_limit", day, config, source_fact_ids
				):
					unmet_count += 1
				continue
			var profile := _select_profile(
				snapshot, seeker_id, settlement_id,
				profiles_by_scope, open_slots, config
			)
			if profile.is_empty():
				if _append_unmet_search(
					result, snapshot, seeker_id, settlement_id,
					"no_open_occupation", day, config, source_fact_ids
				):
					unmet_count += 1
				continue
			var workplace_id := str(profile.get("workplace_id", ""))
			source_fact_ids = _employment_source_facts(
				snapshot, seeker_id, settlement_id,
				workplace_id, location_by_id
			)
			_append_employment(
				result, snapshot, seeker_id, settlement_id,
				profile, source_fact_ids, day, events
			)
			var profile_key := _profile_key(
				settlement_id, str(profile.get("occupation_id", ""))
			)
			open_slots[profile_key] = maxi(
				int(open_slots.get(profile_key, 0)) - 1, 0
			)
			settlement_hires += 1
			hired_count += 1

	if result.is_empty():
		return {"results": [], "events": events}
	result.set_narrative_result({
		"title": "本地劳动力进入新的生计",
		"summary": "%d 名居民进入真实岗位，%d 名居民仍受岗位容量限制。" % [
			hired_count, unmet_count
		],
		"tone": "ordinary_life",
	})
	result.mark_resolved("resident_labor_absorption")
	return {"results": [result], "events": events}


func _append_employment(
		result: Variant,
		snapshot: Variant,
		resident_id: String,
		settlement_id: String,
		profile: Dictionary,
		source_fact_ids: Array[String],
		day: int,
		events: Array
) -> void:
	var occupation_id := str(profile.get("occupation_id", ""))
	var workplace_id := str(profile.get("workplace_id", ""))
	var livelihood_status := str(profile.get(
		"livelihood_status", "self_employed"
	))
	var household_id := str(snapshot.get_entity_state(
		resident_id, "household_id", ""
	))
	var fact_id := "fact.resident_employed.%s.day%d" % [
		_safe_id(resident_id), day
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "resident_employed",
		"actor_id": settlement_id,
		"target_id": resident_id,
		"resident_id": resident_id,
		"household_id": household_id,
		"settlement_id": settlement_id,
		"occupation_id": occupation_id,
		"occupation_label": str(profile.get("label", occupation_id)),
		"livelihood_status": livelihood_status,
		"workplace_id": workplace_id,
		"match_score": int(profile.get("match_score", 0)),
		"attribute_contributions": (
			profile.get("attribute_contributions", {}) as Dictionary
		).duplicate(true),
		"household_occupation_match": bool(profile.get(
			"household_occupation_match", false
		)),
		"source_fact_ids": source_fact_ids.duplicate(),
		"day": day,
		"summary": "%s依据岗位空缺、能力与家庭经验，开始在%s从事%s。" % [
			_entity_name(snapshot, resident_id),
			_entity_name(snapshot, workplace_id),
			str(profile.get("label", occupation_id)),
		],
	})
	for change: Dictionary in [
		{"key": "occupation_id", "to": occupation_id},
		{"key": "livelihood_status", "to": livelihood_status},
		{"key": "workplace_id", "to": workplace_id},
		{"key": "livelihood_elapsed_hours", "to": 0},
		{"key": "livelihood_blocked_count", "to": 0},
	]:
		result.add_state_change({
			"entity_id": resident_id,
			"key": str(change.get("key", "")),
			"to": change.get("to"),
		})
	var entity: Dictionary = snapshot.get_entity(resident_id)
	var tags: Array = []
	for value: Variant in entity.get("tags", []):
		var tag := str(value)
		if not tag.begins_with("occupation_"):
			tags.append(tag)
	if "generated_worker" not in tags:
		tags.append("generated_worker")
	tags.append("occupation_%s" % occupation_id)
	result.add_entity_change({
		"operation": "update",
		"entity_id": resident_id,
		"fields": {
			"tags": tags,
			"description": "%d 岁的生成居民，当前在%s从事%s。" % [
				int(snapshot.get_entity_state(resident_id, "age_years", 18)),
				_entity_name(snapshot, workplace_id),
				str(profile.get("label", occupation_id)),
			],
		},
		"source_fact_ids": [fact_id],
		"day": day,
	})
	var coworker_id := _coworker(
		snapshot, resident_id, settlement_id, workplace_id
	)
	var social_target := coworker_id if coworker_id != "" else settlement_id
	for relationship: Dictionary in [
		{"source_id": resident_id, "target_id": social_target, "axis": "familiarity", "delta": 10},
		{"source_id": social_target, "target_id": resident_id, "axis": "familiarity", "delta": 8},
		{"source_id": resident_id, "target_id": social_target, "axis": "trust", "delta": 3},
	]:
		result.add_relationship_change(relationship)
	result.add_fact({
		"fact_id": "fact.resident_work_relation.%s.day%d" % [
			_safe_id(resident_id), day
		],
		"fact_type": "resident_work_relation_formed",
		"actor_id": resident_id,
		"target_id": social_target,
		"settlement_id": settlement_id,
		"workplace_id": workplace_id,
		"relationship_kind": (
			"workmate" if coworker_id != "" else "settlement_employment"
		),
		"source_fact_ids": [fact_id],
		"day": day,
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.resident_employed.%s.day%d" % [
			_safe_id(resident_id), day
		],
		"subject_id": household_id if household_id != "" else resident_id,
		"title": "%s开始从事%s" % [
			_entity_name(snapshot, resident_id),
			str(profile.get("label", occupation_id)),
		],
		"body": "岗位来自聚落现有产业容量，匹配考虑了居民能力、家庭经验和已在岗同伴。",
		"source_fact_ids": [fact_id],
		"day": day,
	})
	events.append({
		"event_type": "resident_employed",
		"resident_id": resident_id,
		"settlement_id": settlement_id,
		"occupation_id": occupation_id,
		"workplace_id": workplace_id,
		"day": day,
	})


func _append_unmet_search(
		result: Variant,
		snapshot: Variant,
		resident_id: String,
		settlement_id: String,
		reason: String,
		day: int,
		config: Dictionary,
		source_fact_ids: Array[String]
) -> bool:
	var interval := maxi(int(config.get(
		"unmet_search_fact_interval_days", 30
	)), 1)
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "resident_employment_search_unmet"
			and str(fact.get("target_id", "")) == resident_id
			and day - int(fact.get("day", 0)) < interval
		):
			return false
	result.add_fact({
		"fact_id": "fact.resident_employment_search_unmet.%s.day%d" % [
			_safe_id(resident_id), day
		],
		"fact_type": "resident_employment_search_unmet",
		"actor_id": settlement_id,
		"target_id": resident_id,
		"resident_id": resident_id,
		"household_id": str(snapshot.get_entity_state(
			resident_id, "household_id", ""
		)),
		"settlement_id": settlement_id,
		"reason": reason,
		"source_fact_ids": source_fact_ids.duplicate(),
		"day": day,
		"summary": "%s仍在寻找生计，现有岗位容量没有为其伪造职位。" % _entity_name(
			snapshot, resident_id
		),
	})
	return true


func _profile_data(
		snapshot: Variant,
		profiles: Array,
		location_by_id: Dictionary
) -> Dictionary:
	var by_scope: Dictionary = {}
	var open_slots: Dictionary = {}
	var current_counts: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if str(snapshot.get_entity_state(
			person_id, "livelihood_status", ""
		)) not in ["employed", "self_employed"]:
			continue
		var key := _profile_key(
			str(snapshot.get_entity_state(person_id, "settlement_id", "")),
			str(snapshot.get_entity_state(person_id, "occupation_id", ""))
		)
		current_counts[key] = int(current_counts.get(key, 0)) + 1
	for value: Variant in profiles:
		if not value is Dictionary:
			continue
		var profile := (value as Dictionary).duplicate(true)
		var settlement_id := str(profile.get("settlement_id", ""))
		var occupation_id := str(profile.get("occupation_id", ""))
		var workplace_id := str(profile.get("workplace_id", ""))
		var key := _profile_key(settlement_id, occupation_id)
		if (
			settlement_id == ""
			or occupation_id == ""
			or workplace_id == ""
			or not location_by_id.has(workplace_id)
		):
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
		resident_id: String,
		settlement_id: String,
		profiles: Dictionary,
		open_slots: Dictionary,
		config: Dictionary
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var prefix := "%s::" % settlement_id
	var slot_weight := maxi(int(config.get("open_slot_score_weight", 3)), 0)
	var family_bonus := maxi(int(config.get(
		"household_occupation_bonus", 12
	)), 0)
	var familiarity_divisor := maxi(int(config.get(
		"coworker_familiarity_divisor", 10
	)), 1)
	for value: Variant in profiles.keys():
		var key := str(value)
		if not key.begins_with(prefix) or int(open_slots.get(key, 0)) <= 0:
			continue
		var profile: Dictionary = profiles[key]
		var score := int(open_slots.get(key, 0)) * slot_weight
		var contributions: Dictionary = {}
		for attribute: String in (profile.get("attribute_bias", {}) as Dictionary).keys():
			var contribution := int(snapshot.get_entity_state(
				resident_id, attribute, 0
			)) * int((profile.get("attribute_bias", {}) as Dictionary).get(
				attribute, 0
			))
			contributions[attribute] = contribution
			score += contribution
		var occupation_id := str(profile.get("occupation_id", ""))
		var household_match := _household_has_occupation(
			snapshot, resident_id, occupation_id
		)
		if household_match:
			score += family_bonus
		var coworker_id := _coworker(
			snapshot, resident_id, settlement_id,
			str(profile.get("workplace_id", ""))
		)
		if coworker_id != "":
			score += int(snapshot.get_relation(
				resident_id, coworker_id, "familiarity", 0
			)) / familiarity_divisor
		var row := profile.duplicate(true)
		row["match_score"] = score
		row["attribute_contributions"] = contributions
		row["household_occupation_match"] = household_match
		candidates.append(row)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("match_score", 0)) != int(b.get("match_score", 0)):
			return int(a.get("match_score", 0)) > int(b.get("match_score", 0))
		return str(a.get("occupation_id", "")) < str(b.get("occupation_id", ""))
	)
	return candidates[0]


func _seekers_by_settlement(
		snapshot: Variant, day: int, config: Dictionary
) -> Dictionary:
	var pending_households := _pending_migrant_households(snapshot)
	var minimum_search_days := maxi(int(config.get("minimum_search_days", 1)), 0)
	var rows: Dictionary = {}
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		var settlement_id := str(snapshot.get_entity_state(
			person_id, "settlement_id", ""
		))
		var household_id := str(snapshot.get_entity_state(
			person_id, "household_id", ""
		))
		if (
			person_id == "player"
			or settlement_id == ""
			or pending_households.has(household_id)
			or int(snapshot.get_entity_state(person_id, "age_years", 0)) < 18
			or str(snapshot.get_entity_state(
				person_id, "life_status", "alive"
			)) != "alive"
			or str(snapshot.get_entity_state(
				person_id, "livelihood_status", ""
			)) != "unemployed"
			or day - _search_started_day(snapshot, person_id) < minimum_search_days
		):
			continue
		if not rows.has(settlement_id):
			rows[settlement_id] = []
		(rows[settlement_id] as Array).append(person_id)
	return rows


func _search_started_day(snapshot: Variant, resident_id: String) -> int:
	var started_day := 0
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("target_id", "")) == resident_id
			and str(fact.get("fact_type", "")) in [
				"resident_reached_adulthood", "resident_employment_search_unmet"
			]
		):
			started_day = maxi(started_day, int(fact.get("day", 0)))
	return started_day


func _seeker_priority(snapshot: Variant, resident_id: String) -> int:
	var household_id := str(snapshot.get_entity_state(
		resident_id, "household_id", ""
	))
	var household_has_worker := false
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != resident_id
			and str(snapshot.get_entity_state(
				person_id, "household_id", ""
			)) == household_id
			and str(snapshot.get_entity_state(
				person_id, "livelihood_status", ""
			)) in ["employed", "self_employed"]
		):
			household_has_worker = true
			break
	return (
		(0 if household_has_worker else 100)
		+ mini(int(snapshot.get_entity_state(resident_id, "age_years", 18)), 80)
	)


func _household_has_occupation(
		snapshot: Variant, resident_id: String, occupation_id: String
) -> bool:
	var household_id := str(snapshot.get_entity_state(
		resident_id, "household_id", ""
	))
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != resident_id
			and str(snapshot.get_entity_state(
				person_id, "household_id", ""
			)) == household_id
			and str(snapshot.get_entity_state(
				person_id, "occupation_id", ""
			)) == occupation_id
			and str(snapshot.get_entity_state(
				person_id, "livelihood_status", ""
			)) in ["employed", "self_employed"]
		):
			return true
	return false


func _coworker(
		snapshot: Variant,
		resident_id: String,
		settlement_id: String,
		workplace_id: String
) -> String:
	var candidates: Array[String] = []
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			person_id != resident_id
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
	return "" if candidates.is_empty() else candidates[0]


func _pending_migrant_households(snapshot: Variant) -> Dictionary:
	var completed_migrations: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_type", "")) == "migrant_household_absorbed":
			completed_migrations[str(fact.get(
				"source_migration_fact_id", ""
			))] = true
	var rows: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "household_migrated"
			and not completed_migrations.has(str(fact.get("fact_id", "")))
		):
			rows[str(fact.get("household_id", ""))] = true
	return rows


func _employment_source_facts(
		snapshot: Variant,
		resident_id: String,
		settlement_id: String,
		workplace_id: String,
		location_by_id: Dictionary
) -> Array[String]:
	var resident_fact_id := ""
	var settlement_fact_id := ""
	var industry_fact_id := ""
	var industry_id := ""
	if workplace_id != "" and location_by_id.has(workplace_id):
		industry_id = str(((location_by_id[workplace_id] as Dictionary).get(
			"generation_source", {}
		) as Dictionary).get("industry_id", ""))
	for fact: Dictionary in snapshot.get_facts():
		var fact_type := str(fact.get("fact_type", ""))
		if (
			str(fact.get("target_id", "")) == resident_id
			and fact_type in [
				"resident_reached_adulthood", "resident_born", "resident_generated"
			]
		):
			resident_fact_id = str(fact.get("fact_id", ""))
		if (
			fact_type == "settlement_generated"
			and str(fact.get("target_id", "")) == settlement_id
		):
			settlement_fact_id = str(fact.get("fact_id", ""))
		if (
			industry_id != ""
			and fact_type == "settlement_industry_selected"
			and str(fact.get("target_id", "")) == settlement_id
			and str(fact.get("industry_id", "")) == industry_id
		):
			industry_fact_id = str(fact.get("fact_id", ""))
	var rows: Array[String] = []
	for fact_id: String in [resident_fact_id, settlement_fact_id, industry_fact_id]:
		if fact_id != "" and fact_id not in rows:
			rows.append(fact_id)
	return rows


func _locations_by_id(locations: Array) -> Dictionary:
	var rows: Dictionary = {}
	for value: Variant in locations:
		if value is Dictionary:
			var location: Dictionary = value
			rows[str(location.get("id", ""))] = location
	return rows


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	if entity_id == str(snapshot.location.get("id", "")):
		return str(snapshot.location.get("display_name", entity_id))
	var entity: Dictionary = snapshot.get_entity(entity_id)
	if not entity.is_empty():
		return str(entity.get("display_name", entity_id))
	return entity_id


func _profile_key(settlement_id: String, occupation_id: String) -> String:
	return "%s::%s" % [settlement_id, occupation_id]


func _safe_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")
