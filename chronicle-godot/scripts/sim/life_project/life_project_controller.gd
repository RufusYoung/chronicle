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
var action_contract_resolver: Variant = ActionContractResolverModel.new()
var effect_protocol_resolver: Variant = EffectProtocolResolverModel.new()


func start(
		fixture_path: String,
		project_path: String,
		rule_paths: Array = []
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
		rule_paths
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


func build_save_envelope(options: Dictionary = {}) -> Dictionary:
	if not is_ready():
		return {}
	var save_options := options.duplicate(true)
	save_options["life_project_runtime"] = _life_project_save_data()
	return session.build_save_envelope(save_options)


func build_life_stage_transition(target_fixture_id: String) -> Dictionary:
	if (
		not is_complete()
		or _confirmed_growth_candidate_id() == ""
		or target_fixture_id == ""
	):
		return {}
	return LifeStageTransitionServiceModel.new().build_player_transition(
		session,
		{"target_fixture_id": target_fixture_id}
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
	return is_ready() and get_day() > get_duration_days()


func get_day() -> int:
	if not is_ready():
		return 0
	return int(session.get_snapshot().get_player_value("service_day", 1))


func get_duration_days() -> int:
	return maxi(int(definition.get("duration_days", 1)), 1)


func get_ritual() -> Dictionary:
	var ritual: Dictionary = definition.get("ritual", {})
	return {
		"title": str(ritual.get("title", "清晨点名")).replace(
			"{day}", str(mini(get_day(), get_duration_days()))
		),
		"body": str(ritual.get("body", "")),
	}


func get_duty_options() -> Array:
	var rows: Array[Dictionary] = []
	if not is_ready() or is_complete():
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
	if is_complete():
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
	var tick_event := _day_tick_event(day)
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

	var settlement_result: Variant = _settle_day(day)
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

	var tick_result: Dictionary = session.advance_world(tick_event, 24)
	if not bool(tick_result.get("success", false)):
		var failed_tick := _failure("day_tick_failed")
		failed_tick["tick_result"] = tick_result.duplicate(true)
		return failed_tick
	_clamp_states()

	var next_day := day + 1
	session.stores["state_store"].set_state(
		"player", "service_day", next_day
	)
	var row := {
		"day": day,
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
		"status": get_status(),
	}
	day_history.append(row)
	if is_complete():
		_store_completion_chronicle()
	latest_result = {
		"success": true,
		"day": day,
		"duty_id": duty_id,
		"title": row["title"],
		"summary": row["summary"],
		"risk_outcome": row["risk_outcome"],
		"settlement_notes": row["settlement_notes"],
		"npc_narratives": row["npc_narratives"],
		"status": row["status"],
		"complete": is_complete(),
		"completion": get_completion_summary(),
		"base_values": eligibility.get("base_values", {}),
		"modified_values": eligibility.get("modified_values", {}),
		"modifier_explanations": eligibility.get(
			"modifier_explanations", []
		),
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
	}


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
	var rows: Array = []
	if not match_rule is Dictionary:
		return rows
	var matcher := match_rule as Dictionary
	var duty_ids: Array = matcher.get("duty_ids", [])
	for fact: Dictionary in session.stores["fact_store"].list_facts():
		if str(fact.get("project_id", "")) != project_id:
			continue
		var fact_type := str(matcher.get("fact_type", ""))
		if fact_type != "" and str(fact.get("fact_type", "")) != fact_type:
			continue
		if not duty_ids.is_empty() and str(fact.get("duty_id", "")) not in duty_ids:
			continue
		rows.append(str(fact.get("fact_id", "")))
	return rows


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


func _settle_day(day: int) -> Variant:
	var result = TransactionResultModel.new()
	var model: Dictionary = definition.get("daily_settlement", {})
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
		"location_id": str(session.context.location_id),
	})
	result.set_narrative_result({
		"title": "第 %d 天过去" % day,
		"summary": "值勤、消耗和风雪都已经结算。",
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
	if (
		not history_value is Array
		or not duty_value is Dictionary
		or not latest_value is Dictionary
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
	action_contract_resolver.configure(session.registry)
	initialized = true
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


func _day_tick_event(day: int) -> Dictionary:
	return {
		"tick_event_id": "%s_day_%d" % [project_id, day],
		"tick_type": "life_project_day",
		"trigger_key": "life_project_day_end",
		"scope_type": "location",
		"scope_id": str(session.context.location_id),
		"day": int(session.current_day + 1),
		"time_key": "next_roll_call",
		"source": "LifeProjectController",
		"label": "第七哨站值勤日结算",
		"elapsed_hours": 0,
		"include_due_checks": true,
		"due_kinds": ["obligation", "exchange"],
	}


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
