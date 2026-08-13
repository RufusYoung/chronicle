extends RefCounted
class_name V5SimRegistry

const DEFINITION_COLLECTIONS := {
	"state_defs": {
		"kind": "state",
		"id_field": "state_def_id",
	},
	"object_defs": {
		"kind": "object",
		"id_field": "object_def_id",
	},
	"talent_defs": {
		"kind": "talent",
		"id_field": "talent_def_id",
	},
	"trait_defs": {
		"kind": "trait",
		"id_field": "trait_def_id",
	},
	"mark_defs": {
		"kind": "mark",
		"id_field": "mark_def_id",
	},
	"skill_defs": {
		"kind": "skill",
		"id_field": "skill_def_id",
	},
	"item_defs": {
		"kind": "item",
		"id_field": "item_def_id",
	},
	"equipment_slot_defs": {
		"kind": "equipment_slot",
		"id_field": "slot_def_id",
	},
}

const STATE_VALUE_TYPES := [
	"bool",
	"int",
	"float",
	"string",
	"enum",
]

const STATE_OPERATIONS := ["set", "add", "degrade"]
const STATE_OWNER_KINDS := [
	"entity", "character", "object", "region", "institution", "household",
]
const STATE_UI_VISIBILITY := ["hidden", "summary", "detail"]

var definitions: Dictionary = {}
var action_rules: Array = []
var definition_errors: Array[String] = []
var definition_warnings: Array[String] = []
var definition_sources: Dictionary = {}


func register_definition(
		kind: String,
		definition_id: String,
		data: Dictionary,
		source_path: String = ""
) -> bool:
	var normalized_kind := kind.strip_edges()
	var normalized_id := definition_id.strip_edges()
	if normalized_kind == "":
		return _definition_error("missing_definition_kind")
	if normalized_id == "":
		return _definition_error("%s:missing_definition_id" % normalized_kind)

	var group := _ensure_group(normalized_kind)
	if group.has(normalized_id):
		return _definition_error(
			"%s:%s:duplicate_definition_id" % [normalized_kind, normalized_id]
		)

	var normalized := _normalize_definition(normalized_kind, data)
	var id_field := _definition_id_field(normalized_kind)
	if id_field != "":
		var embedded_id := str(normalized.get(id_field, ""))
		if embedded_id != "" and embedded_id != normalized_id:
			return _definition_error(
				"%s:%s:definition_id_mismatch:%s" % [
					normalized_kind,
					normalized_id,
					embedded_id,
				]
			)
		normalized[id_field] = normalized_id
	var validation := _validate_definition(
		normalized_kind,
		normalized_id,
		normalized
	)
	for warning: String in validation.get("warnings", []):
		definition_warnings.append(warning)
	var errors: Array = validation.get("errors", [])
	if not errors.is_empty():
		for error: String in errors:
			definition_errors.append(error)
		return false
	var identity_field := _definition_identity_field(normalized_kind)
	if identity_field != "":
		var logical_identity := str(normalized.get(identity_field, ""))
		for existing_id: String in group.keys():
			var existing: Dictionary = group[existing_id]
			if str(existing.get(identity_field, "")) == logical_identity:
				return _definition_error(
					"%s:%s:duplicate_%s:%s" % [
						normalized_kind,
						normalized_id,
						identity_field,
						existing_id,
					]
				)

	group[normalized_id] = normalized
	if source_path != "":
		definition_sources["%s:%s" % [normalized_kind, normalized_id]] = source_path
	return true


func has_definition(kind: String, definition_id: String) -> bool:
	return definitions.has(kind) and (definitions[kind] as Dictionary).has(
		definition_id
	)


func get_definition(kind: String, definition_id: String) -> Dictionary:
	if not has_definition(kind, definition_id):
		return {}
	return ((definitions[kind] as Dictionary)[definition_id] as Dictionary).duplicate(
		true
	)


func list_definitions(kind: String) -> Dictionary:
	if not definitions.has(kind):
		return {}
	return (definitions[kind] as Dictionary).duplicate(true)


func get_state_definitions_by_key() -> Dictionary:
	var rows: Dictionary = {}
	for definition: Dictionary in list_definitions("state").values():
		var key := str(definition.get("key", ""))
		if key != "":
			rows[key] = definition.duplicate(true)
	return rows


func load_raw_definitions(path: String, strict: bool = true) -> Dictionary:
	var data := load_json(path)
	if data.is_empty():
		_definition_error("%s:definition_file_not_loaded" % path)
		return _definition_report(0)

	var registered_count := 0
	var recognized_collection := false
	for collection_key: String in DEFINITION_COLLECTIONS.keys():
		if not data.has(collection_key):
			continue
		recognized_collection = true
		var spec: Dictionary = DEFINITION_COLLECTIONS[collection_key]
		var values: Variant = data.get(collection_key, [])
		if not values is Array:
			_definition_error("%s:%s:not_an_array" % [path, collection_key])
			continue
		for index: int in range((values as Array).size()):
			var value: Variant = (values as Array)[index]
			if not value is Dictionary:
				_definition_error(
					"%s:%s:%d:not_a_dictionary" % [path, collection_key, index]
				)
				continue
			var definition: Dictionary = (value as Dictionary).duplicate(true)
			var definition_id := str(definition.get(spec.get("id_field", ""), ""))
			if definition_id == "" and not strict:
				definition_id = _legacy_definition_id(
					str(spec.get("kind", "")),
					definition
				)
				if definition_id != "":
					definition[str(spec.get("id_field", ""))] = definition_id
			if register_definition(
				str(spec.get("kind", "")),
				definition_id,
				definition,
				path
			):
				registered_count += 1

	if not recognized_collection:
		_definition_error("%s:no_supported_definition_collection" % path)
	return _definition_report(registered_count)


func load_raw_definition_files(
		paths: Array,
		strict: bool = true,
		clear_existing: bool = true
) -> Dictionary:
	if clear_existing:
		definitions.clear()
		definition_sources.clear()
	definition_errors.clear()
	definition_warnings.clear()

	var registered_count := 0
	for path_value: Variant in paths:
		var report := load_raw_definitions(str(path_value), strict)
		registered_count += int(report.get("registered_count", 0))
	_validate_cross_definition_references()
	return _definition_report(registered_count)


func load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open JSON file: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed

	push_error("JSON file did not contain an object: %s" % path)
	return {}


func load_action_rules(paths: Array) -> void:
	action_rules.clear()
	for path: String in paths:
		var data := load_json(path)
		for rule: Variant in data.get("rules", []):
			if rule is Dictionary:
				action_rules.append((rule as Dictionary).duplicate(true))


func get_action_rules() -> Array:
	return action_rules.duplicate(true)


func get_definition_report() -> Dictionary:
	return _definition_report(_definition_count())


func _validate_definition(
		kind: String,
		definition_id: String,
		definition: Dictionary
) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if kind not in [
		"state", "object", "talent", "trait", "mark", "skill", "item",
		"equipment_slot"
	]:
		return {"errors": errors, "warnings": warnings}

	var version := int(definition.get("definition_version", 0))
	if version < 1:
		errors.append("%s:%s:invalid_definition_version" % [kind, definition_id])

	if kind == "state":
		_validate_state_definition(definition_id, definition, errors)
	elif kind == "object":
		_validate_object_definition(definition_id, definition, errors)
	elif kind == "talent":
		_validate_talent_definition(definition_id, definition, errors)
	elif kind == "trait":
		_validate_trait_definition(definition_id, definition, errors)
	elif kind == "mark":
		_validate_mark_definition(definition_id, definition, errors)
	elif kind == "skill":
		_validate_skill_definition(definition_id, definition, errors)
	elif kind == "item":
		_validate_item_definition(definition_id, definition, errors)
	elif kind == "equipment_slot":
		_validate_equipment_slot_definition(definition_id, definition, errors)
	return {"errors": errors, "warnings": warnings}


func _validate_state_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	var key := str(definition.get("key", ""))
	if key == "":
		errors.append("state:%s:missing_key" % definition_id)
	var value_type := str(definition.get("value_type", ""))
	if value_type not in STATE_VALUE_TYPES:
		errors.append("state:%s:invalid_value_type:%s" % [definition_id, value_type])
	var owner_kinds: Variant = definition.get("owner_kinds", [])
	if not owner_kinds is Array or (owner_kinds as Array).is_empty():
		errors.append("state:%s:missing_owner_kinds" % definition_id)
	elif not _array_values_allowed(owner_kinds, STATE_OWNER_KINDS):
		errors.append("state:%s:invalid_owner_kinds" % definition_id)
	var operations: Variant = definition.get("allowed_operations", [])
	if not operations is Array or (operations as Array).is_empty():
		errors.append("state:%s:missing_allowed_operations" % definition_id)
	elif not _array_values_allowed(operations, STATE_OPERATIONS):
		errors.append("state:%s:invalid_allowed_operations" % definition_id)
	if value_type == "enum":
		var values: Variant = definition.get("values", [])
		if not values is Array or (values as Array).is_empty():
			errors.append("state:%s:missing_enum_values" % definition_id)
	if str(definition.get("persistence", "")) == "":
		errors.append("state:%s:missing_persistence" % definition_id)
	var ui_visibility := str(definition.get("ui_visibility", ""))
	if ui_visibility not in STATE_UI_VISIBILITY:
		errors.append("state:%s:invalid_ui_visibility" % definition_id)
	if definition.has("minimum") and definition.has("maximum"):
		if float(definition.get("minimum")) > float(definition.get("maximum")):
			errors.append("state:%s:invalid_numeric_range" % definition_id)
	if definition.has("default") and value_type in STATE_VALUE_TYPES:
		var default_value: Variant = definition.get("default")
		if not _definition_value_matches_type(default_value, value_type):
			errors.append("state:%s:default_type_mismatch" % definition_id)
		elif value_type == "enum" and default_value not in (
			definition.get("values", []) as Array
		):
			errors.append("state:%s:default_not_in_enum" % definition_id)
		elif default_value is int or default_value is float:
			if definition.has("minimum") and float(default_value) < float(
				definition.get("minimum")
			):
				errors.append("state:%s:default_below_minimum" % definition_id)
			if definition.has("maximum") and float(default_value) > float(
				definition.get("maximum")
			):
				errors.append("state:%s:default_above_maximum" % definition_id)


func _validate_object_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	if str(definition.get("type", "")) == "":
		errors.append("object:%s:missing_type" % definition_id)
	if str(definition.get("owner_kind", "")) == "":
		errors.append("object:%s:missing_owner_kind" % definition_id)
	var default_tags: Variant = definition.get("default_tags", [])
	if not default_tags is Array:
		errors.append("object:%s:default_tags_not_array" % definition_id)


func _validate_talent_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	_validate_feature_header("talent", definition_id, definition, errors)
	_validate_array_field(
		"talent", definition_id, definition, "granted_affordance_tags", errors
	)


func _validate_trait_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	_validate_feature_header("trait", definition_id, definition, errors)
	var stage_order: Variant = definition.get("stage_order", [])
	if not stage_order is Array or (stage_order as Array).is_empty():
		errors.append("trait:%s:missing_stage_order" % definition_id)
	elif _has_duplicate_values(stage_order):
		errors.append("trait:%s:duplicate_stage_id" % definition_id)
	var terminal_stages: Variant = definition.get("terminal_stages", [])
	if not terminal_stages is Array:
		errors.append("trait:%s:terminal_stages_not_array" % definition_id)
	elif stage_order is Array:
		for terminal_stage: Variant in terminal_stages:
			if terminal_stage not in stage_order:
				errors.append("trait:%s:unknown_terminal_stage" % definition_id)
	if not definition.get("allow_multiple_instances", false) is bool:
		errors.append("trait:%s:allow_multiple_instances_not_bool" % definition_id)
	_validate_source_fact_rules("trait", definition_id, definition, errors)
	var source_rules: Variant = definition.get("source_fact_rules", [])
	if stage_order is Array and source_rules is Array:
		for rule_value: Variant in source_rules:
			if not rule_value is Dictionary:
				continue
			var rule := rule_value as Dictionary
			if str(rule.get("stage_id", "")) not in stage_order:
				errors.append("trait:%s:invalid_source_stage" % definition_id)
			if int(rule.get("severity", 0)) <= 0:
				errors.append("trait:%s:invalid_source_severity" % definition_id)


func _validate_mark_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	_validate_feature_header("mark", definition_id, definition, errors)
	_validate_array_field(
		"mark", definition_id, definition, "granted_affordance_tags", errors
	)
	_validate_nonempty_string_array(
		"mark", definition_id, definition, "accepted_fact_types", errors
	)
	var stages: Variant = definition.get("stages", [])
	if not stages is Array or (stages as Array).is_empty():
		errors.append("mark:%s:missing_stages" % definition_id)
	else:
		_validate_threshold_rows("mark", definition_id, stages, "stage_id", errors)
	var progress_by_type: Variant = definition.get("progress_by_fact_type", {})
	if not progress_by_type is Dictionary:
		errors.append("mark:%s:progress_by_fact_type_not_dictionary" % definition_id)
	else:
		var accepted_types: Variant = definition.get("accepted_fact_types", [])
		for fact_type: String in progress_by_type.keys():
			if (
				not accepted_types is Array
				or fact_type not in accepted_types
				or int(progress_by_type[fact_type]) <= 0
			):
				errors.append("mark:%s:invalid_progress_fact_type" % definition_id)
	var progress_rules: Variant = definition.get("progress_rules", [])
	if not progress_rules is Array:
		errors.append("mark:%s:progress_rules_not_array" % definition_id)
	else:
		var accepted_types: Variant = definition.get("accepted_fact_types", [])
		for rule_value: Variant in progress_rules:
			if not rule_value is Dictionary:
				errors.append("mark:%s:progress_rule_not_dictionary" % definition_id)
				continue
			var rule := rule_value as Dictionary
			var fact_type := str(rule.get("fact_type", ""))
			if (
				fact_type == ""
				or not accepted_types is Array
				or fact_type not in accepted_types
				or int(rule.get("delta", 0)) <= 0
			):
				errors.append("mark:%s:invalid_progress_rule" % definition_id)
			if not rule.get("field_equals", {}) is Dictionary:
				errors.append("mark:%s:progress_rule_fields_not_dictionary" % definition_id)


func _validate_skill_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	_validate_feature_header("skill", definition_id, definition, errors)
	_validate_nonempty_string_array(
		"skill",
		definition_id,
		definition,
		"accepted_practice_fact_types",
		errors
	)
	var thresholds: Variant = definition.get("rank_thresholds", [])
	if not thresholds is Array or (thresholds as Array).is_empty():
		errors.append("skill:%s:missing_rank_thresholds" % definition_id)
	elif not _ascending_nonnegative_numbers(thresholds) or int(thresholds[0]) != 0:
		errors.append("skill:%s:invalid_rank_thresholds" % definition_id)
	var practice_rules: Variant = definition.get("practice_rules", [])
	if not practice_rules is Array or (practice_rules as Array).is_empty():
		errors.append("skill:%s:missing_practice_rules" % definition_id)
	else:
		var accepted_types: Variant = definition.get(
			"accepted_practice_fact_types",
			[]
		)
		for rule_value: Variant in practice_rules:
			if not rule_value is Dictionary:
				errors.append("skill:%s:practice_rule_not_dictionary" % definition_id)
				continue
			var rule := rule_value as Dictionary
			if str(rule.get("fact_type", "")) == "" or int(rule.get("xp", 0)) <= 0:
				errors.append("skill:%s:invalid_practice_rule" % definition_id)
			elif (
				not accepted_types is Array
				or str(rule.get("fact_type", "")) not in accepted_types
			):
				errors.append("skill:%s:unaccepted_practice_rule" % definition_id)


func _validate_item_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	_validate_feature_header("item", definition_id, definition, errors)
	if str(definition.get("item_kind", "")) == "":
		errors.append("item:%s:missing_item_kind" % definition_id)
	if not definition.get("stackable", false) is bool:
		errors.append("item:%s:stackable_not_bool" % definition_id)
	var max_stack: Variant = definition.get("max_stack", 0)
	if not max_stack is int or int(max_stack) < 1:
		errors.append("item:%s:invalid_max_stack" % definition_id)
	elif not bool(definition.get("stackable", false)) and int(max_stack) != 1:
		errors.append("item:%s:non_stackable_max_stack" % definition_id)
	var base_mass: Variant = definition.get("base_mass", 0.0)
	if (
		not (base_mass is int or base_mass is float)
		or float(base_mass) < 0.0
	):
		errors.append("item:%s:invalid_base_mass" % definition_id)
	var base_value: Variant = definition.get("base_value", 0)
	if (
		not (base_value is int or base_value is float)
		or float(base_value) < 0.0
	):
		errors.append("item:%s:invalid_base_value" % definition_id)
	_validate_array_field("item", definition_id, definition, "equip_slots", errors)
	_validate_array_field("item", definition_id, definition, "capabilities", errors)
	var equip_slots: Variant = definition.get("equip_slots", [])
	var capabilities: Variant = definition.get("capabilities", [])
	if (
		equip_slots is Array
		and not (equip_slots as Array).is_empty()
		and capabilities is Array
		and "equip" not in (capabilities as Array)
	):
		errors.append("item:%s:equipment_slots_without_equip_capability" % definition_id)
	if definitions.has("equipment_slot") and not (
		definitions["equipment_slot"] as Dictionary
	).is_empty() and equip_slots is Array:
		for slot_value: Variant in equip_slots:
			var slot_id := "slot.%s" % str(slot_value).trim_prefix("slot.")
			if not (definitions["equipment_slot"] as Dictionary).has(slot_id):
				errors.append("item:%s:unknown_equipment_slot:%s" % [
					definition_id,
					str(slot_value),
				])
	var durability: Variant = definition.get("durability", {})
	if not durability is Dictionary:
		errors.append("item:%s:durability_not_dictionary" % definition_id)
	elif not (durability as Dictionary).is_empty():
		var maximum: Variant = (durability as Dictionary).get("maximum", 0)
		if (
			not (maximum is int or maximum is float)
			or not is_equal_approx(float(maximum), roundf(float(maximum)))
			or int(maximum) < 1
		):
			errors.append("item:%s:invalid_maximum_durability" % definition_id)


func _validate_equipment_slot_definition(
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	if str(definition.get("display_name_key", "")) == "":
		errors.append("equipment_slot:%s:missing_display_name_key" % definition_id)
	var accepted_tags: Variant = definition.get("accepts_item_tags_any", [])
	if not accepted_tags is Array or (accepted_tags as Array).is_empty():
		errors.append("equipment_slot:%s:missing_accepted_item_tags" % definition_id)
	if str(definition.get("exclusive_group", "")) == "":
		errors.append("equipment_slot:%s:missing_exclusive_group" % definition_id)


func _validate_feature_header(
		kind: String,
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	if str(definition.get("display_name_key", "")) == "":
		errors.append("%s:%s:missing_display_name_key" % [kind, definition_id])
	_validate_array_field(kind, definition_id, definition, "tags", errors)
	_validate_array_field(kind, definition_id, definition, "modifiers", errors)


func _validate_array_field(
		kind: String,
		definition_id: String,
		definition: Dictionary,
		field: String,
		errors: Array[String]
) -> void:
	if not definition.get(field, []) is Array:
		errors.append("%s:%s:%s_not_array" % [kind, definition_id, field])


func _validate_nonempty_string_array(
		kind: String,
		definition_id: String,
		definition: Dictionary,
		field: String,
		errors: Array[String]
) -> void:
	var values: Variant = definition.get(field, [])
	if not values is Array or (values as Array).is_empty():
		errors.append("%s:%s:missing_%s" % [kind, definition_id, field])
		return
	for value: Variant in values:
		if str(value) == "":
			errors.append("%s:%s:invalid_%s" % [kind, definition_id, field])
			return


func _validate_source_fact_rules(
		kind: String,
		definition_id: String,
		definition: Dictionary,
		errors: Array[String]
) -> void:
	var rules: Variant = definition.get("source_fact_rules", [])
	if not rules is Array or (rules as Array).is_empty():
		errors.append("%s:%s:missing_source_fact_rules" % [kind, definition_id])
		return
	for rule_value: Variant in rules:
		if not rule_value is Dictionary or str(
			(rule_value as Dictionary).get("fact_type", "")
		) == "":
			errors.append("%s:%s:invalid_source_fact_rule" % [kind, definition_id])


func _validate_threshold_rows(
		kind: String,
		definition_id: String,
		rows: Array,
		id_field: String,
		errors: Array[String]
) -> void:
	var ids: Array = []
	var thresholds: Array = []
	for row_value: Variant in rows:
		if not row_value is Dictionary:
			errors.append("%s:%s:threshold_not_dictionary" % [kind, definition_id])
			return
		var row := row_value as Dictionary
		var row_id := str(row.get(id_field, ""))
		if row_id == "" or row_id in ids:
			errors.append("%s:%s:invalid_threshold_id" % [kind, definition_id])
			return
		ids.append(row_id)
		thresholds.append(row.get("threshold", -1))
	if not _ascending_nonnegative_numbers(thresholds):
		errors.append("%s:%s:invalid_threshold_order" % [kind, definition_id])


func _ascending_nonnegative_numbers(values: Array) -> bool:
	var previous := -1.0
	for value: Variant in values:
		if not (value is int or value is float):
			return false
		var number := float(value)
		if number < 0.0 or number <= previous:
			return false
		previous = number
	return true


func _has_duplicate_values(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: Variant in values:
		var key := str(value)
		if key == "" or seen.has(key):
			return true
		seen[key] = true
	return false


func _legacy_definition_id(kind: String, definition: Dictionary) -> String:
	if kind == "state":
		var key := str(definition.get("key", ""))
		return "state.%s" % key if key != "" else ""
	if kind == "object":
		var object_type := str(definition.get("type", ""))
		return "object.%s" % object_type if object_type != "" else ""
	return ""


func _definition_identity_field(kind: String) -> String:
	if kind == "state":
		return "key"
	if kind == "object":
		return "type"
	return ""


func _definition_id_field(kind: String) -> String:
	if kind == "state":
		return "state_def_id"
	if kind == "object":
		return "object_def_id"
	if kind == "talent":
		return "talent_def_id"
	if kind == "trait":
		return "trait_def_id"
	if kind == "mark":
		return "mark_def_id"
	if kind == "skill":
		return "skill_def_id"
	if kind == "item":
		return "item_def_id"
	if kind == "equipment_slot":
		return "slot_def_id"
	return ""


func _normalize_definition(kind: String, data: Dictionary) -> Dictionary:
	var normalized := data.duplicate(true)
	if normalized.has("definition_version"):
		normalized["definition_version"] = int(normalized.get("definition_version"))
	if kind == "mark":
		var stages: Variant = normalized.get("stages", [])
		if stages is Array:
			for stage_value: Variant in stages:
				if stage_value is Dictionary:
					(stage_value as Dictionary)["threshold"] = int(
						(stage_value as Dictionary).get("threshold", 0)
					)
		var progress_rules: Variant = normalized.get("progress_rules", [])
		if progress_rules is Array:
			for rule_value: Variant in progress_rules:
				if rule_value is Dictionary:
					(rule_value as Dictionary)["delta"] = int(
						(rule_value as Dictionary).get("delta", 0)
					)
	if kind == "skill":
		var raw_thresholds: Variant = normalized.get("rank_thresholds", [])
		if raw_thresholds is Array:
			var thresholds: Array = []
			for threshold: Variant in raw_thresholds:
				thresholds.append(
					int(threshold) if threshold is int or threshold is float
					else threshold
				)
			normalized["rank_thresholds"] = thresholds
		var practice_rules: Variant = normalized.get("practice_rules", [])
		if practice_rules is Array:
			for rule_value: Variant in practice_rules:
				if rule_value is Dictionary:
					(rule_value as Dictionary)["xp"] = int(
						(rule_value as Dictionary).get("xp", 0)
					)
	if kind == "item":
		var raw_max_stack: Variant = normalized.get("max_stack", 0)
		if (
			raw_max_stack is int
			or (
				raw_max_stack is float
				and is_equal_approx(
					float(raw_max_stack),
					roundf(float(raw_max_stack))
				)
			)
		):
			normalized["max_stack"] = int(raw_max_stack)
		var durability: Variant = normalized.get("durability", {})
		if durability is Dictionary and (durability as Dictionary).has("maximum"):
			var raw_maximum: Variant = (durability as Dictionary).get("maximum", 0)
			if (
				raw_maximum is int
				or (
					raw_maximum is float
					and is_equal_approx(
						float(raw_maximum),
						roundf(float(raw_maximum))
					)
				)
			):
				(durability as Dictionary)["maximum"] = int(raw_maximum)
	if kind != "state" or str(normalized.get("value_type", "")) != "int":
		return normalized
	for field: String in ["default", "minimum", "maximum"]:
		if not normalized.has(field):
			continue
		var value: Variant = normalized[field]
		if value is float and is_equal_approx(float(value), roundf(float(value))):
			normalized[field] = int(value)
	return normalized


func _array_values_allowed(values: Array, allowed_values: Array) -> bool:
	for value: Variant in values:
		if value not in allowed_values:
			return false
	return true


func _validate_cross_definition_references() -> void:
	var available_slots: Dictionary = list_definitions("equipment_slot")
	for item_id: String in list_definitions("item").keys():
		var definition := get_definition("item", item_id)
		for slot_value: Variant in definition.get("equip_slots", []):
			var short_id := str(slot_value).trim_prefix("slot.")
			var slot_id := "slot.%s" % short_id
			if short_id == "" or not available_slots.has(slot_id):
				_definition_error("item:%s:unknown_equipment_slot:%s" % [
					item_id,
					str(slot_value),
				])


func _definition_value_matches_type(value: Variant, value_type: String) -> bool:
	match value_type:
		"bool":
			return value is bool
		"int":
			return value is int
		"float":
			return value is float or value is int
		"string", "enum":
			return value is String
	return false


func _definition_report(registered_count: int) -> Dictionary:
	return {
		"ok": definition_errors.is_empty(),
		"registered_count": registered_count,
		"total_definition_count": _definition_count(),
		"errors": definition_errors.duplicate(),
		"warnings": definition_warnings.duplicate(),
	}


func _definition_count() -> int:
	var count := 0
	for group: Dictionary in definitions.values():
		count += group.size()
	return count


func _definition_error(message: String) -> bool:
	definition_errors.append(message)
	return false


func _ensure_group(kind: String) -> Dictionary:
	if not definitions.has(kind):
		definitions[kind] = {}
	return definitions[kind]
