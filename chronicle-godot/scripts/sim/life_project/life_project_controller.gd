extends RefCounted
class_name V5LifeProjectController

const SimRegistryModel = preload("res://scripts/sim/core/sim_registry.gd")
const SimSessionModel = preload("res://scripts/sim/core/sim_session.gd")
const TransactionResultModel = preload(
	"res://scripts/sim/transaction/transaction_result.gd"
)
const TickEventSchemaModel = preload(
	"res://scripts/sim/world_tick/tick_event_schema.gd"
)
const ActionContractResolverModel = preload(
	"res://scripts/sim/action/action_contract_resolver.gd"
)
const EffectProtocolResolverModel = preload(
	"res://scripts/sim/transaction/effect_protocol_resolver.gd"
)
const SimSnapshotModel = preload("res://scripts/sim/core/sim_snapshot.gd")
const LifeStageTransitionServiceModel = preload(
	"res://scripts/sim/save/life_stage_transition_service.gd"
)

var session: Variant = null
var definition: Dictionary = {}
var project_id: String = ""
var day_history: Array[Dictionary] = []
var duty_counts: Dictionary = {}
var latest_result: Dictionary = {}
var initialized: bool = false
var fixture_source_path: String = ""
var project_source_path: String = ""
var rule_source_paths: Array = []
var entry_transition: Dictionary = {}
var pending_incident: Dictionary = {}
var incident_history: Array[Dictionary] = []
var incident_counts: Dictionary = {}
var action_contract_resolver: Variant = ActionContractResolverModel.new()
var effect_protocol_resolver: Variant = EffectProtocolResolverModel.new()


func start(
		fixture_path: String,
		project_path: String,
		rule_paths: Array = [],
		start_options: Dictionary = {}
) -> Dictionary:
	reset()
	var loader = SimRegistryModel.new()
	definition = loader.load_json(project_path)
	if definition.is_empty():
		return _failure("project_not_loaded")
	project_id = str(definition.get("project_id", ""))
	if project_id == "":
		return _failure("missing_project_id")
	session = SimSessionModel.new()
	var start_result: Dictionary = session.start_from_fixture_path(
		fixture_path,
		rule_paths,
		start_options
	)
	if not bool(start_result.get("success", false)):
		return start_result
	fixture_source_path = fixture_path
	project_source_path = project_path
	rule_source_paths = rule_paths.duplicate(true)
	action_contract_resolver.configure(session.registry)
	initialized = true
	_clamp_states()
	return {
		"success": true,
		"project_id": project_id,
		"day": get_day(),
		"duration_days": get_duration_days(),
	}


func reset() -> void:
	session = null
	definition = {}
	project_id = ""
	day_history.clear()
	duty_counts.clear()
	latest_result = {}
	initialized = false
	fixture_source_path = ""
	project_source_path = ""
	rule_source_paths = []
	entry_transition = {}
	pending_incident = {}
	incident_history.clear()
	incident_counts.clear()


func set_entry_transition(transition: Dictionary) -> void:
	entry_transition = transition.duplicate(true)


func get_entry_transition() -> Dictionary:
	return entry_transition.duplicate(true)


func build_save_envelope(options: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return {}
	var save_options := options.duplicate(true)
	save_options["life_project_runtime"] = _life_project_save_data()
	return session.build_save_envelope(save_options)


func build_life_stage_transition(target_fixture_id: String) -> Dictionary:
	if (
		not is_complete()
		or (
			bool(definition.get(
				"transition_requires_milestone_resolution", true
			))
			and not definition.get("milestone", {}).is_empty()
			and not bool(get_milestone_summary().get("resolved", false))
		)
		or (
			bool(definition.get(
				"transition_requires_growth_confirmation", true
			))
			and _confirmed_growth_candidate_id() == ""
		)
		or target_fixture_id == ""
	):
		return {}
	return LifeStageTransitionServiceModel.new().build_player_transition(
		session,
		{
			"target_fixture_id": target_fixture_id,
			"persistent_entity_ids": definition.get(
				"transition_persistent_entity_ids", []
			),
		}
	)


func save_to_path(path: String, options: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return _failure("project_not_initialized")
	var save_options := options.duplicate(true)
	save_options["life_project_runtime"] = _life_project_save_data()
	return session.save_to_path(path, save_options)


func load_from_path(path: String) -> Dictionary:
	reset()
	session = SimSessionModel.new()
	var result: Dictionary = session.load_from_path(path)
	if not bool(result.get("success", false)):
		return result
	return _restore_life_project(result)


func load_from_save_envelope(envelope: Variant) -> Dictionary:
	reset()
	session = SimSessionModel.new()
	var result: Dictionary = session.load_from_save_envelope(envelope)
	if not bool(result.get("success", false)):
		return result
	return _restore_life_project(result)


func is_ready() -> bool:
	return initialized and session != null and session.is_ready()


func is_complete() -> bool:
	return (
		is_ready()
		and get_day() > get_duration_days()
		and not has_pending_incident()
	)


func has_pending_incident() -> bool:
	return not pending_incident.is_empty()


func get_day() -> int:
	if not is_ready():
		return 0
	return int(session.get_snapshot().get_player_value("service_day", 1))


func get_duration_days() -> int:
	return maxi(int(definition.get("duration_days", 1)), 1)


func get_calendar_days_per_step() -> int:
	return get_calendar_days_for_step(get_day())


func get_calendar_days_for_step(step: int) -> int:
	var schedule: Variant = definition.get("calendar_days_by_step", [])
	if schedule is Array and not (schedule as Array).is_empty():
		var index := clampi(step - 1, 0, (schedule as Array).size() - 1)
		return maxi(int((schedule as Array)[index]), 1)
	return maxi(int(definition.get("calendar_days_per_step", 1)), 1)


func get_progress_unit_label() -> String:
	return str(definition.get("progress_unit_label", "天"))


func get_ritual() -> Dictionary:
	var ritual: Dictionary = definition.get("ritual", {}).duplicate(true)
	for variant_value: Variant in ritual.get("variants", []):
		if not variant_value is Dictionary:
			continue
		var variant := variant_value as Dictionary
		if not _conditions_match(variant.get("conditions", [])):
			continue
		for key: String in ["title", "body"]:
			if variant.has(key):
				ritual[key] = variant.get(key)
		break
	var step := mini(get_day(), get_duration_days())
	return {
		"title": _replace_ritual_tokens(
			str(ritual.get("title", "清晨点名")), step
		),
		"body": _replace_ritual_tokens(str(ritual.get("body", "")), step),
	}


func get_duty_options() -> Array:
	var rows: Array[Dictionary] = []
	if (
		not is_ready()
		or has_pending_incident()
		or get_day() > get_duration_days()
	):
		return rows
	for duty_value: Variant in definition.get("duties", []):
		if not (duty_value is Dictionary):
			continue
		var duty := duty_value as Dictionary
		if not _conditions_match(duty.get("available_if", [])):
			continue
		var eligibility := _duty_eligibility(duty)
		rows.append({
			"duty_id": str(duty.get("duty_id", "")),
			"label": str(duty.get("label", "承担值勤")),
			"kind": str(duty.get("kind", "值勤")),
			"hint": str(duty.get("hint", "")),
			"calendar_days": get_calendar_days_per_step(),
			"known_effect": str(duty.get(
				"known_effect", duty.get("hint", "改变当前局势")
			)),
			"tradeoff": str(duty.get(
				"tradeoff",
				"结算后，补给、边境压力与其他人物仍按各自规则变化"
			)),
			"can_execute": bool(eligibility.get("can_execute", true)),
			"blocked_reason": str(eligibility.get("blocked_reason", "")),
			"requirements": eligibility.get("requirements", []),
			"base_values": eligibility.get("base_values", {}),
			"modified_values": eligibility.get("modified_values", {}),
			"modifier_explanations": eligibility.get(
				"modifier_explanations", []
			),
		})
	return rows


func execute_duty(duty_id: String, options: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return _failure("project_not_initialized")
	if has_pending_incident():
		return _failure("life_incident_pending")
	if get_day() > get_duration_days():
		return _failure("project_complete")
	var duty := _find_duty(duty_id)
	if duty.is_empty() or not _conditions_match(duty.get("available_if", [])):
		return _failure("duty_not_available")
	var eligibility := _duty_eligibility(duty)
	if not bool(eligibility.get("can_execute", false)):
		var blocked := _failure("duty_blocked")
		blocked["blocked_reason"] = str(
			eligibility.get("blocked_reason", "")
		)
		return blocked

	var day := get_day()
	var calendar_day_start := int(session.current_day)
	var calendar_days := get_calendar_days_per_step()
	var status_before := get_status()
	var tick_event := _day_tick_event(day, calendar_days)
	var tick_validation: Dictionary = TickEventSchemaModel.new().validate(
		tick_event
	)
	if not bool(tick_validation.get("ok", false)):
		var invalid_tick := _failure("invalid_day_tick_event")
		invalid_tick["validation_errors"] = (
			tick_validation.get("errors", []) as Array
		).duplicate(true)
		return invalid_tick
	var duty_result: Variant = _build_duty_transaction(
		duty, day, eligibility, options
	)
	if str(duty_result.contract_status) != "resolved":
		var invalid_effect := _failure("duty_effect_contract_invalid")
		invalid_effect["contract_error"] = str(duty_result.error_reason)
		return invalid_effect
	if not session.writer.apply_result(duty_result, session.stores):
		var failed_write := _failure("duty_transaction_rejected")
		failed_write["transaction_report"] = session.writer.last_report.duplicate(true)
		return failed_write
	_append_duty_log(duty, duty_result, day)
	duty_counts[duty_id] = int(duty_counts.get(duty_id, 0)) + 1

	var settlement_result: Variant = _settle_day(day, calendar_days)
	if str(settlement_result.contract_status) != "resolved":
		var invalid_settlement := _failure("day_settlement_contract_invalid")
		invalid_settlement["contract_error"] = str(
			settlement_result.error_reason
		)
		return invalid_settlement
	if not session.writer.apply_result(settlement_result, session.stores):
		var failed_settlement := _failure("day_settlement_rejected")
		failed_settlement["transaction_report"] = session.writer.last_report.duplicate(true)
		return failed_settlement
	_clamp_states()

	var tick_result: Dictionary = session.advance_world(
		tick_event, calendar_days * 24
	)
	if not bool(tick_result.get("success", false)):
		var failed_tick := _failure("day_tick_failed")
		failed_tick["tick_result"] = tick_result.duplicate(true)
		return failed_tick
	_clamp_states()

	var next_day := day + 1
	session.stores["state_store"].set_state(
		"player", "service_day", next_day
	)
	var status_after := get_status()
	var row := {
		"day": day,
		"progress_unit_label": get_progress_unit_label(),
		"calendar_day_start": calendar_day_start,
		"calendar_day_end": int(session.current_day),
		"duty_id": duty_id,
		"label": str(duty.get("label", duty_id)),
		"title": str(duty_result.narrative_result.get("title", "值勤结束")),
		"summary": str(duty_result.narrative_result.get("summary", "")),
		"risk_outcome": (
			duty_result.narrative_result.get("risk_outcome", {}) as Dictionary
		).duplicate(true),
		"settlement_notes": (
			settlement_result.narrative_result.get("notes", []) as Array
		).duplicate(true),
		"npc_decisions": (
			tick_result.get("observed_autonomous_decisions", []) as Array
		).duplicate(true),
		"npc_narratives": _observed_npc_narratives(tick_result),
		"status_before": status_before.duplicate(true),
		"status": status_after.duplicate(true),
		"duty_transaction": duty_result.to_dict(),
		"settlement_transaction": settlement_result.to_dict(),
		"tick_result": tick_result.duplicate(true),
	}
	day_history.append(row)
	var queued_incident := _try_queue_life_incident(duty, day, options)
	if is_complete():
		_store_completion_chronicle()
	latest_result = {
		"success": true,
		"day": day,
		"calendar_day_start": calendar_day_start,
		"calendar_day_end": int(session.current_day),
		"duty_id": duty_id,
		"title": row["title"],
		"summary": row["summary"],
		"risk_outcome": row["risk_outcome"],
		"settlement_notes": row["settlement_notes"],
		"npc_narratives": row["npc_narratives"],
		"status_before": row["status_before"],
		"status": row["status"],
		"duty_transaction": row["duty_transaction"],
		"settlement_transaction": row["settlement_transaction"],
		"tick_result": row["tick_result"],
		"complete": is_complete(),
		"completion": get_completion_summary(),
		"incident_pending": not queued_incident.is_empty(),
		"incident": queued_incident,
		"base_values": eligibility.get("base_values", {}),
		"modified_values": eligibility.get("modified_values", {}),
		"modifier_explanations": eligibility.get(
			"modifier_explanations", []
		),
	}
	return latest_result.duplicate(true)


func get_pending_incident() -> Dictionary:
	if not is_ready() or pending_incident.is_empty():
		return {"active": false}
	var incident := _find_life_incident(str(
		pending_incident.get("incident_id", "")
	))
	if incident.is_empty():
		return {"active": false, "error": "life_incident_definition_missing"}
	var responses: Array[Dictionary] = []
	for response_value: Variant in incident.get("responses", []):
		if not response_value is Dictionary:
			continue
		var response := response_value as Dictionary
		var eligibility := _incident_response_eligibility(response)
		responses.append({
			"response_id": str(response.get("response_id", "")),
			"label": str(response.get("label", "回应")),
			"hint": str(response.get("hint", "")),
			"can_execute": bool(eligibility.get("can_execute", true)),
			"blocked_reason": str(eligibility.get("blocked_reason", "")),
			"requirements": eligibility.get("requirements", []),
		})
	return {
		"active": true,
		"incident_id": str(incident.get("incident_id", "")),
		"title": str(incident.get("title", "路上发生了一件小事")),
		"body": str(incident.get("body", "")),
		"trigger_reason": str(incident.get("trigger_reason", "")),
		"story_role": str(incident.get("story_role", "incidental")),
		"responses": responses,
		"source_duty_id": str(pending_incident.get("source_duty_id", "")),
		"trigger_day": int(pending_incident.get("trigger_day", 0)),
		"trigger_world_day": int(pending_incident.get("trigger_world_day", 0)),
	}


func resolve_life_incident(response_id: String) -> Dictionary:
	if not is_ready():
		return _failure("project_not_initialized")
	if pending_incident.is_empty():
		return _failure("life_incident_not_pending")
	var incident_id := str(pending_incident.get("incident_id", ""))
	var incident := _find_life_incident(incident_id)
	if incident.is_empty():
		return _failure("life_incident_definition_missing")
	var response := _find_incident_response(incident, response_id)
	if response.is_empty():
		return _failure("life_incident_response_not_available")
	var eligibility := _incident_response_eligibility(response)
	if not bool(eligibility.get("can_execute", false)):
		var blocked := _failure("life_incident_response_blocked")
		blocked["blocked_reason"] = str(eligibility.get(
			"blocked_reason", "当前状态不能这样回应。"
		))
		return blocked
	var story_role := str(incident.get("story_role", "incidental"))
	var status_before := get_status()
	var effects: Dictionary = response.get("effects", {}).duplicate(true)
	if story_role == "incidental" and not _incidental_effects_are_bounded(effects):
		return _failure("incidental_effect_opens_storyline")
	var occurrence := int(incident_counts.get(incident_id, 0)) + 1
	var fact_id := "%s:incident:%s:%d" % [
		project_id, incident_id, occurrence
	]
	var result = TransactionResultModel.new()
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "life_incident_resolved",
		"actor_id": "player",
		"project_id": project_id,
		"incident_id": incident_id,
		"response_id": response_id,
		"story_role": story_role,
		"opens_storyline": false,
		"source_duty_id": str(pending_incident.get("source_duty_id", "")),
		"source_fact_ids": [str(pending_incident.get("source_fact_id", ""))],
		"day": int(pending_incident.get("trigger_day", get_day())),
		"location_id": str(session.context.location_id),
		"summary": str((effects.get("narrative", {}) as Dictionary).get(
			"summary", ""
		)),
	})
	var resolved_effects: Variant = _replace_effect_tokens(
		effects, {"$incident_fact_id": fact_id}
	)
	var effect_report: Dictionary = effect_protocol_resolver.append_effects(
		result, resolved_effects
	)
	if not bool(effect_report.get("ok", false)):
		var invalid := _failure("life_incident_effect_contract_invalid")
		invalid["contract_errors"] = effect_report.get("errors", [])
		return invalid
	if bool(incident.get("creates_memory", true)):
		result.add_memory({
			"memory_id": "%s:memory" % fact_id,
			"owner_id": "player",
			"memory_type": "life_incident",
			"project_id": project_id,
			"incident_id": incident_id,
			"response_id": response_id,
			"source_fact_ids": [fact_id],
			"emotional_tone": str(response.get("emotional_tone", "ordinary")),
			"clarity": "medium",
			"can_be_told_as_rumor": false,
		})
	var narrative: Dictionary = effects.get("narrative", {}).duplicate(true)
	result.set_narrative_result(narrative)
	result.mark_resolved("life_incident_response")
	if not session.writer.apply_result(result, session.stores):
		var failed := _failure("life_incident_transaction_rejected")
		failed["transaction_report"] = session.writer.last_report.duplicate(true)
		return failed
	_clamp_states()
	incident_counts[incident_id] = occurrence
	incident_history.append({
		"incident_id": incident_id,
		"response_id": response_id,
		"trigger_day": int(pending_incident.get("trigger_day", 0)),
		"trigger_world_day": int(pending_incident.get("trigger_world_day", 0)),
		"source_duty_id": str(pending_incident.get("source_duty_id", "")),
		"fact_id": fact_id,
	})
	session.world_log.append_entry({
		"entry_type": "life_incident_response",
		"project_id": project_id,
		"incident_id": incident_id,
		"response_id": response_id,
		"story_role": story_role,
		"contract_status": "resolved",
		"facts_added": ["life_incident_resolved"],
		"state_change_count": result.state_changes.size(),
		"relationship_change_count": result.relationship_changes.size(),
		"memory_count": result.memories_added.size(),
	})
	pending_incident = {}
	if is_complete():
		_store_completion_chronicle()
	latest_result = {
		"success": true,
		"incident_resolved": true,
		"incident_id": incident_id,
		"response_id": response_id,
		"title": str(narrative.get("title", "这件小事过去了")),
		"summary": str(narrative.get("summary", "")),
		"settlement_notes": (
			response.get("outcome_notes", []) as Array
		).duplicate(true),
		"npc_narratives": [],
		"status_before": status_before.duplicate(true),
		"status": get_status(),
		"incident_transaction": result.to_dict(),
		"complete": is_complete(),
		"completion": get_completion_summary(),
		"base_values": {},
		"modified_values": {},
		"modifier_explanations": [],
	}
	return latest_result.duplicate(true)


func get_status() -> Dictionary:
	var rows: Array[Dictionary] = []
	if not is_ready():
		return {"rows": rows}
	var scope_id := str(definition.get("scope_entity_id", ""))
	var store: Variant = session.stores["state_store"]
	for axis_value: Variant in definition.get("status_axes", []):
		if not (axis_value is Dictionary):
			continue
		var axis := axis_value as Dictionary
		var value := int(store.get_state(scope_id, str(axis.get("key", "")), 0))
		var warning := false
		if axis.has("warning_below"):
			warning = value < int(axis.get("warning_below", 0))
		if axis.has("warning_above"):
			warning = warning or value > int(axis.get("warning_above", 0))
		rows.append({
			"key": str(axis.get("key", "")),
			"label": str(axis.get("label", "状态")),
			"value": value,
			"warning": warning,
		})
	return {
		"rows": rows,
		"fatigue": int(store.get_state("player", "fatigue", 0)),
		"training": int(store.get_state("player", "training", 0)),
	}


func get_completion_summary() -> Dictionary:
	if not is_complete():
		return {"active": false}
	var completion: Dictionary = definition.get("completion", {})
	var lines: Array[String] = []
	for outcome_value: Variant in completion.get("outcomes", []):
		if not (outcome_value is Dictionary):
			continue
		var outcome := outcome_value as Dictionary
		if _conditions_match(outcome.get("conditions", [])):
			lines.append(str(outcome.get("text", "")))
	var relationship_lines := _completion_relationship_lines()
	lines.append_array(relationship_lines)
	return {
		"active": true,
		"title": str(completion.get("title", "阶段小结")),
		"intro": str(completion.get("intro", "")),
		"lines": lines,
		"duty_counts": duty_counts.duplicate(true),
		"status": get_status(),
		"growth_candidates": get_growth_candidates(),
		"milestone": get_milestone_summary(),
	}


func get_milestone_summary() -> Dictionary:
	if not is_complete():
		return {"active": false}
	var milestone: Dictionary = definition.get("milestone", {})
	if milestone.is_empty():
		return {"active": false}
	var outcomes := _eligible_milestone_outcomes()
	return {
		"active": true,
		"resolved": not _milestone_resolution_fact().is_empty(),
		"title": str(milestone.get("title", "阶段节点")),
		"intro": str(milestone.get("intro", "")),
		"action_label": str(milestone.get("action_label", "完成阶段结算")),
		"resolved_title": str(milestone.get(
			"resolved_title", "阶段变化已经写入世界"
		)),
		"outcomes": outcomes,
	}


func resolve_milestone() -> Dictionary:
	if not is_ready():
		return _failure("project_not_initialized")
	if not is_complete():
		return _failure("project_not_complete")
	var milestone: Dictionary = definition.get("milestone", {})
	if milestone.is_empty():
		return _failure("project_milestone_missing")
	if not _milestone_resolution_fact().is_empty():
		return _failure("project_milestone_already_resolved")
	var outcomes := _eligible_milestone_outcomes()
	if outcomes.is_empty():
		return _failure("project_milestone_has_no_outcomes")
	var outcome_ids: Array = []
	var source_fact_ids: Array = []
	for outcome: Dictionary in outcomes:
		outcome_ids.append(str(outcome.get("outcome_id", "")))
		for source_id: Variant in outcome.get("source_fact_ids", []):
			if source_id not in source_fact_ids:
				source_fact_ids.append(source_id)
	var fact_id := "%s:milestone_resolved" % project_id
	var result = TransactionResultModel.new()
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "life_project_milestone_resolved",
		"actor_id": "player",
		"project_id": project_id,
		"outcome_ids": outcome_ids,
		"source_fact_ids": source_fact_ids,
		"day": get_day(),
		"location_id": str(session.context.location_id),
	})
	for outcome: Dictionary in outcomes:
		var rule := _find_milestone_rule(str(outcome.get("outcome_id", "")))
		var effects: Variant = _replace_effect_tokens(
			rule.get("effects", {}), {"$milestone_fact_id": fact_id}
		)
		var effect_report: Dictionary = effect_protocol_resolver.append_effects(
			result, effects
		)
		if not bool(effect_report.get("ok", false)):
			var invalid := _failure("project_milestone_effect_invalid")
			invalid["contract_errors"] = effect_report.get("errors", [])
			return invalid
	var lines: Array[String] = []
	for outcome: Dictionary in outcomes:
		lines.append(str(outcome.get("text", "")))
	result.add_chronicle_entry({
		"entry_id": "%s:milestone" % project_id,
		"subject_id": "player",
		"title": str(milestone.get("chronicle_title", milestone.get(
			"title", "阶段节点"
		))),
		"body": "%s\n\n%s" % [
			str(milestone.get("intro", "")), "\n".join(lines)
		],
		"project_id": project_id,
		"outcome_ids": outcome_ids,
		"source_fact_ids": [fact_id],
	})
	result.set_narrative_result({
		"title": str(milestone.get(
			"resolved_title", "阶段变化已经写入世界"
		)),
		"summary": "\n".join(lines),
	})
	result.mark_resolved("life_project_milestone")
	if not session.writer.apply_result(result, session.stores):
		var failed := _failure("project_milestone_transaction_rejected")
		failed["transaction_report"] = session.writer.last_report.duplicate(true)
		return failed
	_clamp_states()
	session.world_log.append_entry({
		"entry_type": "life_project_milestone",
		"project_id": project_id,
		"outcome_ids": outcome_ids,
		"transaction_mode": "life_project_milestone",
		"contract_status": "resolved",
		"facts_added": ["life_project_milestone_resolved"],
	})
	latest_result = {
		"success": true,
		"milestone_resolved": true,
		"title": str(result.narrative_result.get("title", "阶段变化已经写入世界")),
		"summary": str(result.narrative_result.get("summary", "")),
		"outcomes": outcomes,
		"settlement_notes": [],
		"npc_narratives": [],
	}
	return latest_result.duplicate(true)


func get_growth_candidates() -> Array:
	var rows: Array[Dictionary] = []
	if not is_ready():
		return rows
	var confirmed_candidate_id := _confirmed_growth_candidate_id()
	for rule_value: Variant in definition.get("growth_candidate_rules", []):
		if not rule_value is Dictionary:
			continue
		var rule := rule_value as Dictionary
		if bool(rule.get("requires_completion", true)) and not is_complete():
			continue
		var source_fact_ids := _matching_growth_fact_ids(
			rule.get("fact_match", {})
		)
		var minimum_count := maxi(int(rule.get("minimum_fact_count", 1)), 1)
		if source_fact_ids.size() < minimum_count:
			continue
		rows.append({
			"candidate_id": str(rule.get("candidate_id", "")),
			"title": str(rule.get("title", "阶段成长")),
			"description": str(rule.get("description", "")),
			"evidence_label": str(rule.get("evidence_label", "经历事实")),
			"evidence_count": source_fact_ids.size(),
			"minimum_fact_count": minimum_count,
			"source_fact_ids": source_fact_ids,
			"reward_preview": (
				rule.get("reward_preview", {}) as Dictionary
			).duplicate(true),
			"confirmed": str(rule.get("candidate_id", "")) == confirmed_candidate_id,
		})
	return rows


func confirm_growth_candidate(candidate_id: String) -> Dictionary:
	if not is_ready():
		return _failure("project_not_initialized")
	if not is_complete():
		return _failure("project_not_complete")
	if _confirmed_growth_candidate_id() != "":
		return _failure("growth_already_confirmed")
	var candidate := _growth_candidate(candidate_id)
	if candidate.is_empty():
		return _failure("growth_candidate_not_available")
	var rule := _find_growth_rule(candidate_id)
	var reward: Dictionary = rule.get("reward", {})
	if reward.is_empty():
		return _failure("growth_reward_missing")
	var fact_id := "%s:growth_confirmed:%s" % [project_id, candidate_id]
	var growth_fact := {
		"fact_id": fact_id,
		"fact_type": "life_project_growth_confirmed",
		"actor_id": "player",
		"project_id": project_id,
		"candidate_id": candidate_id,
		"source_fact_ids": (
			candidate.get("source_fact_ids", []) as Array
		).duplicate(true),
		"day": get_day(),
		"location_id": str(session.context.location_id),
	}
	var derivation_report := _validate_growth_feature_derivations(
		growth_fact,
		reward.get("required_feature_derivations", {})
	)
	if not bool(derivation_report.get("ok", false)):
		return _growth_contract_failure(
			"growth_feature_derivation_invalid", derivation_report
		)
	var result = TransactionResultModel.new()
	result.add_fact(growth_fact)
	var reward_effects: Variant = _replace_effect_tokens(
		reward.get("effects", {}),
		{
			"$growth_fact_id": fact_id,
			"$growth_tick": int(
				session.current_day * 24 + session.current_hour
			),
		}
	)
	var effect_report: Dictionary = effect_protocol_resolver.append_effects(
		result, reward_effects
	)
	if not bool(effect_report.get("ok", false)):
		return _growth_contract_failure(
			"growth_reward_effect_invalid", effect_report
		)
	for grant_value: Variant in reward.get("talent_grants", []):
		if not grant_value is Dictionary:
			return _failure("growth_talent_grant_invalid")
		var grant := grant_value as Dictionary
		var owner_id := str(grant.get("owner_entity_id", "player"))
		var talent_def_id := str(grant.get("talent_def_id", ""))
		if talent_def_id == "" or not session.registry.has_definition(
			"talent", talent_def_id
		):
			return _failure("growth_talent_definition_missing")
		result.add_character_feature_change({
			"operation": "grant_talent",
			"assignment": {
				"talent_assignment_id": "%s:talent:%s:%s" % [
					project_id,
					candidate_id,
					talent_def_id,
				],
				"talent_def_id": talent_def_id,
				"owner_entity_id": owner_id,
				"source_kind": "system_grant",
				"source_fact_ids": [fact_id],
				"status": "active",
				"assigned_tick": int(session.current_day * 24 + session.current_hour),
			},
		})
	result.add_chronicle_entry({
		"entry_id": "%s:growth:%s" % [project_id, candidate_id],
		"subject_id": "player",
		"title": "阶段成长：%s" % str(candidate.get("title", "阶段成长")),
		"body": "%s\n\n依据：%s，共 %d 次。" % [
			str(candidate.get("description", "")),
			str(candidate.get("evidence_label", "经历事实")),
			int(candidate.get("evidence_count", 0)),
		],
		"project_id": project_id,
		"candidate_id": candidate_id,
		"source_fact_ids": [fact_id],
	})
	result.set_narrative_result({
		"title": "成长已经留下",
		"summary": "%s。%s" % [
			str(candidate.get("title", "阶段成长")),
			str((candidate.get("reward_preview", {}) as Dictionary).get(
				"summary", "奖励已经写入角色。"
			)),
		],
	})
	result.mark_resolved("life_project_growth_confirmation")
	if not session.writer.apply_result(result, session.stores):
		var failed := _failure("growth_transaction_rejected")
		failed["transaction_report"] = session.writer.last_report.duplicate(true)
		return failed
	session.world_log.append_entry({
		"entry_type": "life_project_growth_confirmation",
		"project_id": project_id,
		"candidate_id": candidate_id,
		"transaction_mode": "life_project_growth_confirmation",
		"contract_status": "resolved",
		"facts_added": ["life_project_growth_confirmed"],
	})
	latest_result = {
		"success": true,
		"growth_confirmed": true,
		"candidate_id": candidate_id,
		"title": str(result.narrative_result.get("title", "成长已经留下")),
		"summary": str(result.narrative_result.get("summary", "")),
		"settlement_notes": ["成长事实、属性、天赋和纪事已在同一事务中写入。"],
		"npc_narratives": [],
		"base_values": {},
		"modified_values": {},
		"modifier_explanations": [],
	}
	return latest_result.duplicate(true)


func _validate_growth_feature_derivations(
		growth_fact: Dictionary,
		required_value: Variant
) -> Dictionary:
	if not required_value is Dictionary:
		return {
			"ok": false,
			"errors": ["required_feature_derivations_not_dictionary"],
		}
	var required := required_value as Dictionary
	var store: Variant = session.stores.get("character_feature_store")
	if store == null or not store.has_method("describe_fact_derivations"):
		return {"ok": false, "errors": ["feature_derivation_store_missing"]}
	var actual: Dictionary = store.describe_fact_derivations(growth_fact)
	var errors: Array[String] = []
	for key: String in ["trait_def_ids", "mark_def_ids", "skill_def_ids"]:
		var expected_value: Variant = required.get(key, [])
		if not expected_value is Array:
			errors.append("feature_derivation_not_array:%s" % key)
			continue
		for definition_id: Variant in expected_value:
			if str(definition_id) not in (actual.get(key, []) as Array):
				errors.append(
					"feature_derivation_missing:%s:%s" % [key, definition_id]
				)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"actual": actual,
	}


func _growth_candidate(candidate_id: String) -> Dictionary:
	for candidate: Dictionary in get_growth_candidates():
		if str(candidate.get("candidate_id", "")) == candidate_id:
			return candidate
	return {}


func _find_growth_rule(candidate_id: String) -> Dictionary:
	for value: Variant in definition.get("growth_candidate_rules", []):
		if value is Dictionary and str(
			(value as Dictionary).get("candidate_id", "")
		) == candidate_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _confirmed_growth_candidate_id() -> String:
	if not is_ready():
		return ""
	for fact: Dictionary in session.stores["fact_store"].find_facts_by_type(
		"life_project_growth_confirmed"
	):
		if str(fact.get("project_id", "")) == project_id:
			return str(fact.get("candidate_id", ""))
	return ""


func _growth_contract_failure(error: String, report: Dictionary) -> Dictionary:
	var failure := _failure(error)
	failure["contract_errors"] = report.get("errors", [])
	return failure


func _matching_growth_fact_ids(match_rule: Variant) -> Array:
	return _matching_fact_ids(match_rule)


func _matching_fact_ids(match_rule: Variant) -> Array:
	var rows: Array = []
	if not match_rule is Dictionary:
		return rows
	var matcher := match_rule as Dictionary
	var duty_ids: Array = matcher.get("duty_ids", [])
	var project_ids: Array = matcher.get("project_ids", [project_id])
	if project_ids.is_empty():
		project_ids = [project_id]
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		if str(fact.get("project_id", "")) not in project_ids:
			continue
		var fact_type := str(matcher.get("fact_type", ""))
		if fact_type != "" and str(fact.get("fact_type", "")) != fact_type:
			continue
		if not duty_ids.is_empty() and str(fact.get("duty_id", "")) not in duty_ids:
			continue
		rows.append(str(fact.get("fact_id", "")))
	return rows


func _eligible_milestone_outcomes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var milestone: Dictionary = definition.get("milestone", {})
	for value: Variant in milestone.get("rules", []):
		if not value is Dictionary:
			continue
		var rule := value as Dictionary
		if not _conditions_match(rule.get("conditions", [])):
			continue
		var source_fact_ids := _matching_fact_ids(rule.get("fact_match", {}))
		var minimum_count := maxi(int(rule.get("minimum_fact_count", 1)), 1)
		if source_fact_ids.size() < minimum_count:
			continue
		rows.append({
			"outcome_id": str(rule.get("outcome_id", "")),
			"title": str(rule.get("title", "年度变化")),
			"text": str(rule.get("text", "")),
			"evidence_label": str(rule.get("evidence_label", "累积经历")),
			"evidence_count": source_fact_ids.size(),
			"minimum_fact_count": minimum_count,
			"source_fact_ids": source_fact_ids,
		})
	return rows


func _find_milestone_rule(outcome_id: String) -> Dictionary:
	var milestone: Dictionary = definition.get("milestone", {})
	for value: Variant in milestone.get("rules", []):
		if value is Dictionary and str(
			(value as Dictionary).get("outcome_id", "")
		) == outcome_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _milestone_resolution_fact() -> Dictionary:
	if not is_ready():
		return {}
	for fact: Dictionary in session.stores[
		"fact_store"
	].find_facts_by_type("life_project_milestone_resolved"):
		if str(fact.get("project_id", "")) == project_id:
			return fact.duplicate(true)
	return {}


func _build_duty_transaction(
		duty: Dictionary,
		day: int,
		eligibility: Dictionary = {},
		options: Dictionary = {}
) -> Variant:
	var result = TransactionResultModel.new()
	var duty_id := str(duty.get("duty_id", ""))
	var duty_fact_id := "%s:duty:%d:%s" % [project_id, day, duty_id]
	result.add_fact({
		"fact_id": duty_fact_id,
		"fact_type": "life_project_duty_completed",
		"actor_id": "player",
		"project_id": project_id,
		"duty_id": duty_id,
		"day": day,
		"location_id": str(session.context.location_id),
		"summary": str((duty.get("effects", {}) as Dictionary).get(
			"narrative", {}
		).get("summary", "")),
	})
	var progress_fact_id := ""
	var progress_fact: Dictionary = duty.get("progress_fact", {})
	if not progress_fact.is_empty():
		progress_fact_id = "%s:progress:%d:%s" % [project_id, day, duty_id]
		var normalized_progress_fact := progress_fact.duplicate(true)
		normalized_progress_fact["fact_id"] = progress_fact_id
		if str(normalized_progress_fact.get("actor_id", "")) == "":
			normalized_progress_fact["actor_id"] = "player"
		normalized_progress_fact["project_id"] = project_id
		normalized_progress_fact["duty_id"] = duty_id
		normalized_progress_fact["day"] = day
		normalized_progress_fact["location_id"] = str(
			session.context.location_id
		)
		result.add_fact(normalized_progress_fact)
	var effects: Dictionary = _replace_effect_tokens(
		duty.get("effects", {}),
		{
			"$duty_fact_id": duty_fact_id,
			"$progress_fact_id": progress_fact_id,
		}
	)
	var effect_report: Dictionary = effect_protocol_resolver.append_effects(
		result, effects
	)
	if not bool(effect_report.get("ok", false)):
		result.mark_invalid_contract(
			"life_project_duty",
			",".join(effect_report.get("errors", []))
		)
		return result
	result.add_memory({
		"memory_id": "%s:duty_memory:%d:%s" % [project_id, day, duty_id],
		"owner_id": "player",
		"memory_type": "service_duty",
		"project_id": project_id,
		"duty_id": duty_id,
		"day": day,
		"emotional_tone": "enduring",
		"clarity": "high",
		"can_be_told_as_rumor": false,
	})
	var narrative := (
		effects.get("narrative", {}) as Dictionary
	).duplicate(true)
	var risk_report := _append_risk_outcome(
		result, duty, day, eligibility, options
	)
	if not bool(risk_report.get("ok", true)):
		result.mark_invalid_contract(
			"life_project_duty",
			str(risk_report.get("error", "risk_outcome_invalid"))
		)
		return result
	var risk_outcome: Dictionary = risk_report.get("outcome", {})
	if not risk_outcome.is_empty():
		narrative["risk_outcome"] = risk_outcome
		var consequence := str(risk_outcome.get("consequence", ""))
		if consequence != "":
			narrative["summary"] = "%s\n%s" % [
				str(narrative.get("summary", "")), consequence
			]
	result.set_narrative_result(narrative)
	result.mark_resolved("life_project_duty")
	return result


func _append_risk_outcome(
		result: Variant,
		duty: Dictionary,
		day: int,
		eligibility: Dictionary,
		options: Dictionary
) -> Dictionary:
	var config: Dictionary = duty.get("risk_resolution", {})
	if config.is_empty():
		return {"ok": true, "outcome": {}}
	var risk := maxi(int((eligibility.get(
		"modified_values", {}
	) as Dictionary).get("action.risk", 0)), 0)
	var die_sides := maxi(int(config.get("die_sides", 10)), 1)
	var roll := int(options.get("risk_roll_override", 0))
	if roll < 1:
		roll = session.challenge_rng.randi_range(1, die_sides)
	roll = clampi(roll, 1, die_sides)
	var margin := roll - risk
	var selected: Dictionary = {}
	var selected_threshold := -1000000
	for tier_value: Variant in config.get("tiers", []):
		if not tier_value is Dictionary:
			continue
		var tier := tier_value as Dictionary
		var threshold := int(tier.get("minimum_margin", -1000000))
		if margin >= threshold and threshold >= selected_threshold:
			selected = tier
			selected_threshold = threshold
	if selected.is_empty():
		return {"ok": false, "error": "risk_outcome_tier_missing"}
	var fact_id := "%s:risk:%d:%s" % [
		project_id, day, str(duty.get("duty_id", ""))
	]
	result.add_fact({
		"fact_id": fact_id,
		"fact_type": "life_project_risk_resolved",
		"actor_id": "player",
		"project_id": project_id,
		"duty_id": str(duty.get("duty_id", "")),
		"day": day,
		"location_id": str(session.context.location_id),
		"risk": risk,
		"roll": roll,
		"margin": margin,
		"outcome_tier": str(selected.get("tier_id", "")),
	})
	var risk_effects: Variant = _replace_effect_tokens(
		selected.get("effects", {}), {"$risk_fact_id": fact_id}
	)
	var effect_report: Dictionary = effect_protocol_resolver.append_effects(
		result, risk_effects
	)
	if not bool(effect_report.get("ok", false)):
		return {
			"ok": false,
			"error": ",".join(effect_report.get("errors", [])),
		}
	return {
		"ok": true,
		"outcome": {
			"tier_id": str(selected.get("tier_id", "")),
			"title": str(selected.get("title", "风险结算")),
			"consequence": str(selected.get("consequence", "")),
			"risk": risk,
			"roll": roll,
			"margin": margin,
			"source_fact_id": fact_id,
		},
	}


func _replace_effect_tokens(value: Variant, replacements: Dictionary) -> Variant:
	if value is Dictionary:
		var row: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			row[key] = _replace_effect_tokens(
				(value as Dictionary).get(key), replacements
			)
		return row
	if value is Array:
		var rows: Array = []
		for entry: Variant in value:
			rows.append(_replace_effect_tokens(entry, replacements))
		return rows
	if value is String and replacements.has(value):
		return replacements.get(value)
	return value


func _settle_day(day: int, calendar_days: int = 1) -> Variant:
	var result = TransactionResultModel.new()
	var model: Dictionary = definition.get(
		"step_settlement", definition.get("daily_settlement", {})
	)
	var base_effects: Variant = model.get(
		"base_effects",
		{"state_changes": model.get("base_state_changes", [])}
	)
	var base_report: Dictionary = effect_protocol_resolver.append_effects(
		result, base_effects
	)
	if not bool(base_report.get("ok", false)):
		result.mark_invalid_contract(
			"life_project_day_settlement",
			",".join(base_report.get("errors", []))
		)
		return result
	var notes: Array[String] = []
	for effect_value: Variant in model.get("conditional_effects", []):
		if not (effect_value is Dictionary):
			continue
		var effect := effect_value as Dictionary
		if not _conditions_match_after_changes(
			effect.get("requirements", effect.get("conditions", [])),
			result.state_changes
		):
			continue
		var effect_report: Dictionary = effect_protocol_resolver.append_effects(
			result,
			effect.get("operations", effect)
		)
		if not bool(effect_report.get("ok", false)):
			result.mark_invalid_contract(
				"life_project_day_settlement",
				",".join(effect_report.get("errors", []))
			)
			return result
		var note := str(effect.get("narrative", ""))
		if note != "":
			notes.append(note)
	result.add_fact({
		"fact_id": "%s:day_settled:%d" % [project_id, day],
		"fact_type": "life_project_day_settled",
		"actor_id": "player",
		"project_id": project_id,
		"day": day,
		"calendar_days": calendar_days,
		"world_day_start": int(session.current_day),
		"world_day_end": int(session.current_day + calendar_days),
		"location_id": str(session.context.location_id),
	})
	result.set_narrative_result({
		"title": "第 %d %s过去" % [day, get_progress_unit_label()],
		"summary": str(model.get(
			"summary", "值勤、消耗和风雪都已经结算。"
		)),
		"notes": notes,
	})
	result.mark_resolved("life_project_day_settlement")
	return result


func _conditions_match_after_changes(
		conditions: Array,
		pending_changes: Array
) -> bool:
	var snapshot: Variant = session.get_snapshot()
	var data: Dictionary = snapshot.to_dict()
	var states: Dictionary = data.get("states", {})
	var player: Dictionary = data.get("player", {})
	for change: Dictionary in pending_changes:
		var entity_id := str(change.get("entity_id", ""))
		var key := str(change.get("key", ""))
		var entity_states: Dictionary = (
			states.get(entity_id, {}) as Dictionary
		).duplicate(true)
		var current: Variant = entity_states.get(key, 0)
		if change.has("to"):
			entity_states[key] = change.get("to")
		elif change.has("delta"):
			entity_states[key] = float(current) + float(change.get("delta", 0))
		states[entity_id] = entity_states
		if entity_id == "player":
			player[key] = entity_states[key]
	data["states"] = states
	data["player"] = player
	return _requirements_match(conditions, SimSnapshotModel.new(data))


func _duty_eligibility(duty: Dictionary) -> Dictionary:
	var snapshot: Variant = session.get_snapshot()
	var contract := duty.duplicate(true)
	var requirements: Array = action_contract_resolver.adapt_legacy_state_requirements(
		duty.get("requirements", [])
	)
	requirements.append_array(action_contract_resolver.adapt_player_min(
		duty.get("player_min", {}), duty.get("player_min_labels", {})
	))
	contract["requirements"] = requirements
	return action_contract_resolver.evaluate(snapshot, contract, "player")


func _conditions_match(conditions: Array) -> bool:
	if not is_ready():
		return false
	return _requirements_match(conditions, session.get_snapshot())


func _try_queue_life_incident(
		duty: Dictionary,
		day: int,
		options: Dictionary
) -> Dictionary:
	var config: Dictionary = definition.get("life_incident_system", {})
	if config.is_empty() or pending_incident.size() > 0:
		return {}
	if incident_history.size() >= int(config.get("maximum_per_project", 3)):
		return {}
	var minimum_gap := maxi(int(config.get("minimum_steps_between", 2)), 1)
	if not incident_history.is_empty():
		var previous: Dictionary = incident_history.back()
		if day - int(previous.get("trigger_day", -minimum_gap)) < minimum_gap:
			return {}
	var candidates := _eligible_life_incidents(duty)
	if candidates.is_empty():
		return {}
	var override_id := str(options.get("incident_id_override", ""))
	var selected: Dictionary = {}
	if override_id != "":
		for candidate: Dictionary in candidates:
			if str(candidate.get("incident_id", "")) == override_id:
				selected = candidate
				break
		if selected.is_empty():
			return {}
	else:
		var chance := clampi(
			int(config.get("trigger_chance_percent", 50)), 0, 100
		)
		var roll := int(options.get("incident_roll_override", 0))
		if roll < 1:
			roll = session.challenge_rng.randi_range(1, 100)
		if clampi(roll, 1, 100) > chance:
			return {}
		selected = _weighted_life_incident(candidates)
	if selected.is_empty():
		return {}
	pending_incident = {
		"incident_id": str(selected.get("incident_id", "")),
		"source_duty_id": str(duty.get("duty_id", "")),
		"source_fact_id": "%s:duty:%d:%s" % [
			project_id, day, str(duty.get("duty_id", ""))
		],
		"trigger_day": day,
		"trigger_world_day": int(session.current_day),
	}
	return get_pending_incident()


func _eligible_life_incidents(duty: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for value: Variant in definition.get("life_incidents", []):
		if not value is Dictionary:
			continue
		var incident := value as Dictionary
		var incident_id := str(incident.get("incident_id", ""))
		var source_conditions: Array = incident.get("source_conditions", [])
		# Incidents must expose a concrete state cause; an unconditional card is invalid.
		if incident_id == "" or source_conditions.is_empty():
			continue
		if not _conditions_match(source_conditions):
			continue
		if not _incident_matches_duty(incident, duty):
			continue
		if int(incident_counts.get(incident_id, 0)) >= maxi(
			int(incident.get("maximum_occurrences", 1)), 1
		):
			continue
		rows.append(incident.duplicate(true))
	return rows


func _incident_matches_duty(incident: Dictionary, duty: Dictionary) -> bool:
	var duty_ids: Array = incident.get("source_duty_ids", [])
	if not duty_ids.is_empty() and str(duty.get("duty_id", "")) not in duty_ids:
		return false
	var required_tags: Array = incident.get("source_action_tags_any", [])
	if required_tags.is_empty():
		return true
	var duty_tags: Array = duty.get("action_tags", [])
	for tag: Variant in required_tags:
		if tag in duty_tags:
			return true
	return false


func _weighted_life_incident(candidates: Array[Dictionary]) -> Dictionary:
	var total_weight := 0
	for candidate: Dictionary in candidates:
		total_weight += maxi(int(candidate.get("weight", 1)), 1)
	if total_weight <= 0:
		return {}
	var roll: int = int(session.challenge_rng.randi_range(1, total_weight))
	var cursor := 0
	for candidate: Dictionary in candidates:
		cursor += maxi(int(candidate.get("weight", 1)), 1)
		if roll <= cursor:
			return candidate.duplicate(true)
	return candidates.back().duplicate(true)


func _find_life_incident(incident_id: String) -> Dictionary:
	for value: Variant in definition.get("life_incidents", []):
		if value is Dictionary and str(
			(value as Dictionary).get("incident_id", "")
		) == incident_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _find_incident_response(
		incident: Dictionary, response_id: String
) -> Dictionary:
	for value: Variant in incident.get("responses", []):
		if value is Dictionary and str(
			(value as Dictionary).get("response_id", "")
		) == response_id:
			return (value as Dictionary).duplicate(true)
	return {}


func _incident_response_eligibility(response: Dictionary) -> Dictionary:
	var contract := response.duplicate(true)
	contract["requirements"] = (
		action_contract_resolver.adapt_legacy_state_requirements(
			response.get("requirements", [])
		)
	)
	return action_contract_resolver.evaluate(
		session.get_snapshot(), contract, "player"
	)


func _incidental_effects_are_bounded(effects: Dictionary) -> bool:
	for forbidden_key: String in [
		"facts", "facts_added", "traces", "rumors", "exchanges",
		"obligations", "deferred_consequences", "chronicle_entries",
		"memories", "memories_added", "pressure_changes",
	]:
		var forbidden_value: Variant = effects.get(forbidden_key, [])
		if forbidden_value is Array and not forbidden_value.is_empty():
			return false
		if forbidden_value is Dictionary and not forbidden_value.is_empty():
			return false
	var allowed_operations := [
		"state_set", "state_add", "state_degrade", "relationship_add",
		"item_consume", "item_condition", "item_history",
	]
	for value: Variant in effects.get("operations", []):
		if not value is Dictionary:
			return false
		if str((value as Dictionary).get("operation", "")) not in allowed_operations:
			return false
	return true


func _requirements_match(conditions: Array, snapshot: Variant) -> bool:
	var requirements: Array = action_contract_resolver.adapt_legacy_conditions(
		conditions
	)
	return bool(action_contract_resolver.evaluate_requirements(
		snapshot, requirements, "player"
	).get("can_execute", true))


func _life_project_save_data() -> Dictionary:
	return {
		"project_id": project_id,
		"project_path": project_source_path,
		"fixture_path": fixture_source_path,
		"rule_paths": rule_source_paths.duplicate(true),
		"current_day": get_day(),
		"status": "complete" if is_complete() else "active",
		"day_history": day_history.duplicate(true),
		"duty_counts": duty_counts.duplicate(true),
		"latest_result": latest_result.duplicate(true),
		"entry_transition": entry_transition.duplicate(true),
		"pending_incident": pending_incident.duplicate(true),
		"incident_history": incident_history.duplicate(true),
		"incident_counts": incident_counts.duplicate(true),
	}


func _restore_life_project(session_result: Dictionary) -> Dictionary:
	var runtime: Dictionary = session_result.get("life_project_runtime", {})
	var project_path := str(runtime.get("project_path", ""))
	if project_path == "":
		reset()
		return _failure("save_life_project_path_missing")
	var loader = SimRegistryModel.new()
	definition = loader.load_json(project_path)
	if definition.is_empty():
		reset()
		return _failure("save_life_project_not_loaded")
	project_id = str(definition.get("project_id", ""))
	if project_id == "" or project_id != str(runtime.get("project_id", "")):
		reset()
		return _failure("save_life_project_id_mismatch")
	var history_value: Variant = runtime.get("day_history", [])
	var duty_value: Variant = runtime.get("duty_counts", {})
	var latest_value: Variant = runtime.get("latest_result", {})
	var entry_transition_value: Variant = runtime.get("entry_transition", {})
	var pending_incident_value: Variant = runtime.get("pending_incident", {})
	var incident_history_value: Variant = runtime.get("incident_history", [])
	var incident_counts_value: Variant = runtime.get("incident_counts", {})
	if (
		not history_value is Array
		or not duty_value is Dictionary
		or not latest_value is Dictionary
		or not entry_transition_value is Dictionary
		or not pending_incident_value is Dictionary
		or not incident_history_value is Array
		or not incident_counts_value is Dictionary
	):
		reset()
		return _failure("save_life_project_runtime_invalid")
	project_source_path = project_path
	fixture_source_path = str(runtime.get("fixture_path", ""))
	rule_source_paths = (
		runtime.get("rule_paths", []) as Array
	).duplicate(true)
	day_history.assign((history_value as Array).duplicate(true))
	duty_counts = (duty_value as Dictionary).duplicate(true)
	latest_result = (latest_value as Dictionary).duplicate(true)
	entry_transition = (
		entry_transition_value as Dictionary
	).duplicate(true)
	pending_incident = (pending_incident_value as Dictionary).duplicate(true)
	incident_history.assign((incident_history_value as Array).duplicate(true))
	incident_counts = (incident_counts_value as Dictionary).duplicate(true)
	action_contract_resolver.configure(session.registry)
	initialized = true
	if (
		not pending_incident.is_empty()
		and _find_life_incident(str(pending_incident.get(
			"incident_id", ""
		))).is_empty()
	):
		reset()
		return _failure("save_life_incident_definition_missing")
	if int(runtime.get("current_day", 0)) != get_day():
		reset()
		return _failure("save_life_project_day_mismatch")
	return {
		"success": true,
		"ok": true,
		"error": "",
		"phase": "life_project_restored",
		"project_id": project_id,
		"source_kind": str(session_result.get("source_kind", "")),
		"day": get_day(),
		"duration_days": get_duration_days(),
		"candidate_count": get_duty_options().size(),
		"migrations": session_result.get("migrations", []),
	}


func _find_duty(duty_id: String) -> Dictionary:
	for duty_value: Variant in definition.get("duties", []):
		if duty_value is Dictionary and str(
			(duty_value as Dictionary).get("duty_id", "")
		) == duty_id:
			return (duty_value as Dictionary).duplicate(true)
	return {}


func _day_tick_event(day: int, calendar_days: int) -> Dictionary:
	var elapsed_hours := calendar_days * 24
	var projected_day := int(
		session.current_day + (session.current_hour + elapsed_hours) / 24
	)
	return {
		"tick_event_id": "%s_day_%d" % [project_id, day],
		"tick_type": "life_project_day",
		"trigger_key": "life_project_day_end",
		"scope_type": "location",
		"scope_id": str(session.context.location_id),
		"day": projected_day,
		"time_key": "next_roll_call",
		"source": "LifeProjectController",
		"label": str(definition.get("tick_label", "第七哨站值勤结算")),
		"elapsed_hours": 0,
		"include_due_checks": true,
		"due_kinds": ["obligation", "exchange"],
	}


func _replace_ritual_tokens(text: String, step: int) -> String:
	return text.replace("{day}", str(step)).replace(
		"{step}", str(step)
	).replace("{world_day}", str(session.current_day))


func _clamp_states() -> void:
	if not is_ready():
		return
	var store: Variant = session.stores["state_store"]
	var bounds: Dictionary = definition.get("state_bounds", {})
	for entity_id: String in bounds.keys():
		var entity_bounds: Dictionary = bounds[entity_id]
		for key: String in entity_bounds.keys():
			var range_values: Array = entity_bounds[key]
			if range_values.size() < 2:
				continue
			store.set_state(entity_id, key, clampi(
				int(store.get_state(entity_id, key, 0)),
				int(range_values[0]),
				int(range_values[1])
			))


func _append_duty_log(duty: Dictionary, result: Variant, day: int) -> void:
	session.world_log.append_entry({
		"entry_type": "life_project_duty",
		"project_id": project_id,
		"day": day,
		"rule_id": str(duty.get("duty_id", "")),
		"action_id": str(duty.get("duty_id", "")),
		"transaction_mode": "life_project_duty",
		"contract_status": "resolved",
		"facts_added": ["life_project_duty_completed"],
		"state_change_count": result.state_changes.size(),
		"relationship_change_count": result.relationship_changes.size(),
		"memory_count": result.memories_added.size(),
		"narrative_summary": str(result.narrative_result.get("summary", "")),
	})


func _observed_npc_narratives(tick_result: Dictionary) -> Array:
	var rows: Array[String] = []
	for result: Dictionary in tick_result.get("observed_autonomous_results", []):
		var narrative: Dictionary = result.get("narrative_result", {})
		var title := str(narrative.get("title", ""))
		var summary := str(narrative.get("summary", ""))
		if title != "" or summary != "":
			rows.append("%s：%s" % [title, summary])
	return rows


func _completion_relationship_lines() -> Array[String]:
	var rows: Array[String] = []
	var relationships: Variant = session.stores["relationship_store"]
	var people := [
		["captain_ron", "罗恩", "discipline_respect", "军纪表现"],
		["recruit_elai", "伊莱", "trust", "战友情"],
		["cook_marta", "玛塔", "trust", "信任"],
		["medic_saira", "赛拉", "familiarity", "熟悉"],
		["veteran_hoke", "霍克", "trust", "信任"],
	]
	for data: Array in people:
		var value := int(relationships.get_relation(
			str(data[0]), "player", str(data[2]), 0
		))
		if value > 0:
			rows.append("%s对你的%s达到 %d。" % [data[1], data[3], value])
	return rows


func _store_completion_chronicle() -> void:
	var summary := get_completion_summary()
	if not bool(summary.get("active", false)):
		return
	session.stores["chronicle_store"].add_entry({
		"entry_id": "%s:completion" % project_id,
		"subject_id": "player",
		"title": str(summary.get("title", "阶段小结")),
		"body": "%s\n\n%s" % [
			str(summary.get("intro", "")),
			"\n".join(summary.get("lines", [])),
		],
		"project_id": project_id,
		"source_fact_ids": _project_fact_ids(),
	})


func _project_fact_ids() -> Array:
	var rows: Array = []
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		if str(fact.get("project_id", "")) == project_id:
			rows.append(str(fact.get("fact_id", "")))
	return rows


func _attribute_label(key: String) -> String:
	return {
		"strength": "力量",
		"dexterity": "敏捷",
		"wisdom": "智慧",
		"charisma": "魅力",
		"constitution": "体质",
		"perception": "感知",
	}.get(key, key)


func _failure(error: String) -> Dictionary:
	return {
		"success": false,
		"error": error,
		"project_id": project_id,
	}
