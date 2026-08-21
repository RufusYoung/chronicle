extends RefCounted
class_name V5PopulationLifecycleSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_daily_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary
) -> Dictionary:
	if not bool(config.get("enabled", true)):
		return {"results": [], "events": []}
	var day := int(tick_event.get("day", 0))
	if day <= 0:
		return {"results": [], "events": []}
	var days_per_year := maxi(int(config.get("days_per_year", 365)), 1)
	var adulthood_age := maxi(int(config.get("adulthood_age", 18)), 1)
	var elder_age := maxi(int(config.get("elder_age", 65)), adulthood_age)
	var results: Array = []
	var events: Array = []

	for person: Dictionary in snapshot.get_entities_by_type("person"):
		if "generated_resident" not in (person.get("tags", []) as Array):
			continue
		var person_id := str(person.get("id", ""))
		var current_age := int(snapshot.get_entity_state(
			person_id, "age_years", 0
		))
		var birth_day := int(snapshot.get_entity_state(
			person_id, "birth_day", day - current_age * days_per_year
		))
		var computed_age := maxi(int(floor(
			float(day - birth_day) / float(days_per_year)
		)), 0)
		var life_expectancy := maxi(int(snapshot.get_entity_state(
			person_id, "life_expectancy_years", current_age + 1
		)), 1)
		var health := int(snapshot.get_entity_state(person_id, "health", 100))
		var died := health <= 0 or computed_age >= life_expectancy
		var aged := computed_age > current_age
		if not aged and not died:
			continue

		var result = TransactionResultModel.new()
		var source_fact_ids: Array[String] = [
			"fact.generated_resident.%s" % person_id
		]
		if aged:
			var aged_fact_id := "fact.resident_aged.%s.age%d" % [
				_safe_id(person_id), computed_age
			]
			result.add_state_change({
				"entity_id": person_id,
				"key": "age_years",
				"to": computed_age,
			})
			result.add_state_change({
				"entity_id": person_id,
				"key": "life_stage",
				"to": _life_stage(computed_age, adulthood_age, elder_age),
			})
			result.add_fact({
				"fact_id": aged_fact_id,
				"fact_type": "resident_aged",
				"actor_id": person_id,
				"target_id": person_id,
				"age_years": computed_age,
				"household_id": str(snapshot.get_entity_state(
					person_id, "household_id", ""
				)),
				"settlement_id": str(snapshot.get_entity_state(
					person_id, "settlement_id", ""
				)),
				"source_fact_ids": source_fact_ids.duplicate(),
				"day": day,
				"summary": "%s年满 %d 岁。" % [
					_entity_name(snapshot, person_id), computed_age
				],
			})
			source_fact_ids = [aged_fact_id]
			if current_age < adulthood_age and computed_age >= adulthood_age:
				_append_adulthood(
					result, snapshot, person_id, computed_age,
					day, aged_fact_id
				)
				events.append({
					"event_type": "resident_reached_adulthood",
					"resident_id": person_id,
					"day": day,
				})

		if died:
			_append_death(
				result, snapshot, person, computed_age, health,
				day, source_fact_ids
			)
			events.append({
				"event_type": "resident_died",
				"resident_id": person_id,
				"day": day,
			})
		else:
			result.mark_resolved("population_aging")
		results.append(result)
	return {"results": results, "events": events}


func _append_adulthood(
		result: Variant,
		snapshot: Variant,
		person_id: String,
		age: int,
		day: int,
		aged_fact_id: String
) -> void:
	for change: Dictionary in [
		{"key": "livelihood_status", "to": "unemployed"},
		{"key": "occupation_id", "to": "unemployed"},
		{"key": "livelihood_elapsed_hours", "to": 0},
	]:
		change["entity_id"] = person_id
		result.add_state_change(change)
	var adulthood_fact_id := "fact.resident_reached_adulthood.%s" % _safe_id(
		person_id
	)
	result.add_fact({
		"fact_id": adulthood_fact_id,
		"fact_type": "resident_reached_adulthood",
		"actor_id": person_id,
		"target_id": person_id,
		"age_years": age,
		"household_id": str(snapshot.get_entity_state(
			person_id, "household_id", ""
		)),
		"settlement_id": str(snapshot.get_entity_state(
			person_id, "settlement_id", ""
		)),
		"source_fact_ids": [aged_fact_id],
		"day": day,
		"summary": "%s已经成年，开始寻找自己的生计。" % _entity_name(
			snapshot, person_id
		),
	})
	result.add_chronicle_entry({
		"entry_id": "chronicle.resident_adulthood.%s" % _safe_id(person_id),
		"subject_id": str(snapshot.get_entity_state(
			person_id, "household_id", person_id
		)),
		"title": "%s成年" % _entity_name(snapshot, person_id),
		"body": "家庭中一名年轻人开始独立寻找生计。",
		"source_fact_ids": [adulthood_fact_id],
		"day": day,
	})


func _append_death(
		result: Variant,
		snapshot: Variant,
		person: Dictionary,
		age: int,
		health: int,
		day: int,
		source_fact_ids: Array[String]
) -> void:
	var person_id := str(person.get("id", ""))
	var household_id := str(snapshot.get_entity_state(
		person_id, "household_id", ""
	))
	var settlement_id := str(snapshot.get_entity_state(
		person_id, "settlement_id", ""
	))
	var occupation_id := str(snapshot.get_entity_state(
		person_id, "occupation_id", ""
	))
	var workplace_id := str(snapshot.get_entity_state(
		person_id, "workplace_id", ""
	))
	var institution_role := str(snapshot.get_entity_state(
		person_id, "institution_role", ""
	))
	var death_cause := "fatal_condition" if health <= 0 else "old_age"
	var death_fact_id := "fact.resident_died.%s.day%d" % [
		_safe_id(person_id), day
	]
	result.add_fact({
		"fact_id": death_fact_id,
		"fact_type": "resident_died",
		"actor_id": person_id,
		"target_id": person_id,
		"age_years": age,
		"death_cause": death_cause,
		"household_id": household_id,
		"settlement_id": settlement_id,
		"occupation_id": occupation_id,
		"workplace_id": workplace_id,
		"institution_role": institution_role,
		"source_fact_ids": source_fact_ids.duplicate(),
		"day": day,
		"summary": "%s在 %d 岁时去世。" % [
			_entity_name(snapshot, person_id), age
		],
	})
	result.add_entity_change({
		"operation": "retire",
		"entity_id": person_id,
		"retired_fact_id": death_fact_id,
		"reason": "resident_died",
		"source_fact_ids": [death_fact_id],
		"day": day,
	})
	for change: Dictionary in [
		{"key": "life_status", "to": "dead"},
		{"key": "alive", "to": false},
		{"key": "death_day", "to": day},
		{"key": "death_cause", "to": death_cause},
		{"key": "former_occupation_id", "to": occupation_id},
		{"key": "former_workplace_id", "to": workplace_id},
		{"key": "former_institution_role", "to": institution_role},
		{"key": "livelihood_status", "to": "deceased"},
		{"key": "occupation_id", "to": "none"},
		{"key": "institution_role", "to": ""},
		{"key": "location_id", "to": ""},
		{"key": "visible", "to": false},
	]:
		change["entity_id"] = person_id
		result.add_state_change(change)
	_append_position_vacancy(
		result, snapshot, person_id, institution_role,
		settlement_id, household_id, death_fact_id, day
	)
	result.add_chronicle_entry({
		"entry_id": "chronicle.resident_death.%s.day%d" % [
			_safe_id(person_id), day
		],
		"subject_id": household_id if household_id != "" else settlement_id,
		"title": "%s去世" % _entity_name(snapshot, person_id),
		"body": "这场死亡改变了家庭人口，也可能让工作与地方组织留下空缺。",
		"source_fact_ids": [death_fact_id],
		"day": day,
	})
	result.set_narrative_result({
		"title": "%s去世" % _entity_name(snapshot, person_id),
		"summary": "家庭失去了一名成员，相关工作和职责从此无人承担。",
		"tone": "resident_death",
	})
	result.mark_resolved("population_death")


func _append_position_vacancy(
		result: Variant,
		snapshot: Variant,
		person_id: String,
		institution_role: String,
		settlement_id: String,
		household_id: String,
		death_fact_id: String,
		day: int
) -> void:
	var role_parts := institution_role.split("::", false, 1)
	if role_parts.size() != 2:
		return
	var organization_id := str(role_parts[0])
	var position_id := str(role_parts[1])
	var organization: Dictionary = snapshot.get_entity(organization_id)
	if organization.is_empty():
		return
	var position_label := position_id
	for position_value: Variant in organization.get("positions", []):
		if not position_value is Dictionary:
			continue
		var position := position_value as Dictionary
		if str(position.get("position_id", "")) == position_id:
			position_label = str(position.get("label", position_id))
			break
	result.add_fact({
		"fact_id": "fact.organization_position_vacated.%s.%s.day%d" % [
			_safe_id(organization_id), _safe_id(position_id), day
		],
		"fact_type": "organization_position_vacated",
		"actor_id": organization_id,
		"target_id": person_id,
		"organization_id": organization_id,
		"settlement_id": settlement_id,
		"position_id": position_id,
		"position_label": position_label,
		"household_id": household_id,
		"vacancy_reason": "holder_died",
		"source_fact_ids": [death_fact_id],
		"day": day,
		"summary": "%s去世，%s的%s职位因此空缺。" % [
			_entity_name(snapshot, person_id),
			_entity_name(snapshot, organization_id),
			position_label,
		],
	})


func _life_stage(age: int, adulthood_age: int, elder_age: int) -> String:
	if age < adulthood_age:
		return "child"
	if age >= elder_age:
		return "elder"
	return "adult"


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_")
