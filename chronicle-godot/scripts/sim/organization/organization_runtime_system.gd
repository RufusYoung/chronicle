extends RefCounted
class_name V5OrganizationRuntimeSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary
) -> Dictionary:
	var day := int(tick_event.get("day", 0))
	if day <= 0:
		return {"results": [], "events": []}
	var organizations := _organizations(snapshot)
	var assigned_member_ids: Dictionary = {}
	var results: Array = []
	var events: Array = []
	var appointment_delay := maxi(int(config.get(
		"appointment_delay_days", 1
	)), 0)
	var maximum_per_organization := maxi(int(config.get(
		"max_appointments_per_organization_per_day", 1
	)), 1)

	for organization: Dictionary in organizations:
		var organization_id := str(organization.get("id", ""))
		var evaluation_fact_id := "fact.organization_recruitment_evaluated.%s.day%d" % [
			_safe_id(organization_id), day
		]
		if _fact_exists(snapshot, evaluation_fact_id):
			continue
		var vacancies := _eligible_vacancies(
			snapshot, organization, day, appointment_delay
		)
		if vacancies.is_empty():
			continue
		var result = TransactionResultModel.new()
		var appointment_fact_ids: Array[String] = []
		var appointed_member_ids: Array[String] = []
		var source_vacancy_fact_ids: Array[String] = []
		for vacancy: Dictionary in vacancies:
			if appointed_member_ids.size() >= maximum_per_organization:
				break
			var vacancy_fact_id := str(vacancy.get("vacancy_fact_id", ""))
			source_vacancy_fact_ids.append(vacancy_fact_id)
			var candidate := _select_candidate(
				snapshot,
				organization,
				vacancy,
				assigned_member_ids,
				day
			)
			if candidate.is_empty():
				continue
			var member_id := str(candidate.get("member_id", ""))
			var position_id := str(vacancy.get("position_id", ""))
			var appointment_fact_id := "fact.organization_position_filled.%s.%s.day%d" % [
				_safe_id(organization_id), _safe_id(position_id), day
			]
			assigned_member_ids[member_id] = true
			appointed_member_ids.append(member_id)
			appointment_fact_ids.append(appointment_fact_id)
			result.add_state_change({
				"entity_id": member_id,
				"key": "institution_role",
				"to": "%s::%s" % [organization_id, position_id],
			})
			for change: Dictionary in [
				{
					"source_id": organization_id,
					"target_id": member_id,
					"axis": "familiarity",
					"delta": 18,
				},
				{
					"source_id": organization_id,
					"target_id": member_id,
					"axis": "trust",
					"delta": 6,
				},
				{
					"source_id": member_id,
					"target_id": organization_id,
					"axis": "familiarity",
					"delta": 18,
				},
			]:
				result.add_relationship_change(change)
			result.add_fact({
				"fact_id": appointment_fact_id,
				"fact_type": "organization_position_filled",
				"actor_id": organization_id,
				"target_id": member_id,
				"organization_id": organization_id,
				"settlement_id": str(organization.get("settlement_id", "")),
				"position_id": position_id,
				"position_label": str(vacancy.get("label", "成员")),
				"previous_holder_id": str(vacancy.get(
					"founding_holder_id", ""
				)),
				"selection_score": int(candidate.get("selection_score", 0)),
				"source_fact_ids": [vacancy_fact_id],
				"day": day,
				"summary": "%s从当地居民中补入%s担任%s。" % [
					_entity_name(snapshot, organization_id),
					_entity_name(snapshot, member_id),
					str(vacancy.get("label", "成员")),
				],
			})
		result.add_fact({
			"fact_id": evaluation_fact_id,
			"fact_type": "organization_recruitment_evaluated",
			"actor_id": organization_id,
			"target_id": organization_id,
			"organization_id": organization_id,
			"vacancy_count": vacancies.size(),
			"appointment_count": appointed_member_ids.size(),
			"source_fact_ids": source_vacancy_fact_ids.duplicate(),
			"day": day,
			"summary": (
				"地方组织补入 %d 名成员，仍有 %d 个职位空缺。" % [
					appointed_member_ids.size(),
					vacancies.size() - appointed_member_ids.size(),
				]
				if not appointed_member_ids.is_empty()
				else "地方组织评估了职位空缺，但当地没有合适人选。"
			),
		})
		var unresolved_vacancy_count := (
			vacancies.size() - appointed_member_ids.size()
		)
		if unresolved_vacancy_count > 0:
			result.add_pressure_change({
				"pressure_id": "pressure.organization_staffing.%s.day%d" % [
					_safe_id(organization_id), day
				],
				"domain": "organization",
				"scope_id": organization_id,
				"pressure_type": "organization_staffing_need",
				"value": unresolved_vacancy_count,
				"source_fact_ids": [evaluation_fact_id],
			})
		if not appointed_member_ids.is_empty():
			result.add_chronicle_entry({
				"entry_id": "chronicle.organization_restaffed.%s.day%d" % [
					_safe_id(organization_id), day
				],
				"subject_id": organization_id,
				"title": "%s%s" % [
					_entity_name(snapshot, organization_id),
					"补齐空缺" if unresolved_vacancy_count == 0 else "补入新成员",
				],
				"body": "%d 名当地居民接下空缺职位，仍有 %d 个职位无人承担。" % [
					appointed_member_ids.size(), unresolved_vacancy_count
				],
				"source_fact_ids": appointment_fact_ids.duplicate(),
				"day": day,
			})
			result.set_narrative_result({
				"title": "%s补入了新成员" % _entity_name(
					snapshot, organization_id
				),
				"summary": "%d 个职位由当地居民接手，%d 个职位仍然空缺。" % [
					appointed_member_ids.size(), unresolved_vacancy_count
				],
				"tone": "organization_restaffed",
			})
		result.mark_resolved("organization_recruitment")
		results.append(result)
		events.append({
			"event_type": "organization_recruitment_evaluated",
			"organization_id": organization_id,
			"appointed_member_ids": appointed_member_ids.duplicate(),
			"day": day,
		})
	return {"results": results, "events": events}


func _organizations(snapshot: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_entities():
		if "generated_organization" in (entity.get("tags", []) as Array):
			rows.append(entity)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return rows


func _eligible_vacancies(
		snapshot: Variant,
		organization: Dictionary,
		day: int,
		appointment_delay: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var organization_id := str(organization.get("id", ""))
	for position_value: Variant in organization.get("positions", []):
		if not position_value is Dictionary:
			continue
		var position: Dictionary = position_value
		var position_id := str(position.get("position_id", ""))
		if _current_holder_id(snapshot, organization, position_id) != "":
			continue
		var vacancy := _latest_vacancy(snapshot, organization_id, position_id)
		if (
			vacancy.is_empty()
			or day - int(vacancy.get("day", day)) < appointment_delay
		):
			continue
		var row := position.duplicate(true)
		row["vacancy_fact_id"] = str(vacancy.get("fact_id", ""))
		rows.append(row)
	return rows


func _current_holder_id(
		snapshot: Variant,
		organization: Dictionary,
		position_id: String
) -> String:
	var expected_role := "%s::%s" % [
		str(organization.get("id", "")), position_id
	]
	var settlement_id := str(organization.get("settlement_id", ""))
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) == settlement_id
			and str(snapshot.get_entity_state(
				person_id, "institution_role", ""
			)) == expected_role
		):
			return person_id
	return ""


func _latest_vacancy(
		snapshot: Variant,
		organization_id: String,
		position_id: String
) -> Dictionary:
	var latest: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", ""))
			!= "organization_position_vacated"
			or str(fact.get("organization_id", "")) != organization_id
			or str(fact.get("position_id", "")) != position_id
		):
			continue
		if latest.is_empty() or int(fact.get("day", 0)) > int(
			latest.get("day", 0)
		):
			latest = fact.duplicate(true)
	return latest


func _select_candidate(
		snapshot: Variant,
		organization: Dictionary,
		position: Dictionary,
		assigned_member_ids: Dictionary,
		day: int
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var settlement_id := str(organization.get("settlement_id", ""))
	var preferred: Array = position.get("preferred_occupation_ids", [])
	var attribute_bias: Dictionary = position.get("attribute_bias", {})
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			assigned_member_ids.has(person_id)
			or int(snapshot.get_entity_state(
				person_id, "age_years", 0
			)) < 18
			or str(snapshot.get_entity_state(
				person_id, "settlement_id", ""
			)) != settlement_id
			or str(snapshot.get_entity_state(
				person_id, "institution_role", ""
			)) != ""
		):
			continue
		var occupation_id := str(snapshot.get_entity_state(
			person_id, "occupation_id", ""
		))
		var score := 40 if occupation_id in preferred else 0
		for attribute: String in attribute_bias.keys():
			score += int(snapshot.get_entity_state(
				person_id, attribute, 0
			)) * int(attribute_bias.get(attribute, 0))
		candidates.append({
			"member_id": person_id,
			"selection_score": score,
			"tie_break": _stable_noise("%d:%s:%s:%s" % [
				day,
				str(organization.get("id", "")),
				str(position.get("position_id", "")),
				person_id,
			]),
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("selection_score", 0)) != int(b.get("selection_score", 0)):
			return int(a.get("selection_score", 0)) > int(b.get("selection_score", 0))
		if int(a.get("tie_break", 0)) != int(b.get("tie_break", 0)):
			return int(a.get("tie_break", 0)) > int(b.get("tie_break", 0))
		return str(a.get("member_id", "")) < str(b.get("member_id", ""))
	)
	return candidates[0]


func _fact_exists(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	for entity: Dictionary in snapshot.get_entities():
		if str(entity.get("id", "")) == entity_id:
			return str(entity.get("display_name", entity_id))
	return entity_id


func _stable_noise(key: String) -> int:
	return int(("0x" + key.sha256_text().substr(0, 8)).hex_to_int() % 1000000)


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_")
