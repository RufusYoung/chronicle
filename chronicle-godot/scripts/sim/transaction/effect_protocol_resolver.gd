extends RefCounted
class_name V5EffectProtocolResolver


func append_effects(result: Variant, effects: Variant) -> Dictionary:
	var operations := _normalize_operations(effects)
	var errors: Array[String] = []
	for value: Variant in operations:
		if not value is Dictionary:
			errors.append("effect_not_dictionary")
			continue
		var operation := value as Dictionary
		var error := _append_operation(result, operation)
		if error != "":
			errors.append(error)
	return {
		"ok": errors.is_empty(),
		"operation_count": operations.size(),
		"errors": errors,
	}


func _normalize_operations(effects: Variant) -> Array:
	if effects is Array:
		return (effects as Array).duplicate(true)
	if not effects is Dictionary:
		return []
	var source := effects as Dictionary
	if source.has("operations"):
		return (source.get("operations", []) as Array).duplicate(true)
	var rows: Array = []
	for change: Dictionary in source.get("state_changes", []):
		var row := change.duplicate(true)
		if row.has("to"):
			row["operation"] = "state_set"
		elif row.has("degrade"):
			row["operation"] = "state_degrade"
		else:
			row["operation"] = "state_add"
		rows.append(row)
	for change: Dictionary in source.get("relationship_changes", []):
		var row := change.duplicate(true)
		row["operation"] = "relationship_add"
		rows.append(row)
	for fact: Dictionary in source.get("facts_added", []):
		rows.append({"operation": "fact_add", "fact": fact.duplicate(true)})
	for fact: Dictionary in source.get("facts", []):
		rows.append({"operation": "fact_add", "fact": fact.duplicate(true)})
	for memory: Dictionary in source.get("memories_added", []):
		rows.append({"operation": "memory_add", "memory": memory.duplicate(true)})
	for memory: Dictionary in source.get("memories", []):
		rows.append({"operation": "memory_add", "memory": memory.duplicate(true)})
	for trace: Dictionary in source.get("traces", []):
		rows.append({"operation": "trace_add", "trace": trace.duplicate(true)})
	for rumor: Dictionary in source.get("rumors", []):
		rows.append({"operation": "rumor_add", "rumor": rumor.duplicate(true)})
	for exchange: Dictionary in source.get("exchanges", []):
		rows.append({
			"operation": "exchange_add",
			"exchange": exchange.duplicate(true),
		})
	for obligation: Dictionary in source.get("obligations", []):
		rows.append({
			"operation": "obligation_add",
			"obligation": obligation.duplicate(true),
		})
	for consequence: Dictionary in source.get("deferred_consequences", []):
		rows.append({
			"operation": "deferred_add",
			"consequence": consequence.duplicate(true),
		})
	for change: Dictionary in source.get("pressure_changes", []):
		var row := change.duplicate(true)
		row["operation"] = "pressure_add"
		rows.append(row)
	return rows


func _append_operation(result: Variant, operation: Dictionary) -> String:
	var kind := str(operation.get("operation", ""))
	match kind:
		"state_set":
			result.add_state_change(_without_operation(operation, ["to"]))
		"state_add":
			result.add_state_change(_without_operation(operation, ["delta"]))
		"state_degrade":
			result.add_state_change(_without_operation(operation, ["degrade"]))
		"fact_add":
			result.add_fact(_payload(operation, "fact"))
		"memory_add":
			result.add_memory(_payload(operation, "memory"))
		"relationship_add":
			result.add_relationship_change(_without_operation(operation, ["delta"]))
		"pressure_add":
			result.add_pressure_change(_without_operation(operation, ["delta", "value"]))
		"trace_add":
			result.add_trace(_payload(operation, "trace"))
		"rumor_add":
			result.add_rumor_seed(_payload(operation, "rumor"))
		"chronicle_add":
			result.add_chronicle_entry(_payload(operation, "entry"))
		"investigation_change":
			var investigation_change := _payload(operation, "change")
			var investigation_operation := str(
				investigation_change.get(
					"operation", operation.get("change_operation", "")
				)
			)
			if not investigation_operation in ["create", "update"]:
				return "invalid_investigation_operation:%s" % investigation_operation
			investigation_change["operation"] = investigation_operation
			result.add_investigation_change(investigation_change)
		"item_create", "item_transfer", "item_consume", "item_condition", "item_history":
			var item_change := _without_operation(operation)
			item_change["operation"] = {
				"item_create": "create",
				"item_transfer": "transfer",
				"item_consume": "consume",
				"item_condition": "adjust_durability",
				"item_history": "append_history",
			}[kind]
			result.add_item_change(item_change)
		"equipment_set", "equipment_clear":
			result.add_equipment_change(operation.duplicate(true))
		"obligation_add":
			result.add_obligation(_payload(operation, "obligation"))
		"obligation_update":
			result.add_obligation_update(_without_operation(operation))
		"exchange_add":
			result.add_exchange(_payload(operation, "exchange"))
		"exchange_update":
			result.add_exchange_update(_without_operation(operation))
		"deferred_add":
			result.add_deferred_consequence(_payload(operation, "consequence"))
		"deferred_update":
			result.add_deferred_consequence_update(_without_operation(operation))
		_:
			return "unsupported_effect_operation:%s" % kind
	return ""


func _payload(operation: Dictionary, key: String) -> Dictionary:
	var value: Variant = operation.get(key, {})
	if value is Dictionary and not (value as Dictionary).is_empty():
		return (value as Dictionary).duplicate(true)
	return _without_operation(operation)


func _without_operation(
		operation: Dictionary, required_fields: Array = []
) -> Dictionary:
	var row := operation.duplicate(true)
	row.erase("operation")
	for field: String in required_fields:
		if not row.has(field):
			row[field] = 0
	return row
