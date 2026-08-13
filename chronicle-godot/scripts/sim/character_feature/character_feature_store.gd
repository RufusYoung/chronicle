extends RefCounted
class_name V5CharacterFeatureStore

const TALENT_SOURCE_KINDS := [
	"character_creation",
	"system_grant",
	"migration_fixture",
	"test_fixture",
]

var talent_defs: Dictionary = {}
var trait_defs: Dictionary = {}
var mark_defs: Dictionary = {}
var skill_defs: Dictionary = {}
var entity_store: Variant = null
var fact_store: Variant = null

var talent_assignments: Dictionary = {}
var trait_instances: Dictionary = {}
var mark_instances: Dictionary = {}
var skill_progress: Dictionary = {}
var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var last_error: String = ""


func configure(
		definitions: Dictionary,
		source_entity_store: Variant,
		source_fact_store: Variant
) -> void:
	talent_defs = (definitions.get("talent", {}) as Dictionary).duplicate(true)
	trait_defs = (definitions.get("trait", {}) as Dictionary).duplicate(true)
	mark_defs = (definitions.get("mark", {}) as Dictionary).duplicate(true)
	skill_defs = (definitions.get("skill", {}) as Dictionary).duplicate(true)
	entity_store = source_entity_store
	fact_store = source_fact_store
	clear()


func load_initial_data(fixture: Dictionary, context: Variant = null) -> Dictionary:
	clear()
	var initial: Dictionary = fixture.get("initial_character_features", {})
	for assignment: Dictionary in initial.get("talent_assignments", []):
		assign_talent(assignment)
	for instance: Dictionary in initial.get("trait_instances", []):
		load_trait_instance(instance)
	for instance: Dictionary in initial.get("mark_instances", []):
		load_mark_instance(instance)
	for progress: Dictionary in initial.get("skill_progress", []):
		load_skill_progress(progress)
	if context != null:
		_migrate_legacy_player_fields(context)
	apply_facts([] if fact_store == null else fact_store.list_facts())
	return get_contract_report()


func assign_talent(assignment: Dictionary) -> bool:
	last_error = ""
	var assignment_id := str(assignment.get("talent_assignment_id", ""))
	var talent_def_id := str(assignment.get("talent_def_id", ""))
	var owner_id := str(assignment.get("owner_entity_id", ""))
	var source_kind := str(assignment.get("source_kind", ""))
	if assignment_id == "" or talent_def_id == "" or owner_id == "":
		return _reject("invalid_talent_assignment_identity")
	if not _valid_owner(owner_id) or not talent_defs.has(talent_def_id):
		return _reject("%s:invalid_talent_reference" % assignment_id)
	if source_kind not in TALENT_SOURCE_KINDS:
		return _reject("%s:invalid_talent_source_kind" % assignment_id)
	if talent_assignments.has(assignment_id):
		return _reject("%s:duplicate_talent_assignment_id" % assignment_id)
	for existing: Dictionary in talent_assignments.values():
		if (
			str(existing.get("owner_entity_id", "")) == owner_id
			and str(existing.get("talent_def_id", "")) == talent_def_id
			and str(existing.get("status", "active")) == "active"
		):
			return _reject("%s:duplicate_active_talent" % assignment_id)
	var normalized := assignment.duplicate(true)
	normalized["status"] = str(normalized.get("status", "active"))
	normalized["source_fact_ids"] = (
		normalized.get("source_fact_ids", []) as Array
	).duplicate(true)
	normalized["assigned_tick"] = int(normalized.get("assigned_tick", 0))
	if source_kind == "system_grant" and normalized["source_fact_ids"].is_empty():
		return _reject("%s:system_grant_requires_source_fact" % assignment_id)
	if not _facts_exist(normalized["source_fact_ids"]):
		return _reject("%s:unknown_source_fact" % assignment_id)
	if not _facts_belong_to_owner(normalized["source_fact_ids"], owner_id):
		return _reject("%s:talent_source_owner_mismatch" % assignment_id)
	talent_assignments[assignment_id] = normalized
	return true


func load_trait_instance(instance: Dictionary) -> bool:
	last_error = ""
	var instance_id := str(instance.get("trait_instance_id", ""))
	var trait_def_id := str(instance.get("trait_def_id", ""))
	var owner_id := str(instance.get("owner_entity_id", ""))
	if instance_id == "" or not trait_defs.has(trait_def_id) or not _valid_owner(owner_id):
		return _reject("%s:invalid_trait_instance" % instance_id)
	if trait_instances.has(instance_id):
		return _reject("%s:duplicate_trait_instance_id" % instance_id)
	var source_kind := str(instance.get("source_kind", ""))
	var source_fact_ids: Array = (
		instance.get("source_fact_ids", []) as Array
	).duplicate(true)
	if source_fact_ids.is_empty() and source_kind not in [
		"character_creation", "migration_fixture", "test_fixture"
	]:
		return _reject("%s:trait_requires_source_fact" % instance_id)
	if not _facts_exist(source_fact_ids):
		return _reject("%s:unknown_source_fact" % instance_id)
	var definition: Dictionary = trait_defs[trait_def_id]
	if (
		not bool(definition.get("allow_multiple_instances", false))
		and _has_active_feature(trait_instances, owner_id, "trait_def_id", trait_def_id)
	):
		return _reject("%s:duplicate_active_trait" % instance_id)
	if (
		not source_fact_ids.is_empty()
		and not _trait_sources_are_valid(source_fact_ids, owner_id, definition)
	):
		return _reject("%s:invalid_trait_source_fact" % instance_id)
	var stage_id := str(instance.get("stage_id", ""))
	if stage_id not in (definition.get("stage_order", []) as Array):
		return _reject("%s:invalid_trait_stage" % instance_id)
	var normalized := instance.duplicate(true)
	normalized["severity"] = maxi(int(normalized.get("severity", 1)), 0)
	normalized["recovery_progress"] = maxi(
		int(normalized.get("recovery_progress", 0)),
		0
	)
	normalized["status"] = str(normalized.get("status", "active"))
	normalized["source_fact_ids"] = source_fact_ids
	normalized["created_tick"] = int(normalized.get("created_tick", 0))
	normalized["updated_tick"] = int(normalized.get("updated_tick", 0))
	trait_instances[instance_id] = normalized
	return true


func load_mark_instance(instance: Dictionary) -> bool:
	last_error = ""
	var instance_id := str(instance.get("mark_instance_id", ""))
	var mark_def_id := str(instance.get("mark_def_id", ""))
	var owner_id := str(instance.get("owner_entity_id", ""))
	if instance_id == "" or not mark_defs.has(mark_def_id) or not _valid_owner(owner_id):
		return _reject("%s:invalid_mark_instance" % instance_id)
	if mark_instances.has(instance_id):
		return _reject("%s:duplicate_mark_instance_id" % instance_id)
	var normalized := instance.duplicate(true)
	var source_kind := str(normalized.get("source_kind", ""))
	var progress := maxi(int(normalized.get("progress", 0)), 0)
	normalized["progress"] = progress
	normalized["stage_id"] = _mark_stage(mark_defs[mark_def_id], progress)
	normalized["status"] = str(normalized.get("status", "active"))
	normalized["source_fact_ids"] = (
		normalized.get("source_fact_ids", []) as Array
	).duplicate(true)
	normalized["progress_events"] = (
		normalized.get("progress_events", []) as Array
	).duplicate(true)
	if not _facts_exist(normalized["source_fact_ids"]):
		return _reject("%s:unknown_source_fact" % instance_id)
	if (
		progress > 0
		and normalized["source_fact_ids"].is_empty()
		and source_kind != "migration_fixture"
	):
		return _reject("%s:mark_progress_requires_source_fact" % instance_id)
	if (
		not normalized["source_fact_ids"].is_empty()
		and not _mark_sources_are_valid(normalized, owner_id, mark_defs[mark_def_id])
	):
		return _reject("%s:invalid_mark_source_fact" % instance_id)
	mark_instances[instance_id] = normalized
	return true


func load_skill_progress(progress: Dictionary) -> bool:
	last_error = ""
	var progress_id := str(progress.get("skill_progress_id", ""))
	var skill_def_id := str(progress.get("skill_def_id", ""))
	var owner_id := str(progress.get("owner_entity_id", ""))
	if progress_id == "" or not skill_defs.has(skill_def_id) or not _valid_owner(owner_id):
		return _reject("%s:invalid_skill_progress" % progress_id)
	if skill_progress.has(progress_id):
		return _reject("%s:duplicate_skill_progress_id" % progress_id)
	if _has_feature(skill_progress, owner_id, "skill_def_id", skill_def_id):
		return _reject("%s:duplicate_owner_skill_progress" % progress_id)
	var normalized := progress.duplicate(true)
	var practice_xp := maxi(int(normalized.get("practice_xp", 0)), 0)
	normalized["practice_xp"] = practice_xp
	normalized["rank"] = _skill_rank(skill_defs[skill_def_id], practice_xp)
	normalized["source_fact_ids"] = (
		normalized.get("source_fact_ids", []) as Array
	).duplicate(true)
	normalized["practice_events"] = (
		normalized.get("practice_events", []) as Array
	).duplicate(true)
	if not _facts_exist(normalized["source_fact_ids"]):
		return _reject("%s:unknown_source_fact" % progress_id)
	if practice_xp > 0 and normalized["source_fact_ids"].is_empty():
		return _reject("%s:skill_progress_requires_source_fact" % progress_id)
	if (
		not normalized["source_fact_ids"].is_empty()
		and not _skill_sources_are_valid(
			normalized,
			owner_id,
			skill_defs[skill_def_id]
		)
	):
		return _reject("%s:invalid_skill_source_fact" % progress_id)
	skill_progress[progress_id] = normalized
	return true


func apply_facts(facts: Array) -> Dictionary:
	var applied := {
		"trait_instances_created": 0,
		"mark_progress_events": 0,
		"skill_practice_events": 0,
	}
	for candidate: Dictionary in facts:
		var fact := _stored_fact(str(candidate.get("fact_id", "")))
		if fact.is_empty():
			continue
		applied["trait_instances_created"] += _apply_fact_to_traits(fact)
		applied["mark_progress_events"] += _apply_fact_to_marks(fact)
		applied["skill_practice_events"] += _apply_fact_to_skills(fact)
	return applied


func list_talent_assignments(owner_id: String = "") -> Array:
	return _list_owned(talent_assignments, owner_id)


func list_trait_instances(owner_id: String = "") -> Array:
	return _list_owned(trait_instances, owner_id)


func list_mark_instances(owner_id: String = "") -> Array:
	return _list_owned(mark_instances, owner_id)


func list_skill_progress(owner_id: String = "") -> Array:
	return _list_owned(skill_progress, owner_id)


func to_save_data() -> Dictionary:
	return {
		"talent_assignments": list_talent_assignments(),
		"trait_instances": list_trait_instances(),
		"mark_instances": list_mark_instances(),
		"skill_progress": list_skill_progress(),
	}


func load_save_data(data: Variant) -> Dictionary:
	clear()
	if not data is Dictionary:
		_reject("save_character_features_not_dictionary")
		return get_contract_report()
	for assignment: Variant in (data as Dictionary).get("talent_assignments", []):
		if assignment is Dictionary:
			assign_talent(assignment)
		else:
			_reject("save_talent_assignment_not_dictionary")
	for instance: Variant in (data as Dictionary).get("trait_instances", []):
		if instance is Dictionary:
			load_trait_instance(instance)
		else:
			_reject("save_trait_instance_not_dictionary")
	for instance: Variant in (data as Dictionary).get("mark_instances", []):
		if instance is Dictionary:
			load_mark_instance(instance)
		else:
			_reject("save_mark_instance_not_dictionary")
	for progress: Variant in (data as Dictionary).get("skill_progress", []):
		if progress is Dictionary:
			load_skill_progress(progress)
		else:
			_reject("save_skill_progress_not_dictionary")
	return get_contract_report()


func get_legacy_projection(owner_id: String) -> Dictionary:
	var projection := {
		"injury": "none",
		"mist_salt_echo": "none",
	}
	var latest_trait: Dictionary = {}
	for instance: Dictionary in list_trait_instances(owner_id):
		if str(instance.get("status", "active")) != "active":
			continue
		var candidate_def: Dictionary = trait_defs.get(
			str(instance.get("trait_def_id", "")),
			{}
		)
		if str(candidate_def.get("legacy_state_value", "")) == "":
			continue
		if latest_trait.is_empty() or int(instance.get("updated_tick", 0)) >= int(
			latest_trait.get("updated_tick", 0)
		):
			latest_trait = instance
	if not latest_trait.is_empty():
		var trait_def: Dictionary = trait_defs.get(
			str(latest_trait.get("trait_def_id", "")),
			{}
		)
		projection["injury"] = str(trait_def.get("legacy_state_value", "none"))
	var strongest_echo: Dictionary = {}
	for instance: Dictionary in list_mark_instances(owner_id):
		if str(instance.get("mark_def_id", "")) != "mark.mist_salt_echo":
			continue
		if strongest_echo.is_empty() or int(instance.get("progress", 0)) > int(
			strongest_echo.get("progress", 0)
		):
			strongest_echo = instance
	if not strongest_echo.is_empty():
		projection["mist_salt_echo"] = str(
			strongest_echo.get("stage_id", "none")
		)
	return projection


func get_contract_report() -> Dictionary:
	return {
		"ok": validation_errors.is_empty(),
		"talent_assignment_count": talent_assignments.size(),
		"trait_instance_count": trait_instances.size(),
		"mark_instance_count": mark_instances.size(),
		"skill_progress_count": skill_progress.size(),
		"errors": validation_errors.duplicate(),
		"warnings": validation_warnings.duplicate(),
	}


func clear() -> void:
	talent_assignments.clear()
	trait_instances.clear()
	mark_instances.clear()
	skill_progress.clear()
	validation_errors.clear()
	validation_warnings.clear()
	last_error = ""


func _apply_fact_to_traits(fact: Dictionary) -> int:
	var fact_id := str(fact.get("fact_id", ""))
	if fact_id == "" or not _fact_exists(fact_id):
		return 0
	var created := 0
	for trait_def_id: String in trait_defs.keys():
		var definition: Dictionary = trait_defs[trait_def_id]
		for rule: Dictionary in definition.get("source_fact_rules", []):
			if not _fact_matches_rule(fact, rule):
				continue
			var owner_id := _fact_owner_id(fact)
			if (
				not bool(definition.get("allow_multiple_instances", false))
				and _has_active_feature(
					trait_instances,
					owner_id,
					"trait_def_id",
					trait_def_id
				)
			):
				continue
			var instance_id := "trait_instance.%s.%s" % [
				_sanitize_id(fact_id),
				trait_def_id.trim_prefix("trait."),
			]
			if trait_instances.has(instance_id):
				continue
			if load_trait_instance({
				"trait_instance_id": instance_id,
				"trait_def_id": trait_def_id,
				"owner_entity_id": owner_id,
				"stage_id": str(rule.get("stage_id", "fresh")),
				"severity": int(rule.get("severity", 1)),
				"status": "active",
				"source_fact_ids": [fact_id],
				"created_tick": _fact_tick(fact),
				"updated_tick": _fact_tick(fact),
				"recovery_progress": 0,
			}):
				created += 1
	return created


func _apply_fact_to_marks(fact: Dictionary) -> int:
	var fact_id := str(fact.get("fact_id", ""))
	if fact_id == "" or not _fact_exists(fact_id):
		return 0
	var applied := 0
	for mark_def_id: String in mark_defs.keys():
		var definition: Dictionary = mark_defs[mark_def_id]
		var fact_type := _fact_type(fact)
		if fact_type not in (definition.get("accepted_fact_types", []) as Array):
			continue
		var owner_id := _fact_owner_id(fact)
		var instance_id := "mark_instance.%s.%s" % [
			_sanitize_id(owner_id),
			mark_def_id.trim_prefix("mark."),
		]
		var instance: Dictionary = mark_instances.get(instance_id, {
			"mark_instance_id": instance_id,
			"mark_def_id": mark_def_id,
			"owner_entity_id": owner_id,
			"progress": 0,
			"status": "active",
			"source_fact_ids": [],
			"progress_events": [],
			"created_tick": _fact_tick(fact),
			"updated_tick": _fact_tick(fact),
		})
		if fact_id in (instance.get("source_fact_ids", []) as Array):
			continue
		var delta := int((definition.get("progress_by_fact_type", {}) as Dictionary).get(
			fact_type,
			1
		))
		instance["progress"] = maxi(int(instance.get("progress", 0)) + delta, 0)
		instance["stage_id"] = _mark_stage(definition, int(instance["progress"]))
		(instance["source_fact_ids"] as Array).append(fact_id)
		(instance["progress_events"] as Array).append({
			"fact_id": fact_id,
			"delta": delta,
		})
		instance["updated_tick"] = _fact_tick(fact)
		mark_instances[instance_id] = instance
		applied += 1
	return applied


func _apply_fact_to_skills(fact: Dictionary) -> int:
	var fact_id := str(fact.get("fact_id", ""))
	if fact_id == "" or not _fact_exists(fact_id):
		return 0
	var applied := 0
	for skill_def_id: String in skill_defs.keys():
		var definition: Dictionary = skill_defs[skill_def_id]
		for rule: Dictionary in definition.get("practice_rules", []):
			if not _fact_matches_rule(fact, rule):
				continue
			var owner_id := _fact_owner_id(fact)
			var progress_id := "skill_progress.%s.%s" % [
				_sanitize_id(owner_id),
				skill_def_id.trim_prefix("skill."),
			]
			var progress: Dictionary = skill_progress.get(progress_id, {
				"skill_progress_id": progress_id,
				"skill_def_id": skill_def_id,
				"owner_entity_id": owner_id,
				"practice_xp": 0,
				"source_fact_ids": [],
				"practice_events": [],
				"updated_tick": _fact_tick(fact),
			})
			if fact_id in (progress.get("source_fact_ids", []) as Array):
				continue
			var xp := int(rule.get("xp", 0))
			progress["practice_xp"] = int(progress.get("practice_xp", 0)) + xp
			progress["rank"] = _skill_rank(
				definition,
				int(progress["practice_xp"])
			)
			(progress["source_fact_ids"] as Array).append(fact_id)
			(progress["practice_events"] as Array).append({
				"fact_id": fact_id,
				"xp": xp,
			})
			progress["updated_tick"] = _fact_tick(fact)
			skill_progress[progress_id] = progress
			applied += 1
	return applied


func _migrate_legacy_player_fields(context: Variant) -> void:
	var owner_id := str(context.player.get("id", context.actor_id))
	var injury := str(context.player.get("injury", "none"))
	if injury != "" and injury != "none":
		for trait_def_id: String in trait_defs.keys():
			var definition: Dictionary = trait_defs[trait_def_id]
			if str(definition.get("legacy_state_value", "")) != injury:
				continue
			load_trait_instance({
				"trait_instance_id": "trait_instance.migration.%s.%s" % [
					_sanitize_id(owner_id),
					trait_def_id.trim_prefix("trait."),
				],
				"trait_def_id": trait_def_id,
				"owner_entity_id": owner_id,
				"stage_id": "fresh",
				"severity": 1,
				"status": "active",
				"source_kind": "migration_fixture",
				"source_fact_ids": [],
				"created_tick": 0,
				"updated_tick": 0,
				"recovery_progress": 0,
			})
	var echo_stage := str(context.player.get("mist_salt_echo", "none"))
	if echo_stage != "" and echo_stage != "none" and mark_defs.has(
		"mark.mist_salt_echo"
	):
		var definition: Dictionary = mark_defs["mark.mist_salt_echo"]
		load_mark_instance({
			"mark_instance_id": "mark_instance.%s.mist_salt_echo" % _sanitize_id(owner_id),
			"mark_def_id": "mark.mist_salt_echo",
			"owner_entity_id": owner_id,
			"progress": _minimum_progress_for_mark_stage(definition, echo_stage),
			"status": "active",
			"source_kind": "migration_fixture",
			"source_fact_ids": [],
			"progress_events": [],
			"created_tick": 0,
			"updated_tick": 0,
		})


func _list_owned(source: Dictionary, owner_id: String) -> Array:
	var rows: Array = []
	for value: Dictionary in source.values():
		if owner_id == "" or str(value.get("owner_entity_id", "")) == owner_id:
			rows.append(value.duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _feature_id(a) < _feature_id(b)
	)
	return rows


func _feature_id(value: Dictionary) -> String:
	for key: String in [
		"talent_assignment_id", "trait_instance_id", "mark_instance_id", "skill_progress_id"
	]:
		if value.has(key):
			return str(value.get(key, ""))
	return ""


func _fact_matches_rule(fact: Dictionary, rule: Dictionary) -> bool:
	if _fact_type(fact) != str(rule.get("fact_type", "")):
		return false
	for key: String in (rule.get("field_equals", {}) as Dictionary).keys():
		if fact.get(key) != (rule.get("field_equals", {}) as Dictionary)[key]:
			return false
	return true


func _trait_sources_are_valid(
		fact_ids: Array,
		owner_id: String,
		definition: Dictionary
) -> bool:
	if _has_duplicate_values(fact_ids):
		return false
	for fact_id: Variant in fact_ids:
		var fact := _stored_fact(str(fact_id))
		if _fact_owner_id(fact) != owner_id:
			return false
		var accepted := false
		for rule: Dictionary in definition.get("source_fact_rules", []):
			if _fact_matches_rule(fact, rule):
				accepted = true
				break
		if not accepted:
			return false
	return true


func _mark_sources_are_valid(
		instance: Dictionary,
		owner_id: String,
		definition: Dictionary
) -> bool:
	var fact_ids: Array = instance.get("source_fact_ids", [])
	var events: Array = instance.get("progress_events", [])
	if _has_duplicate_values(fact_ids) or events.size() != fact_ids.size():
		return false
	var event_fact_ids: Array = []
	var total_progress := 0
	for event: Dictionary in events:
		var fact_id := str(event.get("fact_id", ""))
		var fact := _stored_fact(fact_id)
		var delta := int(event.get("delta", 0))
		if (
			fact_id not in fact_ids
			or fact_id in event_fact_ids
			or _fact_owner_id(fact) != owner_id
			or _fact_type(fact) not in (
				definition.get("accepted_fact_types", []) as Array
			)
			or delta != int((definition.get(
				"progress_by_fact_type",
				{}
			) as Dictionary).get(_fact_type(fact), 0))
		):
			return false
		event_fact_ids.append(fact_id)
		total_progress += delta
	return total_progress == int(instance.get("progress", 0))


func _skill_sources_are_valid(
		progress: Dictionary,
		owner_id: String,
		definition: Dictionary
) -> bool:
	var fact_ids: Array = progress.get("source_fact_ids", [])
	var events: Array = progress.get("practice_events", [])
	if _has_duplicate_values(fact_ids) or events.size() != fact_ids.size():
		return false
	var event_fact_ids: Array = []
	var total_xp := 0
	for event: Dictionary in events:
		var fact_id := str(event.get("fact_id", ""))
		var fact := _stored_fact(fact_id)
		var xp := int(event.get("xp", 0))
		if (
			fact_id not in fact_ids
			or fact_id in event_fact_ids
			or _fact_owner_id(fact) != owner_id
			or _fact_type(fact) not in (
				definition.get("accepted_practice_fact_types", []) as Array
			)
			or xp != _practice_xp_for_fact(fact, definition)
		):
			return false
		event_fact_ids.append(fact_id)
		total_xp += xp
	return total_xp == int(progress.get("practice_xp", 0))


func _practice_xp_for_fact(fact: Dictionary, definition: Dictionary) -> int:
	for rule: Dictionary in definition.get("practice_rules", []):
		if _fact_matches_rule(fact, rule):
			return int(rule.get("xp", 0))
	return 0


func _fact_type(fact: Dictionary) -> String:
	return str(fact.get("fact_type", fact.get("type", "")))


func _fact_owner_id(fact: Dictionary) -> String:
	for key: String in ["actor_id", "source_id", "owner_entity_id"]:
		var owner_id := str(fact.get(key, ""))
		if owner_id != "":
			return owner_id
	return str(fact.get("target_id", ""))


func _fact_tick(fact: Dictionary) -> int:
	if fact.has("tick"):
		return int(fact.get("tick", 0))
	return int(fact.get("day", 0)) * 24 + int(fact.get("hour", 0))


func _mark_stage(definition: Dictionary, progress: int) -> String:
	var stage_id := "none"
	for stage: Dictionary in definition.get("stages", []):
		if progress >= int(stage.get("threshold", 0)):
			stage_id = str(stage.get("stage_id", stage_id))
	return stage_id


func _minimum_progress_for_mark_stage(definition: Dictionary, stage_id: String) -> int:
	for stage: Dictionary in definition.get("stages", []):
		if str(stage.get("stage_id", "")) == stage_id:
			return int(stage.get("threshold", 0))
	return 0


func _skill_rank(definition: Dictionary, practice_xp: int) -> int:
	var rank := 0
	for index: int in range((definition.get("rank_thresholds", []) as Array).size()):
		if practice_xp >= int((definition.get("rank_thresholds", []) as Array)[index]):
			rank = index
	return rank


func _facts_exist(fact_ids: Array) -> bool:
	for fact_id: Variant in fact_ids:
		if not _fact_exists(str(fact_id)):
			return false
	return true


func _facts_belong_to_owner(fact_ids: Array, owner_id: String) -> bool:
	for fact_id: Variant in fact_ids:
		if _fact_owner_id(_stored_fact(str(fact_id))) != owner_id:
			return false
	return true


func _has_feature(
		source: Dictionary,
		owner_id: String,
		definition_field: String,
		definition_id: String
) -> bool:
	for value: Dictionary in source.values():
		if (
			str(value.get("owner_entity_id", "")) == owner_id
			and str(value.get(definition_field, "")) == definition_id
		):
			return true
	return false


func _has_active_feature(
		source: Dictionary,
		owner_id: String,
		definition_field: String,
		definition_id: String
) -> bool:
	for value: Dictionary in source.values():
		if (
			str(value.get("owner_entity_id", "")) == owner_id
			and str(value.get(definition_field, "")) == definition_id
			and str(value.get("status", "active")) == "active"
		):
			return true
	return false


func _has_duplicate_values(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		var key := str(value)
		if key == "" or seen.has(key):
			return true
		seen[key] = true
	return false


func _fact_exists(fact_id: String) -> bool:
	return not _stored_fact(fact_id).is_empty()


func _stored_fact(fact_id: String) -> Dictionary:
	if fact_id == "" or fact_store == null:
		return {}
	if fact_store.has_method("get_fact"):
		return fact_store.get_fact(fact_id)
	for fact: Dictionary in fact_store.list_facts():
		if str(fact.get("fact_id", "")) == fact_id:
			return fact.duplicate(true)
	return {}


func _valid_owner(owner_id: String) -> bool:
	return owner_id != "" and entity_store != null and entity_store.has_entity(owner_id)


func _sanitize_id(value: String) -> String:
	return value.replace(":", ".").replace("/", ".").replace(" ", "_")


func _reject(message: String) -> bool:
	last_error = message
	validation_errors.append(message)
	return false
