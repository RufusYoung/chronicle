extends RefCounted
class_name V5TransactionWorldWriter

const EXTERNAL_PROJECTION_KEYS := [
	"food_count",
	"injury",
	"mist_salt_echo",
	"inventory_item_ids",
]

const STORE_REQUIREMENTS := {
	"facts_added": "fact_store",
	"state_changes": "state_store",
	"relationship_changes": "relationship_store",
	"memories_added": "memory_store",
	"traces_added": "trace_store",
	"rumors_added": "rumor_store",
	"pressure_changes": "pressure_store",
	"obligations_added": "obligation_store",
	"obligation_updates": "obligation_store",
	"exchanges_added": "exchange_store",
	"exchange_updates": "exchange_store",
	"deferred_consequences_added": "deferred_consequence_store",
	"deferred_consequence_updates": "deferred_consequence_store",
	"item_changes": "item_store",
	"resource_changes": "resource_stock_store",
	"equipment_changes": "equipment_store",
	"character_feature_changes": "character_feature_store",
	"chronicle_entries_added": "chronicle_store",
	"investigation_changes": "investigation_store",
}

var last_report: Dictionary = {"ok": true, "error": ""}


func apply_result(result: Variant, stores: Dictionary) -> bool:
	last_report = _validate_store_coverage(result, stores)
	if not bool(last_report.get("ok", false)):
		return _reject(result, last_report)

	var preview_report := _build_preview_stores(stores)
	if not bool(preview_report.get("ok", false)):
		last_report = preview_report
		return _reject(result, last_report)
	var preview_stores: Dictionary = preview_report.get("stores", {})
	var apply_report := _apply_to_stores(result, preview_stores)
	if not bool(apply_report.get("ok", false)):
		last_report = apply_report
		return _reject(result, last_report)

	var equipment_store: Variant = preview_stores.get("equipment_store")
	if equipment_store != null:
		var integrity: Dictionary = equipment_store.validate_integrity()
		if not bool(integrity.get("ok", false)):
			last_report = {
				"ok": false,
				"error": "equipment_integrity_failed:%s" % str(
					(integrity.get("errors", ["unknown_error"]) as Array)[0]
				),
				"phase": "preflight",
			}
			return _reject(result, last_report)

	_commit_preview(preview_stores, stores)
	last_report = {
		"ok": true,
		"error": "",
		"phase": "committed",
		"store_count": preview_stores.size(),
	}
	return true


func _apply_to_stores(result: Variant, stores: Dictionary) -> Dictionary:
	var fact_store: Variant = stores.get("fact_store")
	if fact_store != null:
		for fact: Dictionary in result.facts_added:
			fact_store.add_fact(fact)

	var state_store: Variant = stores.get("state_store")
	if state_store != null:
		for state_change: Dictionary in result.state_changes:
			if str(state_change.get("key", "")) in EXTERNAL_PROJECTION_KEYS:
				continue
			if not state_store.apply_state_change(state_change):
				return _store_failure("state_store", state_store)

	var character_feature_store: Variant = stores.get(
		"character_feature_store"
	)
	if character_feature_store != null:
		for feature_change: Dictionary in result.character_feature_changes:
			if not character_feature_store.apply_change(feature_change):
				return _store_failure(
					"character_feature_store", character_feature_store
				)
		character_feature_store.apply_facts(result.facts_added)

	var relationship_store: Variant = stores.get("relationship_store")
	if relationship_store != null:
		for relationship_change: Dictionary in result.relationship_changes:
			relationship_store.apply_relationship_change(relationship_change)

	var memory_store: Variant = stores.get("memory_store")
	if memory_store != null:
		for memory: Dictionary in result.memories_added:
			memory_store.add_memory(memory)

	var trace_store: Variant = stores.get("trace_store")
	if trace_store != null:
		for trace: Dictionary in result.traces_added:
			trace_store.add_trace(trace)

	var rumor_store: Variant = stores.get("rumor_store")
	if rumor_store != null:
		for rumor: Dictionary in result.rumors_added:
			rumor_store.add_rumor_seed(rumor)

	var pressure_store: Variant = stores.get("pressure_store")
	if pressure_store != null:
		for pressure_change: Dictionary in result.pressure_changes:
			pressure_store.add_pressure_change(pressure_change)

	var obligation_store: Variant = stores.get("obligation_store")
	if obligation_store != null:
		for obligation: Dictionary in result.obligations_added:
			obligation_store.add_obligation(obligation)
		for obligation_update: Dictionary in result.obligation_updates:
			if not obligation_store.apply_obligation_update(obligation_update):
				return _store_failure("obligation_store", obligation_store)

	var exchange_store: Variant = stores.get("exchange_store")
	if exchange_store != null:
		for exchange: Dictionary in result.exchanges_added:
			exchange_store.add_exchange(exchange)
		for exchange_update: Dictionary in result.exchange_updates:
			if not exchange_store.apply_exchange_update(exchange_update):
				return _store_failure("exchange_store", exchange_store)

	var deferred_store: Variant = stores.get("deferred_consequence_store")
	if deferred_store != null:
		for consequence: Dictionary in result.deferred_consequences_added:
			deferred_store.add_deferred_consequence(consequence)
		for update: Dictionary in result.deferred_consequence_updates:
			if not deferred_store.apply_deferred_consequence_update(update):
				return _store_failure(
					"deferred_consequence_store", deferred_store
				)

	var item_store: Variant = stores.get("item_store")
	if item_store != null:
		for item_change: Dictionary in result.item_changes:
			if not item_store.apply_item_change(item_change):
				return _store_failure("item_store", item_store)

	var resource_stock_store: Variant = stores.get("resource_stock_store")
	if resource_stock_store != null:
		for resource_change: Dictionary in result.resource_changes:
			if not resource_stock_store.apply_resource_change(resource_change):
				return _store_failure(
					"resource_stock_store", resource_stock_store
				)

	var equipment_store: Variant = stores.get("equipment_store")
	if equipment_store != null:
		for equipment_change: Dictionary in result.equipment_changes:
			if not equipment_store.apply_equipment_change(equipment_change):
				return _store_failure("equipment_store", equipment_store)

	var chronicle_store: Variant = stores.get("chronicle_store")
	if chronicle_store != null:
		for entry: Dictionary in result.chronicle_entries_added:
			chronicle_store.add_entry(entry)

	var investigation_store: Variant = stores.get("investigation_store")
	if investigation_store != null:
		for change: Dictionary in result.investigation_changes:
			investigation_store.apply_change(change)
	return {"ok": true, "error": "", "phase": "preflight"}


func _validate_store_coverage(result: Variant, stores: Dictionary) -> Dictionary:
	if result == null:
		return {
			"ok": false,
			"error": "transaction_result_missing",
			"phase": "contract",
		}
	if str(result.get("contract_status")) == "invalid_contract":
		return {
			"ok": false,
			"error": "transaction_contract_invalid:%s" % str(
				result.get("error_reason")
			),
			"phase": "contract",
		}
	for result_property: String in STORE_REQUIREMENTS.keys():
		var values: Variant = result.get(result_property)
		if values is Array and not (values as Array).is_empty():
			var store_key := str(STORE_REQUIREMENTS[result_property])
			if stores.get(store_key) == null:
				return {
					"ok": false,
					"error": "required_store_missing:%s:%s" % [
						result_property, store_key
					],
					"phase": "contract",
				}
	return {"ok": true, "error": "", "phase": "contract"}


func _build_preview_stores(stores: Dictionary) -> Dictionary:
	var preview: Dictionary = {}
	var instance_map: Dictionary = {}
	for key: String in stores.keys():
		var source: Variant = stores.get(key)
		if source == null or source.get_script() == null:
			return {
				"ok": false,
				"error": "store_not_cloneable:%s" % key,
				"phase": "preflight_setup",
			}
		var clone: Variant = source.get_script().new()
		_copy_script_properties(source, clone, false, {})
		preview[key] = clone
		instance_map[source.get_instance_id()] = clone
	for key: String in stores.keys():
		_reconnect_store_references(
			stores.get(key), preview.get(key), instance_map
		)
	return {
		"ok": true,
		"error": "",
		"phase": "preflight_setup",
		"stores": preview,
	}


func _commit_preview(preview: Dictionary, stores: Dictionary) -> void:
	for key: String in preview.keys():
		_copy_script_properties(preview.get(key), stores.get(key), true, {})


func _copy_script_properties(
		source: Variant,
		target: Variant,
		skip_object_references: bool,
		object_map: Dictionary
) -> void:
	for property: Dictionary in source.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var property_name := str(property.get("name", ""))
		if property_name == "":
			continue
		var value: Variant = source.get(property_name)
		if value is Object:
			if skip_object_references:
				continue
			var instance_id: int = value.get_instance_id()
			target.set(property_name, object_map.get(instance_id, value))
		elif value is Dictionary or value is Array:
			target.set(property_name, value.duplicate(true))
		else:
			target.set(property_name, value)


func _reconnect_store_references(
		source: Variant, target: Variant, instance_map: Dictionary
) -> void:
	for property: Dictionary in source.get_property_list():
		if int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var property_name := str(property.get("name", ""))
		var value: Variant = source.get(property_name)
		if value is Object and instance_map.has(value.get_instance_id()):
			target.set(property_name, instance_map[value.get_instance_id()])


func _store_failure(store_key: String, store: Variant) -> Dictionary:
	var detail := "operation_rejected"
	if _has_script_property(store, "last_error"):
		var candidate: Variant = store.get("last_error")
		if candidate != null and str(candidate) != "":
			detail = str(candidate)
	return {
		"ok": false,
		"error": "%s:%s" % [store_key, detail],
		"phase": "preflight",
	}


func _has_script_property(source: Variant, property_name: String) -> bool:
	for property: Dictionary in source.get_property_list():
		if (
			str(property.get("name", "")) == property_name
			and int(property.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE != 0
		):
			return true
	return false


func _reject(result: Variant, report: Dictionary) -> bool:
	if result != null and result.has_method("mark_invalid_contract"):
		result.mark_invalid_contract(
			str(result.transaction_mode),
			str(report.get("error", "transaction_preflight_failed"))
		)
	return false
