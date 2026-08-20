extends RefCounted
class_name V5OrganizationLifecycleSystem

const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)


func resolve_tick(
		snapshot: Variant,
		tick_event: Dictionary,
		config: Dictionary
) -> Dictionary:
	var day := int(tick_event.get("day", 0))
	if (
		day <= 0
		or not bool(config.get("lifecycle_enabled", false))
	):
		return {"results": [], "events": []}

	var prototypes := _lifecycle_prototypes(config)
	if prototypes.is_empty():
		return {"results": [], "events": []}

	var results: Array = []
	var events: Array = []
	for settlement: Dictionary in _settlements(snapshot):
		for prototype: Dictionary in prototypes:
			var resolution := _resolve_pair(
				snapshot, settlement, prototype, config, day
			)
			results.append_array(resolution.get("results", []))
			events.append_array(resolution.get("events", []))
	return {"results": results, "events": events}


func _resolve_pair(
		snapshot: Variant,
		settlement: Dictionary,
		prototype: Dictionary,
		config: Dictionary,
		day: int
) -> Dictionary:
	var settlement_id := str(settlement.get("id", ""))
	var prototype_id := str(prototype.get("prototype_id", ""))
	var lifecycle: Dictionary = prototype.get("lifecycle", {})
	var state_key := str(lifecycle.get("state_key", ""))
	if settlement_id == "" or prototype_id == "" or state_key == "":
		return {"results": [], "events": []}

	var signal_value := str(snapshot.get_entity_state(
		settlement_id, state_key, ""
	))
	var source_fact := _latest_pressure_fact(
		snapshot, settlement_id, state_key, signal_value
	)
	if source_fact.is_empty():
		return {"results": [], "events": []}

	var active := _active_organization(
		snapshot, settlement_id, prototype_id
	)
	if not active.is_empty():
		if "runtime_organization" not in (active.get("tags", []) as Array):
			return {"results": [], "events": []}
		return _resolve_active(
			snapshot,
			settlement,
			prototype,
			active,
			signal_value,
			source_fact,
			day
		)

	if signal_value not in (lifecycle.get("formation_values", []) as Array):
		return {"results": [], "events": []}
	if not _industry_requirements_met(snapshot, settlement_id, prototype):
		return {"results": [], "events": []}
	if _in_cooldown(snapshot, settlement_id, prototype_id, lifecycle, day):
		return {"results": [], "events": []}

	var observation := _observation(
		snapshot,
		settlement_id,
		prototype_id,
		state_key,
		signal_value,
		"formation",
		source_fact,
		day
	)
	if observation.is_empty():
		return {"results": [], "events": []}
	var observation_result: Variant = observation.get("result")
	var results: Array = [observation_result]
	var events: Array = [observation.get("event", {})]
	if int(observation.get("streak", 0)) >= maxi(int(lifecycle.get(
		"formation_delay_days", 2
	)), 1):
		var formation := _formation_result(
			snapshot,
			settlement,
			prototype,
			config,
			str(observation.get("fact_id", "")),
			int(observation.get("streak", 0)),
			day
		)
		if not formation.is_empty():
			results.append(formation.get("result"))
			events.append(formation.get("event", {}))
	return {"results": results, "events": events}


func _resolve_active(
		snapshot: Variant,
		settlement: Dictionary,
		prototype: Dictionary,
		organization: Dictionary,
		signal_value: String,
		source_fact: Dictionary,
		day: int
) -> Dictionary:
	var lifecycle: Dictionary = prototype.get("lifecycle", {})
	var recovery_values: Array = lifecycle.get("recovery_values", [])
	var formation_values: Array = lifecycle.get("formation_values", [])
	var recovery_goal := str(lifecycle.get("recovery_goal", ""))
	var active_goal := str(lifecycle.get(
		"active_goal", prototype.get("goal", "")
	))
	var organization_goal := str(organization.get("goal", ""))
	if signal_value in formation_values and organization_goal == recovery_goal:
		var resumed := _goal_change_result(
			settlement,
			organization,
			active_goal,
			"organization_goal_reactivated",
			"压力再次升高，临时组织恢复应急目标。",
			str(source_fact.get("fact_id", "")),
			day
		)
		return {
			"results": [resumed.get("result")],
			"events": [resumed.get("event", {})],
		}
	if signal_value not in recovery_values:
		return {"results": [], "events": []}

	var settlement_id := str(settlement.get("id", ""))
	var prototype_id := str(prototype.get("prototype_id", ""))
	var observation := _observation(
		snapshot,
		settlement_id,
		prototype_id,
		str(lifecycle.get("state_key", "")),
		signal_value,
		"recovery",
		source_fact,
		day
	)
	if observation.is_empty():
		return {"results": [], "events": []}
	var results: Array = [observation.get("result")]
	var events: Array = [observation.get("event", {})]
	var observation_fact_id := str(observation.get("fact_id", ""))
	var retirement_delay := maxi(int(lifecycle.get(
		"retirement_delay_days", 2
	)), 1)
	if int(observation.get("streak", 0)) >= retirement_delay:
		var retirement := _retirement_result(
			snapshot,
			settlement,
			organization,
			observation_fact_id,
			day
		)
		results.append(retirement.get("result"))
		events.append(retirement.get("event", {}))
	elif recovery_goal != "" and organization_goal != recovery_goal:
		var changed := _goal_change_result(
			settlement,
			organization,
			recovery_goal,
			"organization_goal_changed",
			"粮压已经缓解，临时组织转向核清余项并准备退出。",
			observation_fact_id,
			day
		)
		results.append(changed.get("result"))
		events.append(changed.get("event", {}))
	return {"results": results, "events": events}


func _observation(
		snapshot: Variant,
		settlement_id: String,
		prototype_id: String,
		state_key: String,
		signal_value: String,
		phase: String,
		source_fact: Dictionary,
		day: int
) -> Dictionary:
	var fact_id := "fact.organization_lifecycle_signal.%s.%s.%s.day%d" % [
		_safe_id(settlement_id), _safe_id(prototype_id), phase, day
	]
	if _fact_exists(snapshot, fact_id):
		return {}
	var previous := _previous_observation(
		snapshot, settlement_id, prototype_id, phase, day
	)
	var streak := (
		int(previous.get("streak", 0)) + 1
		if int(previous.get("day", 0)) == day - 1
		else 1
	)
	var result = TransactionResultModel.new()
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "organization_lifecycle_signal_observed",
		"actor_id": settlement_id,
		"target_id": settlement_id,
		"settlement_id": settlement_id,
		"prototype_id": prototype_id,
		"state_key": state_key,
		"signal_value": signal_value,
		"phase": phase,
		"streak": streak,
		"day": day,
		"source_fact_ids": [str(source_fact.get("fact_id", ""))],
		"summary": "%s已连续 %d 天处于%s阶段的组织压力条件。" % [
			_entity_name(snapshot, settlement_id), streak,
			"形成" if phase == "formation" else "收尾",
		],
	})
	result.mark_resolved("organization_lifecycle_observation")
	return {
		"result": result,
		"fact_id": fact_id,
		"streak": streak,
		"event": {
			"event_type": "organization_lifecycle_signal_observed",
			"settlement_id": settlement_id,
			"prototype_id": prototype_id,
			"phase": phase,
			"streak": streak,
			"day": day,
		},
	}


func _formation_result(
		snapshot: Variant,
		settlement: Dictionary,
		prototype: Dictionary,
		config: Dictionary,
		observation_fact_id: String,
		streak: int,
		day: int
) -> Dictionary:
	var settlement_id := str(settlement.get("id", ""))
	var prototype_id := str(prototype.get("prototype_id", ""))
	var cycle := _next_cycle(snapshot, settlement_id, prototype_id)
	var organization_id := "runtime_organization.%s.%s.cycle%d" % [
		_site_token(settlement_id), _safe_id(prototype_id), cycle
	]
	var positions := _assigned_positions(
		snapshot,
		settlement_id,
		organization_id,
		prototype.get("positions", []),
		day
	)
	var founding_member_ids: Array[String] = []
	for position: Dictionary in positions:
		var holder_id := str(position.get("founding_holder_id", ""))
		if holder_id != "":
			founding_member_ids.append(holder_id)
	if founding_member_ids.is_empty():
		return {}

	var formation_fact_id := "fact.organization_runtime_formed.%s" % (
		_safe_id(organization_id)
	)
	var organization_name := "%s临时%s" % [
		str(settlement.get("display_name", "聚落")),
		str(prototype.get("name_suffix", "议事会")),
	]
	var lifecycle: Dictionary = prototype.get("lifecycle", {})
	var goal := str(lifecycle.get(
		"active_goal", prototype.get("goal", "协调当前压力。")
	))
	var resource_stock_ids := _resource_stock_ids(
		snapshot,
		settlement_id,
		prototype.get("resource_tags_any", []),
		maxi(int(config.get("maximum_resource_links", 3)), 0),
		str((prototype.get("runtime_response", {}) as Dictionary).get(
			"action_kind", ""
		))
	)
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "create",
		"entity": {
			"id": organization_id,
			"type": "institution",
			"display_name": organization_name,
			"description": "由持续的现实压力和当地居民临时形成的组织。%s" % str(
				prototype.get("description", "")
			),
			"tags": [
				"institution", "organization", "generated_organization",
				"runtime_organization",
				str(prototype.get("organization_kind", "local_association")),
			],
			"settlement_id": settlement_id,
			"organization_kind": str(prototype.get(
				"organization_kind", "local_association"
			)),
			"prototype_id": prototype_id,
			"goal": goal,
			"need_signals": {"formation_streak": streak},
			"runtime_response": (
				prototype.get("runtime_response", {}) as Dictionary
			).duplicate(true),
			"positions": positions.duplicate(true),
			"founding_member_ids": founding_member_ids.duplicate(),
			"resource_stock_ids": resource_stock_ids.duplicate(),
			"formation_day": day,
			"formation_cycle": cycle,
			"source_fact_ids": [observation_fact_id],
		},
		"source_fact_ids": [formation_fact_id],
	})
	result.add_state_change({
		"entity_id": organization_id,
		"key": "location_id",
		"to": str(snapshot.get_entity_state(
			settlement_id, "location_id", ""
		)),
	})
	result.add_state_change({
		"entity_id": organization_id,
		"key": "visible",
		"to": false,
	})
	result.add_fact({
		"fact_id": formation_fact_id,
		"fact_type": "organization_runtime_formed",
		"actor_id": settlement_id,
		"target_id": organization_id,
		"organization_id": organization_id,
		"settlement_id": settlement_id,
		"prototype_id": prototype_id,
		"founding_member_ids": founding_member_ids.duplicate(),
		"resource_stock_ids": resource_stock_ids.duplicate(),
		"formation_streak": streak,
		"day": day,
		"source_fact_ids": [observation_fact_id],
		"summary": "%s连续承受压力后，%s由 %d 名当地居民组成。" % [
			str(settlement.get("display_name", "聚落")),
			organization_name,
			founding_member_ids.size(),
		],
	})
	for position: Dictionary in positions:
		var position_id := str(position.get("position_id", "member"))
		var member_id := str(position.get("founding_holder_id", ""))
		if member_id == "":
			result.add_fact({
				"fact_id": "fact.organization_position_vacated.%s.%s.day%d" % [
					_safe_id(organization_id), _safe_id(position_id), day
				],
				"fact_type": "organization_position_vacated",
				"actor_id": organization_id,
				"target_id": organization_id,
				"organization_id": organization_id,
				"settlement_id": settlement_id,
				"position_id": position_id,
				"position_label": str(position.get("label", "成员")),
				"source_fact_ids": [formation_fact_id],
				"day": day,
				"summary": "%s成立时仍缺少%s。" % [
					organization_name, str(position.get("label", "成员"))
				],
			})
			continue
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
				"delta": 30,
			},
			{
				"source_id": organization_id,
				"target_id": member_id,
				"axis": "trust",
				"delta": 12,
			},
			{
				"source_id": member_id,
				"target_id": organization_id,
				"axis": "familiarity",
				"delta": 30,
			},
		]:
			result.add_relationship_change(change)
		result.add_fact({
			"fact_id": "fact.organization_position_assigned.%s.%s.day%d" % [
				_safe_id(organization_id), _safe_id(position_id), day
			],
			"fact_type": "organization_position_assigned",
			"actor_id": organization_id,
			"target_id": member_id,
			"organization_id": organization_id,
			"settlement_id": settlement_id,
			"position_id": position_id,
			"position_label": str(position.get("label", "成员")),
			"selection_score": int(position.get("selection_score", 0)),
			"source_fact_ids": [formation_fact_id],
			"day": day,
			"summary": "%s因当地压力加入%s，担任%s。" % [
				_entity_name(snapshot, member_id),
				organization_name,
				str(position.get("label", "成员")),
			],
		})
	result.add_chronicle_entry({
		"entry_id": "chronicle.organization_runtime_formed.%s" % (
			_safe_id(organization_id)
		),
		"subject_id": organization_id,
		"title": "%s成立" % organization_name,
		"body": "%s连续承受现实压力后，当地居民临时承担职位。目标是%s" % [
			str(settlement.get("display_name", "聚落")), goal
		],
		"source_fact_ids": [formation_fact_id],
		"day": day,
	})
	result.set_narrative_result({
		"title": "%s成立" % organization_name,
		"summary": "%d 名当地居民因持续粮压组成临时共食组织，开始协调口粮。" % (
			founding_member_ids.size()
		),
		"tone": "organization_formed",
	})
	result.mark_resolved("organization_runtime_formation")
	return {
		"result": result,
		"event": {
			"event_type": "organization_runtime_formed",
			"organization_id": organization_id,
			"settlement_id": settlement_id,
			"day": day,
		},
	}


func _goal_change_result(
	settlement: Dictionary,
	organization: Dictionary,
	goal: String,
	fact_type: String,
	summary: String,
	source_fact_id: String,
	day: int
) -> Dictionary:
	var organization_id := str(organization.get("id", ""))
	var fact_id := "fact.%s.%s.day%d" % [
		fact_type, _safe_id(organization_id), day
	]
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "update",
		"entity_id": organization_id,
		"fields": {"goal": goal},
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": fact_type,
		"actor_id": organization_id,
		"target_id": organization_id,
		"organization_id": organization_id,
		"settlement_id": str(settlement.get("id", "")),
		"goal": goal,
		"day": day,
		"source_fact_ids": [source_fact_id],
		"summary": "%s：%s" % [
			str(organization.get("display_name", "临时组织")), summary
		],
	})
	result.set_narrative_result({
		"title": "%s调整目标" % str(organization.get(
			"display_name", "临时组织"
		)),
		"summary": summary,
		"tone": "organization_goal_changed",
	})
	result.mark_resolved("organization_runtime_goal_change")
	return {
		"result": result,
		"event": {
			"event_type": fact_type,
			"organization_id": organization_id,
			"day": day,
		},
	}


func _retirement_result(
		snapshot: Variant,
		settlement: Dictionary,
		organization: Dictionary,
		observation_fact_id: String,
		day: int
) -> Dictionary:
	var organization_id := str(organization.get("id", ""))
	var organization_name := str(organization.get(
		"display_name", "临时组织"
	))
	var fact_id := "fact.organization_runtime_retired.%s.day%d" % [
		_safe_id(organization_id), day
	]
	var result = TransactionResultModel.new()
	result.add_entity_change({
		"operation": "retire",
		"entity_id": organization_id,
		"retired_fact_id": fact_id,
		"day": day,
		"reason": "粮食压力连续缓解后临时职责结束",
		"source_fact_ids": [fact_id],
	})
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "organization_runtime_retired",
		"actor_id": organization_id,
		"target_id": organization_id,
		"organization_id": organization_id,
		"settlement_id": str(settlement.get("id", "")),
		"prototype_id": str(organization.get("prototype_id", "")),
		"day": day,
		"source_fact_ids": [observation_fact_id],
		"summary": "粮压持续缓解后，%s结束临时职责，但成员、关系和行动仍保留在历史中。" % (
			organization_name
		),
	})
	for position_value: Variant in organization.get("positions", []):
		if not position_value is Dictionary:
			continue
		var position: Dictionary = position_value
		var position_id := str(position.get("position_id", "member"))
		var holder_id := _current_holder_id(
			snapshot, organization, position_id
		)
		if holder_id == "":
			continue
		result.add_state_change({
			"entity_id": holder_id,
			"key": "institution_role",
			"to": "",
		})
		result.add_fact({
			"fact_id": "fact.organization_position_ended.%s.%s.day%d" % [
				_safe_id(organization_id), _safe_id(position_id), day
			],
			"fact_type": "organization_position_ended",
			"actor_id": organization_id,
			"target_id": holder_id,
			"organization_id": organization_id,
			"settlement_id": str(settlement.get("id", "")),
			"position_id": position_id,
			"position_label": str(position.get("label", "成员")),
			"day": day,
			"source_fact_ids": [fact_id],
			"summary": "%s随%s退出而结束任职。" % [
				_entity_name(snapshot, holder_id), organization_name
			],
		})
	result.add_chronicle_entry({
		"entry_id": "chronicle.organization_runtime_retired.%s.day%d" % [
			_safe_id(organization_id), day
		],
		"subject_id": organization_id,
		"title": "%s结束职责" % organization_name,
		"body": "连续缓解的粮压让临时职责失去必要性。组织退出，既有事实与关系保留。",
		"source_fact_ids": [fact_id],
		"day": day,
	})
	result.set_narrative_result({
		"title": "%s结束职责" % organization_name,
		"summary": "粮压连续缓解后，这个临时组织退出；它留下的任职与行动仍属于世界历史。",
		"tone": "organization_retired",
	})
	result.mark_resolved("organization_runtime_retirement")
	return {
		"result": result,
		"event": {
			"event_type": "organization_runtime_retired",
			"organization_id": organization_id,
			"settlement_id": str(settlement.get("id", "")),
			"day": day,
		},
	}


func _lifecycle_prototypes(config: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value: Variant in config.get("lifecycle_prototypes", []):
		if value is Dictionary and not (value as Dictionary).get(
			"lifecycle", {}
		).is_empty():
			rows.append((value as Dictionary).duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("prototype_id", "")) < str(b.get("prototype_id", ""))
	)
	return rows


func _settlements(snapshot: Variant) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entity: Dictionary in snapshot.get_entities():
		if "generated_settlement" in (entity.get("tags", []) as Array):
			rows.append(entity)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return rows


func _active_organization(
		snapshot: Variant, settlement_id: String, prototype_id: String
) -> Dictionary:
	for entity: Dictionary in snapshot.get_entities():
		if (
			"generated_organization" in (entity.get("tags", []) as Array)
			and str(entity.get("lifecycle_status", "active")) != "retired"
			and str(entity.get("settlement_id", "")) == settlement_id
			and str(entity.get("prototype_id", "")) == prototype_id
		):
			return entity
	return {}


func _latest_pressure_fact(
		snapshot: Variant,
		settlement_id: String,
		state_key: String,
		signal_value: String
) -> Dictionary:
	var facts: Array = snapshot.get_facts()
	for index: int in range(facts.size() - 1, -1, -1):
		var fact: Dictionary = facts[index]
		if (
			str(fact.get("fact_type", ""))
			== "settlement_resource_pressure_changed"
			and str(fact.get("target_id", "")) == settlement_id
		):
			return (
				fact
				if str(fact.get(state_key, "")) == signal_value
				else {}
			)
	return {}


func _previous_observation(
		snapshot: Variant,
	settlement_id: String,
	prototype_id: String,
	phase: String,
	day: int
) -> Dictionary:
	var latest: Dictionary = {}
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", ""))
			!= "organization_lifecycle_signal_observed"
			or str(fact.get("settlement_id", "")) != settlement_id
			or str(fact.get("prototype_id", "")) != prototype_id
			or str(fact.get("phase", "")) != phase
			or int(fact.get("day", 0)) >= day
		):
			continue
		if latest.is_empty() or int(fact.get("day", 0)) > int(
			latest.get("day", 0)
		):
			latest = fact
	return latest


func _industry_requirements_met(
		snapshot: Variant, settlement_id: String, prototype: Dictionary
) -> bool:
	var required: Array = prototype.get("required_any_industry_ids", [])
	if required.is_empty():
		return true
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "settlement_industry_selected"
			and str(fact.get("actor_id", "")) == settlement_id
			and str(fact.get("industry_id", "")) in required
		):
			return true
	return false


func _in_cooldown(
		snapshot: Variant,
	settlement_id: String,
	prototype_id: String,
	lifecycle: Dictionary,
	day: int
) -> bool:
	var latest_retired_day := -999999
	for entity: Dictionary in snapshot.get_entities():
		if (
			"runtime_organization" in (entity.get("tags", []) as Array)
			and str(entity.get("lifecycle_status", "active")) == "retired"
			and str(entity.get("settlement_id", "")) == settlement_id
			and str(entity.get("prototype_id", "")) == prototype_id
		):
			latest_retired_day = maxi(
				latest_retired_day, int(entity.get("retired_day", 0))
			)
	return day - latest_retired_day < maxi(int(lifecycle.get(
		"cooldown_days", 0
	)), 0)


func _next_cycle(
		snapshot: Variant, settlement_id: String, prototype_id: String
) -> int:
	var count := 0
	for fact: Dictionary in snapshot.get_facts():
		if (
			str(fact.get("fact_type", "")) == "organization_runtime_formed"
			and str(fact.get("settlement_id", "")) == settlement_id
			and str(fact.get("prototype_id", "")) == prototype_id
		):
			count += 1
	return count + 1


func _assigned_positions(
		snapshot: Variant,
	settlement_id: String,
	organization_id: String,
	position_values: Variant,
	day: int
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var reserved: Dictionary = {}
	if not position_values is Array:
		return rows
	for value: Variant in position_values:
		if not value is Dictionary:
			continue
		var position: Dictionary = (value as Dictionary).duplicate(true)
		var candidate := _select_candidate(
			snapshot,
			settlement_id,
			organization_id,
			position,
			reserved,
			day
		)
		position["founding_holder_id"] = str(candidate.get("member_id", ""))
		position["selection_score"] = int(candidate.get("selection_score", 0))
		if str(candidate.get("member_id", "")) != "":
			reserved[str(candidate.get("member_id", ""))] = true
		rows.append(position)
	return rows


func _select_candidate(
		snapshot: Variant,
	settlement_id: String,
	organization_id: String,
	position: Dictionary,
	reserved: Dictionary,
	day: int
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var preferred: Array = position.get("preferred_occupation_ids", [])
	var attribute_bias: Dictionary = position.get("attribute_bias", {})
	for person: Dictionary in snapshot.get_entities_by_type("person"):
		var person_id := str(person.get("id", ""))
		if (
			reserved.has(person_id)
			or int(snapshot.get_entity_state(person_id, "age_years", 0)) < 18
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
		rows.append({
			"member_id": person_id,
			"selection_score": score,
			"tie_break": _stable_noise("%d:%s:%s:%s" % [
				day,
				organization_id,
				str(position.get("position_id", "")),
				person_id,
			]),
		})
	if rows.is_empty():
		return {}
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("selection_score", 0)) != int(b.get("selection_score", 0)):
			return int(a.get("selection_score", 0)) > int(b.get("selection_score", 0))
		if int(a.get("tie_break", 0)) != int(b.get("tie_break", 0)):
			return int(a.get("tie_break", 0)) > int(b.get("tie_break", 0))
		return str(a.get("member_id", "")) < str(b.get("member_id", ""))
	)
	return rows[0]


func _resource_stock_ids(
		snapshot: Variant,
		settlement_id: String,
		tag_values: Variant,
		maximum_count: int,
		action_kind: String
) -> Array[String]:
	var tags: Array = tag_values if tag_values is Array else []
	var candidates: Array[Dictionary] = []
	for stock: Dictionary in snapshot.get_resource_stocks():
		if (
			str(stock.get("settlement_id", "")) == settlement_id
			and _arrays_intersect(stock.get("tags", []), tags)
		):
			candidates.append(stock)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_priority := _resource_priority(a, action_kind)
		var b_priority := _resource_priority(b, action_kind)
		if a_priority != b_priority:
			return a_priority > b_priority
		if float(a.get("current", 0.0)) != float(b.get("current", 0.0)):
			return float(a.get("current", 0.0)) > float(b.get("current", 0.0))
		return str(a.get("stock_id", "")) < str(b.get("stock_id", ""))
	)
	var rows: Array[String] = []
	for stock: Dictionary in candidates:
		if rows.size() >= maximum_count:
			break
		rows.append(str(stock.get("stock_id", "")))
	return rows


func _resource_priority(stock: Dictionary, action_kind: String) -> int:
	var tags: Array = stock.get("tags", [])
	if action_kind == "local_provisioning":
		if (
			str(stock.get("source_kind", "")) == "trade_reserve"
			and "food" in tags
		):
			return 300
		if "food" in tags:
			return 200
	return 100


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


func _arrays_intersect(left_value: Variant, right_value: Variant) -> bool:
	var left: Array = left_value if left_value is Array else []
	var right: Array = right_value if right_value is Array else []
	for value: Variant in left:
		if value in right:
			return true
	return false


func _fact_exists(snapshot: Variant, fact_id: String) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return true
	return false


func _entity_name(snapshot: Variant, entity_id: String) -> String:
	var entity: Dictionary = snapshot.get_entity(entity_id)
	return str(entity.get("display_name", entity_id))


func _site_token(settlement_id: String) -> String:
	return _safe_id(settlement_id.trim_prefix("generated_settlement."))


func _stable_noise(key: String) -> int:
	return int(("0x" + key.sha256_text().substr(0, 8)).hex_to_int() % 1000000)


func _safe_id(value: String) -> String:
	return value.to_lower().replace(" ", "_").replace(":", "_").replace(".", "_")
