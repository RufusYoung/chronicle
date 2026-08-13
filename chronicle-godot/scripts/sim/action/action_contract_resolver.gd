extends RefCounted
class_name V5ActionContractResolver

const OPERATION_ORDER := {
	"set_base": 0,
	"add": 1,
	"multiply": 2,
	"clamp": 3,
}

var registry: Variant = null


func configure(source_registry: Variant) -> void:
	registry = source_registry


func evaluate(
		snapshot: Variant,
		contract: Dictionary,
		actor_id: String = "player",
		target_id: String = ""
) -> Dictionary:
	var requirement_result := evaluate_requirements(
		snapshot,
		contract.get("requirements", []),
		actor_id,
		target_id
	)
	var modifier_result := evaluate_modifiers(
		snapshot,
		contract,
		actor_id,
		target_id
	)
	return {
		"can_execute": bool(requirement_result.get("can_execute", true)),
		"blocked_reason": str(requirement_result.get("blocked_reason", "")),
		"requirements": requirement_result.get("requirements", []),
		"base_values": modifier_result.get("base_values", {}),
		"modified_values": modifier_result.get("modified_values", {}),
		"modifier_explanations": modifier_result.get(
			"modifier_explanations", []
		),
	}


func evaluate_requirements(
		snapshot: Variant,
		requirement_groups: Array,
		actor_id: String = "player",
		target_id: String = ""
) -> Dictionary:
	var rows: Array[Dictionary] = []
	var blocked: Array[String] = []
	for group_value: Variant in requirement_groups:
		if not group_value is Dictionary:
			continue
		var group := group_value as Dictionary
		var conditions: Array = group.get("conditions", [])
		if conditions.is_empty():
			continue
		var mode := str(group.get("mode", "all"))
		var condition_rows: Array[Dictionary] = []
		var met_count := 0
		for condition_value: Variant in conditions:
			if not condition_value is Dictionary:
				continue
			var condition_row := _evaluate_condition(
				snapshot,
				condition_value,
				actor_id,
				target_id
			)
			condition_rows.append(condition_row)
			if bool(condition_row.get("met", false)):
				met_count += 1
		var met := (
			met_count > 0
			if mode == "any"
			else met_count == condition_rows.size()
		)
		var label := str(group.get("label", group.get(
			"requirement_id", "行动条件"
		)))
		var explanation := _requirement_explanation(
			label, mode, condition_rows, met
		)
		rows.append({
			"requirement_id": str(group.get("requirement_id", "")),
			"label": label,
			"mode": mode,
			"met": met,
			"conditions": condition_rows,
			"explanation": explanation,
		})
		if not met:
			blocked.append(explanation)
	return {
		"can_execute": blocked.is_empty(),
		"blocked_reason": "；".join(blocked),
		"requirements": rows,
	}


func evaluate_modifiers(
		snapshot: Variant,
		contract: Dictionary,
		actor_id: String = "player",
		target_id: String = ""
) -> Dictionary:
	var base_values: Dictionary = (
		contract.get("base_values", {}) as Dictionary
	).duplicate(true)
	var collected := _collect_modifiers(snapshot, contract, actor_id)
	collected.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_modifier: Dictionary = left.get("modifier", {})
		var right_modifier: Dictionary = right.get("modifier", {})
		var left_order := int(OPERATION_ORDER.get(
			str(left_modifier.get("operation", "add")), 99
		))
		var right_order := int(OPERATION_ORDER.get(
			str(right_modifier.get("operation", "add")), 99
		))
		if left_order != right_order:
			return left_order < right_order
		return str(left_modifier.get("modifier_id", "")) < str(
			right_modifier.get("modifier_id", "")
		)
	)
	var values := base_values.duplicate(true)
	var explanations: Array[Dictionary] = []
	for entry: Dictionary in collected:
		var modifier: Dictionary = entry.get("modifier", {})
		if not _modifier_matches(
			snapshot, modifier, contract, actor_id, target_id, entry
		):
			continue
		var target := str(modifier.get("target", ""))
		if target == "":
			continue
		var before := float(values.get(target, 0.0))
		var amount := float(modifier.get("value", 0.0))
		var after := _apply_modifier(before, modifier)
		values[target] = after
		explanations.append({
			"modifier_id": str(modifier.get("modifier_id", "")),
			"source_kind": str(entry.get("source_kind", "action")),
			"source_id": str(entry.get("source_id", "")),
			"source_label": str(entry.get("source_label", "未知来源")),
			"target": target,
			"operation": str(modifier.get("operation", "add")),
			"value": amount,
			"before": before,
			"after": after,
			"reason": str(modifier.get(
				"explain_text",
				modifier.get("player_facing_reason", "")
			)),
		})
	return {
		"base_values": base_values,
		"modified_values": values,
		"modifier_explanations": explanations,
	}


func adapt_player_min(
		minimums: Dictionary,
		custom_labels: Dictionary = {}
) -> Array:
	var groups: Array = []
	for key: String in minimums.keys():
		groups.append({
			"requirement_id": "legacy.player_min.%s" % key,
			"label": str(custom_labels.get(key, _attribute_label(key))),
			"mode": "all",
			"conditions": [{
				"kind": "attribute",
				"subject": "actor",
				"key": key,
				"operator": "gte",
				"value": minimums.get(key, 0),
			}],
			"compatibility_adapter": "player_min",
		})
	return groups


func adapt_legacy_state_requirements(requirements: Array) -> Array:
	var groups: Array = []
	for value: Variant in requirements:
		if not value is Dictionary:
			continue
		var requirement := value as Dictionary
		if requirement.has("conditions"):
			groups.append(requirement.duplicate(true))
			continue
		var operator := "gte"
		var required: Variant = requirement.get("min", 0)
		if requirement.has("max"):
			operator = "lte"
			required = requirement.get("max", 0)
		elif requirement.has("equals"):
			operator = "eq"
			required = requirement.get("equals")
		groups.append({
			"requirement_id": "legacy.state.%s.%s" % [
				str(requirement.get("entity_id", "")),
				str(requirement.get("key", "")),
			],
			"label": str(requirement.get("label", "资源")),
			"mode": "all",
			"conditions": [{
				"kind": "state",
				"entity_id": str(requirement.get("entity_id", "")),
				"key": str(requirement.get("key", "")),
				"label": str(requirement.get("label", "资源")),
				"operator": operator,
				"value": required,
			}],
			"compatibility_adapter": "legacy_state_requirement",
		})
	return groups


func adapt_legacy_conditions(conditions: Array) -> Array:
	var groups: Array = []
	for value: Variant in conditions:
		if not value is Dictionary:
			continue
		var condition := value as Dictionary
		if condition.has("conditions"):
			groups.append(condition.duplicate(true))
			continue
		var rows: Array = []
		var base := _legacy_condition_base(condition)
		for pair: Array in [
			["equals", "eq"],
			["not_equals", "neq"],
			["in", "in"],
			["min", "gte"],
			["max", "lte"],
		]:
			if not condition.has(str(pair[0])):
				continue
			var row := base.duplicate(true)
			row["operator"] = str(pair[1])
			row["value"] = condition.get(str(pair[0]))
			rows.append(row)
		if rows.is_empty():
			var row := base.duplicate(true)
			row["operator"] = "eq"
			row["value"] = true
			rows.append(row)
		groups.append({
			"requirement_id": str(condition.get(
				"requirement_id", "legacy.%d" % groups.size()
			)),
			"label": str(condition.get("label", "条件")),
			"mode": "all",
			"conditions": rows,
			"compatibility_adapter": "legacy_condition",
		})
	return groups


func _evaluate_condition(
		snapshot: Variant,
		condition: Dictionary,
		actor_id: String,
		target_id: String
) -> Dictionary:
	var kind := str(condition.get("kind", ""))
	var current: Variant = null
	var label := str(condition.get("label", ""))
	match kind:
		"attribute":
			var attribute_key := str(condition.get("key", ""))
			current = _subject_value(
				snapshot, condition, actor_id, target_id, attribute_key
			)
			if label == "":
				label = _attribute_label(attribute_key)
		"state":
			var entity_id := _subject_id(condition, actor_id, target_id)
			current = snapshot.get_entity_state(
				entity_id, str(condition.get("key", "")), null
			)
			if label == "":
				label = str(condition.get("key", "状态"))
		"region_state":
			current = snapshot.get_region_state_value(
				str(condition.get("key", "")), null
			)
			if label == "":
				label = str(condition.get("key", "地区状态"))
		"institution":
			current = snapshot.get_institution_value(
				str(condition.get("key", "")), null
			)
			if label == "":
				label = str(condition.get("key", "制度状态"))
		"talent":
			current = _has_feature(
				snapshot.get_talent_assignments(actor_id),
				"talent_def_id", str(condition.get("talent_def_id", ""))
			)
			label = _label_or_definition(label, "talent", str(
				condition.get("talent_def_id", "")
			))
		"trait":
			current = _has_feature(
				snapshot.get_trait_instances(actor_id),
				"trait_def_id", str(condition.get("trait_def_id", ""))
			)
			label = _label_or_definition(label, "trait", str(
				condition.get("trait_def_id", "")
			))
		"mark_stage":
			var mark_id := str(condition.get("mark_def_id", ""))
			current = _feature_stage(
				snapshot.get_mark_instances(actor_id), "mark_def_id", mark_id
			)
			label = _label_or_definition(label, "mark", mark_id)
		"skill_rank":
			var skill_id := str(condition.get("skill_def_id", ""))
			current = _skill_rank(snapshot, actor_id, skill_id)
			label = _label_or_definition(label, "skill", skill_id)
		"item_owned":
			var owner_id := _resolve_side(
				str(condition.get("owner", "actor")), actor_id, target_id
			)
			current = _owned_item_quantity(snapshot, owner_id, condition)
			if label == "":
				label = "持有物品"
		"item_equipped":
			var equipment_owner_id := _resolve_side(
				str(condition.get("owner", "actor")), actor_id, target_id
			)
			current = _has_equipped_item(
				snapshot, equipment_owner_id, condition
			)
			if label == "":
				label = "已装备物品"
		"relationship_axis":
			var source_id := _resolve_side(
				str(condition.get("source", "actor")), actor_id, target_id
			)
			var relation_target := _resolve_side(
				str(condition.get("target", "target")), actor_id, target_id
			)
			current = snapshot.get_relation(
				source_id, relation_target, str(condition.get("axis", "")), 0
			)
			if label == "":
				label = str(condition.get("axis", "关系"))
		"fact_exists":
			current = _fact_exists(snapshot, condition, actor_id, target_id)
			if label == "":
				label = "已发生事实"
		"memory_exists":
			current = _memory_exists(snapshot, condition, actor_id)
			if label == "":
				label = "已有记忆"
		"pressure":
			current = _pressure_value(snapshot, condition)
			if label == "":
				label = str(condition.get("pressure_type", "压力"))
		"context_tag":
			current = str(condition.get("tag", "")) in snapshot.get_location_tags()
			if label == "":
				label = "环境：%s" % str(condition.get("tag", ""))
		"world_time":
			var world_time: Dictionary = snapshot.get("world_time")
			current = world_time.get(str(condition.get("key", "hour")), null)
			if label == "":
				label = "世界时间"
		_:
			label = label if label != "" else "未知条件"
	var operator := str(condition.get(
		"operator", "eq" if current is bool else "gte"
	))
	var required: Variant = condition.get("value", true if current is bool else 0)
	var comparison_current: Variant = current
	var comparison_required: Variant = required
	var comparable := true
	if kind == "mark_stage":
		var mark_definition := _definition(
			"mark", str(condition.get("mark_def_id", ""))
		)
		comparison_current = _mark_stage_rank(mark_definition, str(current))
		comparison_required = _mark_stage_rank(mark_definition, str(required))
		comparable = int(comparison_current) >= 0 and int(
			comparison_required
		) >= 0
	var met := comparable and _compare(
		comparison_current, operator, comparison_required
	)
	return {
		"kind": kind,
		"label": label,
		"current": current,
		"required": required,
		"operator": operator,
		"met": met,
		"explanation": _condition_explanation(label, current, operator, required),
	}


func _collect_modifiers(
		snapshot: Variant,
		contract: Dictionary,
		actor_id: String
) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_append_modifier_rows(rows, contract.get("modifiers", []), {
		"source_kind": "action",
		"source_id": str(contract.get("action_id", contract.get("duty_id", ""))),
		"source_label": str(contract.get("label", "行动")),
	})
	if snapshot.has_method("get_talent_assignments"):
		for assignment: Dictionary in snapshot.get_talent_assignments(actor_id):
			_append_definition_modifiers(
				rows, "talent", assignment, "talent_def_id"
			)
	if snapshot.has_method("get_trait_instances"):
		for instance: Dictionary in snapshot.get_trait_instances(actor_id):
			if str(instance.get("status", "active")) == "active":
				_append_definition_modifiers(
					rows, "trait", instance, "trait_def_id"
				)
	if snapshot.has_method("get_mark_instances"):
		for instance: Dictionary in snapshot.get_mark_instances(actor_id):
			if str(instance.get("status", "active")) == "active":
				_append_definition_modifiers(rows, "mark", instance, "mark_def_id")
	if snapshot.has_method("get_skill_progress"):
		for progress: Dictionary in snapshot.get_skill_progress(actor_id):
			_append_definition_modifiers(rows, "skill", progress, "skill_def_id")
	if not snapshot.has_method("get_equipment_loadout"):
		return rows
	var loadout: Dictionary = snapshot.get_equipment_loadout(actor_id)
	for item_value: Variant in (loadout.get("slots", {}) as Dictionary).values():
		if item_value == null or str(item_value) == "":
			continue
		var item: Dictionary = snapshot.get_item(str(item_value))
		_append_modifier_rows(rows, item.get("modifiers", []), {
			"source_kind": "equipment",
			"source_id": str(item.get("item_instance_id", "")),
			"source_label": str(item.get(
				"display_name", item.get("item_def_id", "装备")
			)),
			"source_data": item,
		})
	return rows


func _append_definition_modifiers(
		rows: Array[Dictionary],
		kind: String,
		instance: Dictionary,
		id_field: String
) -> void:
	var definition_id := str(instance.get(id_field, ""))
	var definition := _definition(kind, definition_id)
	if definition.is_empty():
		return
	_append_modifier_rows(rows, definition.get("modifiers", []), {
		"source_kind": kind,
		"source_id": definition_id,
		"source_label": _definition_label(definition, definition_id),
		"source_data": instance,
	})


func _append_modifier_rows(
		rows: Array[Dictionary],
		modifiers: Array,
		source: Dictionary
) -> void:
	for value: Variant in modifiers:
		if not value is Dictionary:
			continue
		var row := source.duplicate(true)
		row["modifier"] = (value as Dictionary).duplicate(true)
		rows.append(row)


func _modifier_matches(
		snapshot: Variant,
		modifier: Dictionary,
		contract: Dictionary,
		actor_id: String,
		target_id: String,
		entry: Dictionary
) -> bool:
	var source_data: Dictionary = entry.get("source_data", {})
	if entry.get("source_kind") == "skill" and int(source_data.get(
		"rank", 0
	)) < int(modifier.get("minimum_rank", 0)):
		return false
	var action_tags: Array = contract.get("action_tags", [])
	var context_tags: Array = snapshot.get_location_tags()
	for tag: Variant in contract.get("context_tags", []):
		if tag not in context_tags:
			context_tags.append(tag)
	for condition_value: Variant in modifier.get("when", []):
		if not condition_value is Dictionary:
			return false
		var condition := condition_value as Dictionary
		match str(condition.get("kind", "")):
			"action_tag":
				if str(condition.get("tag", "")) not in action_tags:
					return false
			"context_tag":
				if str(condition.get("tag", "")) not in context_tags:
					return false
			_:
				if not bool(_evaluate_condition(
					snapshot, condition, actor_id, target_id
				).get("met", false)):
					return false
	return true


func _apply_modifier(current: float, modifier: Dictionary) -> float:
	match str(modifier.get("operation", "add")):
		"set_base":
			return float(modifier.get("value", current))
		"add":
			return current + float(modifier.get("value", 0.0))
		"multiply":
			return current * float(modifier.get("value", 1.0))
		"clamp":
			return clampf(
				current,
				float(modifier.get("min", -INF)),
				float(modifier.get("max", INF))
			)
	return current


func _subject_value(
		snapshot: Variant,
		condition: Dictionary,
		actor_id: String,
		target_id: String,
		key: String
) -> Variant:
	var entity_id := _subject_id(condition, actor_id, target_id)
	if entity_id == actor_id and actor_id == str(snapshot.get_player_value(
		"id", "player"
	)):
		return snapshot.get_player_value(key, null)
	return snapshot.get_entity_state(entity_id, key, null)


func _subject_id(
		condition: Dictionary, actor_id: String, target_id: String
) -> String:
	var explicit := str(condition.get("entity_id", ""))
	if explicit != "":
		return _resolve_side(explicit, actor_id, target_id)
	return _resolve_side(str(condition.get("subject", "actor")), actor_id, target_id)


func _resolve_side(value: String, actor_id: String, target_id: String) -> String:
	match value:
		"actor":
			return actor_id
		"player":
			return "player"
		"target":
			return target_id
	return value


func _has_feature(rows: Array, id_field: String, definition_id: String) -> bool:
	for row: Dictionary in rows:
		if (
			str(row.get(id_field, "")) == definition_id
			and str(row.get("status", "active")) == "active"
		):
			return true
	return false


func _feature_stage(rows: Array, id_field: String, definition_id: String) -> String:
	for row: Dictionary in rows:
		if (
			str(row.get(id_field, "")) == definition_id
			and str(row.get("status", "active")) == "active"
		):
			return str(row.get("stage_id", ""))
	return ""


func _mark_stage_rank(definition: Dictionary, stage_id: String) -> int:
	var index := 0
	for value: Variant in definition.get("stages", []):
		if value is Dictionary and str(
			(value as Dictionary).get("stage_id", "")
		) == stage_id:
			return index
		index += 1
	return -1


func _skill_rank(snapshot: Variant, actor_id: String, skill_id: String) -> int:
	for progress: Dictionary in snapshot.get_skill_progress(actor_id):
		if str(progress.get("skill_def_id", "")) == skill_id:
			return int(progress.get("rank", 0))
	return 0


func _owned_item_quantity(
		snapshot: Variant, actor_id: String, condition: Dictionary
) -> int:
	var quantity := 0
	for item: Dictionary in snapshot.get_items():
		var holder: Dictionary = item.get("holder", {})
		if str(holder.get("kind", "")) != "entity" or str(
			holder.get("id", "")
		) != actor_id:
			continue
		if _item_matches(item, condition):
			quantity += int(item.get("quantity", 0))
	return quantity


func _has_equipped_item(
		snapshot: Variant, actor_id: String, condition: Dictionary
) -> bool:
	var loadout: Dictionary = snapshot.get_equipment_loadout(actor_id)
	for item_value: Variant in (loadout.get("slots", {}) as Dictionary).values():
		if item_value == null:
			continue
		if _item_matches(snapshot.get_item(str(item_value)), condition):
			return true
	return false


func _item_matches(item: Dictionary, condition: Dictionary) -> bool:
	var definition_id := str(condition.get("item_def_id", ""))
	if definition_id != "" and str(item.get("item_def_id", "")) != definition_id:
		return false
	var tag := str(condition.get("tag", ""))
	return tag == "" or tag in (item.get("tags", []) as Array)


func _fact_exists(
		snapshot: Variant,
		condition: Dictionary,
		actor_id: String,
		target_id: String
) -> bool:
	for fact: Dictionary in snapshot.get_facts():
		if _record_matches(fact, condition, actor_id, target_id):
			return true
	return false


func _memory_exists(
		snapshot: Variant, condition: Dictionary, actor_id: String
) -> bool:
	var owner_id := _resolve_side(
		str(condition.get("owner", "actor")), actor_id, ""
	)
	for memory: Dictionary in snapshot.get_memories(owner_id):
		if _record_matches(memory, condition, actor_id, ""):
			return true
	return false


func _record_matches(
		record: Dictionary,
		condition: Dictionary,
		actor_id: String,
		target_id: String
) -> bool:
	for key: String in ["fact_type", "memory_type"]:
		if condition.has(key) and record.get(key) != condition.get(key):
			return false
	for key: String in (condition.get("field_equals", {}) as Dictionary).keys():
		if record.get(key) != condition.get("field_equals", {}).get(key):
			return false
	var required_actor := str(condition.get("actor", ""))
	if required_actor != "" and str(
		record.get("actor_id", "")
	) != _resolve_side(required_actor, actor_id, target_id):
		return false
	return true


func _pressure_value(snapshot: Variant, condition: Dictionary) -> int:
	var total := 0
	for pressure: Dictionary in snapshot.get_pressures():
		if (
			str(pressure.get("scope_id", "")) == str(condition.get("scope_id", ""))
			and str(pressure.get("pressure_type", "")) == str(
				condition.get("pressure_type", "")
			)
		):
			total += int(pressure.get("value", 0))
	return total


func _compare(current: Variant, operator: String, required: Variant) -> bool:
	match operator:
		"eq", "equals":
			return current == required
		"neq", "not_equals":
			return current != required
	if current == null:
		return false
	match operator:
		"gte":
			return float(current) >= float(required)
		"gt":
			return float(current) > float(required)
		"lte":
			return float(current) <= float(required)
		"lt":
			return float(current) < float(required)
		"contains":
			return required in current
		"in":
			return required is Array and current in required
	return false


func _requirement_explanation(
		label: String, mode: String, conditions: Array, met: bool
) -> String:
	if conditions.size() == 1:
		return str((conditions[0] as Dictionary).get("explanation", label))
	var parts: Array[String] = []
	for condition: Dictionary in conditions:
		parts.append(str(condition.get("explanation", "")))
	var joiner := " 或 " if mode == "any" else " 且 "
	return "%s%s：%s" % [
		label,
		"已满足" if met else "未满足",
		joiner.join(parts),
	]


func _condition_explanation(
		label: String, current: Variant, operator: String, required: Variant
) -> String:
	var numeric_values := (
		(current is int or current is float)
		and (required is int or required is float)
	)
	if numeric_values and operator == "gte" and float(current) < float(required):
		return "%s不足：需要 %s，当前 %s" % [
			label, _value_text(required), _value_text(current)
		]
	if numeric_values and operator == "lte" and float(current) > float(required):
		return "%s超出：至多 %s，当前 %s" % [
			label, _value_text(required), _value_text(current)
		]
	var operator_label: String = {
		"eq": "需要",
		"equals": "需要",
		"gte": "至少",
		"gt": "高于",
		"lte": "至多",
		"lt": "低于",
		"contains": "包含",
	}.get(operator, operator)
	if current is bool:
		return "%s%s（当前%s）" % [
			label,
			"具备" if bool(required) else "不具备",
			"具备" if bool(current) else "不具备",
		]
	return "%s%s %s（当前 %s）" % [
		label, operator_label, _value_text(required), _value_text(current)
	]


func _value_text(value: Variant) -> String:
	if value is int:
		return str(value)
	if value is float and is_equal_approx(float(value), round(float(value))):
		return str(int(value))
	return str(value)


func _label_or_definition(label: String, kind: String, definition_id: String) -> String:
	if label != "":
		return label
	return _definition_label(_definition(kind, definition_id), definition_id)


func _definition(kind: String, definition_id: String) -> Dictionary:
	if registry == null or not registry.has_method("get_definition"):
		return {}
	return registry.get_definition(kind, definition_id)


func _definition_label(definition: Dictionary, fallback: String) -> String:
	return str(definition.get(
		"display_name", definition.get("display_name_key", fallback)
	))


func _legacy_condition_base(condition: Dictionary) -> Dictionary:
	var source := str(condition.get("source", "entity_state"))
	match source:
		"region_state":
			return {
				"kind": "region_state",
				"key": str(condition.get("key", "")),
				"label": str(condition.get("label", condition.get("key", "地区状态"))),
			}
		"institution":
			return {
				"kind": "institution",
				"key": str(condition.get("key", "")),
				"label": str(condition.get("label", condition.get("key", "制度状态"))),
			}
		"relationship":
			return {
				"kind": "relationship_axis",
				"source": str(condition.get("source_id", "actor")),
				"target": str(condition.get("target_id", "player")),
				"axis": str(condition.get("axis", "trust")),
				"label": str(condition.get("label", condition.get("axis", "关系"))),
			}
		"fact":
			return {
				"kind": "fact_exists",
				"fact_type": str(condition.get("fact_type", "")),
				"actor": str(condition.get("actor_id", "")),
				"label": str(condition.get("label", "事实")),
			}
	return {
		"kind": "state",
		"entity_id": str(condition.get("entity_id", "actor")),
		"key": str(condition.get("key", "")),
		"label": str(condition.get("label", condition.get("key", "状态"))),
	}


func _attribute_label(key: String) -> String:
	return {
		"strength": "力量",
		"dexterity": "敏捷",
		"wisdom": "智慧",
		"charisma": "魅力",
		"constitution": "体质",
		"perception": "感知",
		"food_count": "食物",
		"health": "健康",
	}.get(key, key)
