extends RefCounted
class_name V5CombatEncounterDirector

const HASH_MODULUS := 2147483647


func select_for_location(
		definitions: Array,
		snapshot: Variant,
		seed: int,
		locked_selections: Dictionary = {}
) -> Dictionary:
	var location_id := str(snapshot.location.get("id", ""))
	var selected: Array[Dictionary] = []
	var selections := locked_selections.duplicate(true)
	var reports := {}
	var grouped := {}

	for definition_value: Variant in definitions:
		if not definition_value is Dictionary:
			continue
		var definition := definition_value as Dictionary
		if str(definition.get("location_id", "")) != location_id:
			continue
		var group_id := str(definition.get("selection_group_id", ""))
		if group_id == "":
			var evaluation := _evaluate(definition, snapshot)
			if bool(evaluation.get("eligible", false)):
				selected.append(definition.duplicate(true))
			continue
		if not grouped.has(group_id):
			grouped[group_id] = []
		(grouped[group_id] as Array).append(definition)

	var group_ids: Array = grouped.keys()
	group_ids.sort()
	for group_value: Variant in group_ids:
		var group_id := str(group_value)
		var candidates: Array = grouped[group_id]
		var locked_id := str(selections.get(group_id, ""))
		if locked_id != "":
			var locked := _definition(candidates, locked_id)
			if not locked.is_empty():
				selected.append(locked.duplicate(true))
			reports[group_id] = _locked_report(
				group_id, candidates, locked_id, seed, snapshot
			)
			continue

		var eligible: Array[Dictionary] = []
		var rejected: Array[Dictionary] = []
		for candidate_value: Variant in candidates:
			var candidate := candidate_value as Dictionary
			var evaluation := _evaluate(candidate, snapshot)
			if bool(evaluation.get("eligible", false)):
				eligible.append(candidate)
			else:
				rejected.append({
					"encounter_id": str(candidate.get("encounter_id", "")),
					"reasons": evaluation.get("reasons", []).duplicate(true),
				})
		eligible.sort_custom(_candidate_precedes)
		var draw := _weighted_selection(eligible, seed, group_id)
		var chosen: Dictionary = draw.get("definition", {})
		var chosen_id := str(chosen.get("encounter_id", ""))
		if chosen_id != "":
			selections[group_id] = chosen_id
			selected.append(chosen.duplicate(true))
		reports[group_id] = {
			"group_id": group_id,
			"location_id": location_id,
			"locked": false,
			"seed": seed,
			"draw": int(draw.get("draw", -1)),
			"total_weight": int(draw.get("total_weight", 0)),
			"candidate_count": candidates.size(),
			"eligible_candidate_count": eligible.size(),
			"eligible_candidate_ids": _encounter_ids(eligible),
			"selected_encounter_id": chosen_id,
			"rejected": rejected,
		}

	return {
		"location_id": location_id,
		"seed": seed,
		"encounters": selected,
		"selections": selections,
		"reports": reports,
	}


func _evaluate(definition: Dictionary, snapshot: Variant) -> Dictionary:
	var reasons: Array[String] = []
	var location_tags: Array = snapshot.location.get("tags", [])
	for tag_value: Variant in definition.get("required_location_tags", []):
		var tag := str(tag_value)
		if tag not in location_tags:
			reasons.append("missing_location_tag:%s" % tag)

	var enemy: Dictionary = definition.get("enemy", {})
	var enemy_id := str(enemy.get("entity_id", ""))
	var enemy_entity: Dictionary = snapshot.get_entity(enemy_id)
	if enemy_id == "" or enemy_entity.is_empty():
		reasons.append("enemy_entity_missing")
	else:
		var enemy_location := str(snapshot.get_entity_state(
			enemy_id,
			"location_id",
			enemy_entity.get("location_id", "")
		))
		if enemy_location != str(snapshot.location.get("id", "")):
			reasons.append("enemy_not_at_location")
		var entity_tags: Array = enemy_entity.get("tags", [])
		for tag_value: Variant in definition.get(
			"required_enemy_tags", []
		):
			var tag := str(tag_value)
			if tag not in entity_tags:
				reasons.append("missing_enemy_tag:%s" % tag)

	var region_requirements: Variant = definition.get(
		"required_region_states", {}
	)
	if region_requirements is Dictionary:
		for key_value: Variant in (region_requirements as Dictionary).keys():
			var key := str(key_value)
			var expected: Variant = (region_requirements as Dictionary)[key_value]
			var actual: Variant = snapshot.region_state.get(key)
			if expected is Array:
				if actual not in (expected as Array):
					reasons.append("region_state_mismatch:%s" % key)
			elif actual != expected:
				reasons.append("region_state_mismatch:%s" % key)

	for key_value: Variant in (
		definition.get("minimum_player_values", {}) as Dictionary
	).keys():
		var key := str(key_value)
		var minimum := int((
			definition.get("minimum_player_values", {}) as Dictionary
		)[key_value])
		if int(snapshot.get_player_value(key, 0)) < minimum:
			reasons.append("player_value_below_minimum:%s" % key)

	var facts: Array = snapshot.get_facts()
	for fact_type_value: Variant in definition.get(
		"required_fact_types", []
	):
		var fact_type := str(fact_type_value)
		if not _has_fact_type(facts, fact_type):
			reasons.append("missing_fact_type:%s" % fact_type)
	for fact_type_value: Variant in definition.get(
		"forbidden_fact_types", []
	):
		var fact_type := str(fact_type_value)
		if _has_fact_type(facts, fact_type):
			reasons.append("forbidden_fact_type:%s" % fact_type)
	for requirement_value: Variant in definition.get("required_facts", []):
		if not requirement_value is Dictionary:
			continue
		var requirement := requirement_value as Dictionary
		if not _has_matching_fact(facts, requirement):
			reasons.append("missing_required_fact")

	if definition.has("available_hour_start"):
		var hour := int(snapshot.world_time.get("hour", 0))
		var start := int(definition.get("available_hour_start", 0))
		var end := int(definition.get("available_hour_end", 24))
		var available := (
			hour >= start and hour < end
			if start <= end
			else hour >= start or hour < end
		)
		if not available:
			reasons.append("outside_time_window")

	for requirement_value: Variant in definition.get(
		"minimum_pressures", []
	):
		if not requirement_value is Dictionary:
			continue
		if not _pressure_requirement_met(
			requirement_value as Dictionary,
			snapshot.get_pressures()
		):
			reasons.append("pressure_below_minimum")

	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
	}


func _weighted_selection(
		eligible: Array[Dictionary], seed: int, group_id: String
) -> Dictionary:
	if eligible.is_empty():
		return {"definition": {}, "draw": -1, "total_weight": 0}
	var total_weight := 0
	for candidate: Dictionary in eligible:
		total_weight += maxi(int(candidate.get("selection_weight", 1)), 1)
	var draw := _stable_value(seed, group_id) % total_weight
	var cursor := draw
	for candidate: Dictionary in eligible:
		cursor -= maxi(int(candidate.get("selection_weight", 1)), 1)
		if cursor < 0:
			return {
				"definition": candidate,
				"draw": draw,
				"total_weight": total_weight,
			}
	return {
		"definition": eligible.back(),
		"draw": draw,
		"total_weight": total_weight,
	}


func _stable_value(seed: int, group_id: String) -> int:
	var value := posmod(seed, HASH_MODULUS)
	for index: int in range(group_id.length()):
		value = posmod(
			value * 31 + group_id.unicode_at(index),
			HASH_MODULUS
		)
	return value


func _candidate_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_order := int(left.get("selection_order", 0))
	var right_order := int(right.get("selection_order", 0))
	if left_order != right_order:
		return left_order < right_order
	return str(left.get("encounter_id", "")) < str(
		right.get("encounter_id", "")
	)


func _definition(candidates: Array, encounter_id: String) -> Dictionary:
	for candidate_value: Variant in candidates:
		if not candidate_value is Dictionary:
			continue
		var candidate := candidate_value as Dictionary
		if str(candidate.get("encounter_id", "")) == encounter_id:
			return candidate
	return {}


func _locked_report(
		group_id: String,
		candidates: Array,
		locked_id: String,
		seed: int,
		snapshot: Variant
) -> Dictionary:
	var eligible: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	for candidate_value: Variant in candidates:
		if not candidate_value is Dictionary:
			continue
		var candidate := candidate_value as Dictionary
		var evaluation := _evaluate(candidate, snapshot)
		if bool(evaluation.get("eligible", false)):
			eligible.append(candidate)
		else:
			rejected.append({
				"encounter_id": str(candidate.get("encounter_id", "")),
				"reasons": evaluation.get("reasons", []).duplicate(true),
			})
	return {
		"group_id": group_id,
		"locked": true,
		"seed": seed,
		"candidate_count": candidates.size(),
		"eligible_candidate_count": eligible.size(),
		"eligible_candidate_ids": _encounter_ids(eligible),
		"selected_encounter_id": locked_id,
		"rejected": rejected,
	}


func _encounter_ids(candidates: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for candidate: Dictionary in candidates:
		ids.append(str(candidate.get("encounter_id", "")))
	return ids


func _has_fact_type(facts: Array, fact_type: String) -> bool:
	for fact_value: Variant in facts:
		if (
			fact_value is Dictionary
			and str((fact_value as Dictionary).get("fact_type", ""))
				== fact_type
		):
			return true
	return false


func _has_matching_fact(facts: Array, requirement: Dictionary) -> bool:
	for fact_value: Variant in facts:
		if not fact_value is Dictionary:
			continue
		var fact := fact_value as Dictionary
		var matches := true
		for key_value: Variant in requirement.keys():
			var key := str(key_value)
			if fact.get(key) != requirement[key_value]:
				matches = false
				break
		if matches:
			return true
	return false


func _pressure_requirement_met(
		requirement: Dictionary, pressures: Array
) -> bool:
	for pressure_value: Variant in pressures:
		if not pressure_value is Dictionary:
			continue
		var pressure := pressure_value as Dictionary
		if (
			str(pressure.get("pressure_type", ""))
				!= str(requirement.get("pressure_type", ""))
		):
			continue
		var scope_id := str(requirement.get("scope_id", ""))
		if scope_id != "" and str(pressure.get("scope_id", "")) != scope_id:
			continue
		if int(pressure.get("value", 0)) >= int(
			requirement.get("minimum_value", 0)
		):
			return true
	return false
